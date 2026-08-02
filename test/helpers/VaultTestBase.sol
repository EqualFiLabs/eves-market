// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {EveMarketDiamond} from "../../src/EveMarketDiamond.sol";
import {EveUSDC} from "../../src/EveUSDC.sol";
import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {VaultRouterFacet} from "../../src/facets/VaultRouterFacet.sol";
import {IVaultRouter} from "../../src/interfaces/IVaultRouter.sol";
import {LibFixedPointMath} from "../../src/libraries/LibFixedPointMath.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";

import {MockUSDC} from "./MockUSDC.sol";

abstract contract VaultTestBase is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant VAULT_VIRTUAL_ASSETS = 1;
    uint256 internal constant VAULT_VIRTUAL_SHARES = 1;
    uint8 internal constant EVE_ETH_PROFILE_ID = 1;

    MockUSDC internal usdc;
    EveUSDC internal eveUSDC;
    SEveUSDCVault internal vault;
    CanonicalWETH9 internal weth;
    EveETH internal eveETH;
    IVaultRouter internal router;
    EveMarketDiamond internal diamond;

    address internal owner;
    address internal onramp;
    address internal offramp;
    address internal feeRecipient;
    address internal revenueNotifier;
    address internal alice;
    address internal bob;
    address internal carol;
    address internal receiver;

    uint16 internal constant DEFAULT_AUM_FEE_BPS = 200;

    function setUp() public virtual {
        owner = makeAddr("vault-owner");
        onramp = makeAddr("vault-onramp");
        offramp = makeAddr("vault-offramp");
        feeRecipient = makeAddr("vault-fee-recipient");
        revenueNotifier = makeAddr("vault-revenue-notifier");
        alice = makeAddr("vault-alice");
        bob = makeAddr("vault-bob");
        carol = makeAddr("vault-carol");
        receiver = makeAddr("vault-receiver");

        usdc = new MockUSDC();
        eveUSDC = new EveUSDC(address(usdc), onramp, offramp);
        vault = _deployVault(DEFAULT_AUM_FEE_BPS);
        weth = new CanonicalWETH9();
        eveETH = new EveETH(address(weth));
        diamond = new EveMarketDiamond(owner, address(new DiamondCutFacet()));

        _addFacet(address(new DiamondLoupeFacet()), _loupeSelectors());
        _addFacet(address(new OwnershipFacet()), _ownershipSelectors());
        _addFacet(address(new VaultRouterFacet()), _routerSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(address(eveUSDC));
        OwnershipFacet(address(diamond)).setStakingVault(address(vault));
        OwnershipFacet(address(diamond))
            .setCollateralProfile(EVE_ETH_PROFILE_ID, address(eveETH), address(weth), uint128(WAD), 0, true);
        vm.stopPrank();

        router = IVaultRouter(address(diamond));
    }

    function _deployVault(uint16 feeBps) internal returns (SEveUSDCVault) {
        return new SEveUSDCVault(address(eveUSDC), owner, feeRecipient, feeBps, revenueNotifier);
    }

    function _setLendingContract(address lending) internal {
        vm.prank(owner);
        vault.setLendingContract(lending);
    }

    function _seedEveUSDC(address account, uint256 amount) internal {
        usdc.mint(address(eveUSDC), amount);

        vm.prank(onramp);
        eveUSDC.mint(account, amount);
    }

    function _approveAsset(address account, uint256 amount) internal {
        vm.prank(account);
        eveUSDC.approve(address(vault), amount);
    }

    function _depositSeeded(address account, uint256 assets, address vaultReceiver) internal returns (uint256 shares) {
        _seedEveUSDC(account, assets);
        _approveAsset(account, assets);

        vm.prank(account);
        shares = vault.deposit(assets, vaultReceiver);
    }

    function _notifyRevenue(uint256 assets) internal {
        _seedEveUSDC(revenueNotifier, assets);

        vm.startPrank(revenueNotifier);
        eveUSDC.approve(address(vault), assets);
        vault.notifyRevenue(assets);
        vm.stopPrank();
    }

    function _assertRouterBalancesZero() internal view {
        assertEq(usdc.balanceOf(address(diamond)), 0);
        assertEq(eveUSDC.balanceOf(address(diamond)), 0);
        assertEq(vault.balanceOf(address(diamond)), 0);
        assertEq(weth.balanceOf(address(diamond)), 0);
        assertEq(eveETH.balanceOf(address(diamond)), 0);
        assertEq(address(diamond).balance, 0);
    }

    function _addFacet(address facetAddress, bytes4[] memory selectors) internal {
        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: facetAddress, action: DiamondCutFacet.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), new bytes(0));
    }

    function _loupeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = DiamondLoupeFacet.facets.selector;
        selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        selectors[3] = DiamondLoupeFacet.facetAddress.selector;
    }

    function _ownershipSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](38);
        selectors[0] = OwnershipFacet.transferOwnership.selector;
        selectors[1] = OwnershipFacet.owner.selector;
        selectors[2] = OwnershipFacet.setOrderbookEntryFeeBps.selector;
        selectors[3] = OwnershipFacet.setResolutionBondConfig.selector;
        selectors[4] = OwnershipFacet.setMarketCreationFee.selector;
        selectors[5] = OwnershipFacet.setMarketCreationBond.selector;
        selectors[6] = OwnershipFacet.setPermissionlessCreationEnabled.selector;
        selectors[7] = OwnershipFacet.setDefaultConditionalTokens.selector;
        selectors[8] = OwnershipFacet.setCollateralToken.selector;
        selectors[9] = OwnershipFacet.setEveToken.selector;
        selectors[10] = OwnershipFacet.setEveTreasury.selector;
        selectors[11] = OwnershipFacet.setStakingVault.selector;
        selectors[12] = OwnershipFacet.setOrderbookFeeSplit.selector;
        selectors[13] = OwnershipFacet.setParimutuelFeeSplit.selector;
        selectors[14] = OwnershipFacet.setParimutuelConfig.selector;
        selectors[15] = OwnershipFacet.setDurationParams.selector;
        selectors[16] = OwnershipFacet.setDisputeWindow.selector;
        selectors[17] = OwnershipFacet.setCreatorSettleGrace.selector;
        selectors[18] = OwnershipFacet.setOpenResolutionTimeout.selector;
        selectors[19] = OwnershipFacet.setMaxEscalation.selector;
        selectors[20] = OwnershipFacet.registerCurveProfile.selector;
        selectors[21] = OwnershipFacet.setSpotBookCreationFee.selector;
        selectors[22] = OwnershipFacet.setSpotTradeFeeBps.selector;
        selectors[23] = OwnershipFacet.setSpotFeeSplit.selector;
        selectors[24] = OwnershipFacet.setParimutuelCreationSeedAmount.selector;
        selectors[25] = OwnershipFacet.setCollateralProfile.selector;
        selectors[26] = OwnershipFacet.setCollateralProfileEnabled.selector;
        selectors[27] = OwnershipFacet.setCollateralProfilePayoutUnit.selector;
        selectors[28] = OwnershipFacet.setCollateralProfileMarketCreationFee.selector;
        selectors[29] = OwnershipFacet.setCollateralProfileParimutuelCreationSeedAmount.selector;
        selectors[30] = OwnershipFacet.setCollateralProfileParimutuelMinEntry.selector;
        selectors[31] = OwnershipFacet.setCollateralProfileParlayUnderwritingFee.selector;
        selectors[32] = OwnershipFacet.setDelayedOrderConfig.selector;
        selectors[33] = OwnershipFacet.setDelayedOrderProcessing.selector;
        selectors[34] = OwnershipFacet.setDelayedOrderProtocolProcessor.selector;
        selectors[35] = OwnershipFacet.setMarketDelayedExecution.selector;
        selectors[36] = OwnershipFacet.setBookDelayedExecution.selector;
        selectors[37] = OwnershipFacet.setSecondaryStakingVault.selector;
    }

    function _routerSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IVaultRouter.wrapAndDeposit.selector;
        selectors[1] = IVaultRouter.redeemAndUnwrap.selector;
        selectors[2] = IVaultRouter.wrapETHToEveETH.selector;
    }

    function _postAccrualAssets(SEveUSDCVault target)
        internal
        view
        returns (uint256 assetsAfter, uint256 feeAssets, uint256 epochs)
    {
        (feeAssets, epochs) = target.previewAccruedAum();
        assetsAfter = target.totalAssets() - feeAssets;
    }

    function _managedAssets(SEveUSDCVault target) internal view returns (uint256) {
        uint256 grossAssets = eveUSDC.balanceOf(address(target)) + target.outstandingPrincipal();
        uint256 liabilities = target.recognizedLosses() + target.unpaidAumFees();

        return grossAssets > liabilities ? grossAssets - liabilities : 0;
    }

    function _expectedDepositShares(SEveUSDCVault target, uint256 assets) internal view returns (uint256) {
        uint256 supply = target.totalSupply();
        (uint256 assetsAfter,,) = _postAccrualAssets(target);

        if (supply == 0) {
            return assets;
        }

        return Math.mulDiv(assets, supply + VAULT_VIRTUAL_SHARES, assetsAfter + VAULT_VIRTUAL_ASSETS);
    }

    function _expectedMintAssets(SEveUSDCVault target, uint256 shares) internal view returns (uint256) {
        uint256 supply = target.totalSupply();
        (uint256 assetsAfter,,) = _postAccrualAssets(target);

        if (supply == 0) {
            return shares;
        }

        return
            Math.mulDiv(shares, assetsAfter + VAULT_VIRTUAL_ASSETS, supply + VAULT_VIRTUAL_SHARES, Math.Rounding.Ceil);
    }

    function _expectedWithdrawShares(SEveUSDCVault target, uint256 assets) internal view returns (uint256) {
        uint256 supply = target.totalSupply();
        (uint256 assetsAfter,,) = _postAccrualAssets(target);

        if (supply == 0) {
            return assets;
        }

        return Math.mulDiv(assets, supply, assetsAfter, Math.Rounding.Ceil);
    }

    function _expectedRedeemAssets(SEveUSDCVault target, uint256 shares) internal view returns (uint256) {
        uint256 supply = target.totalSupply();
        (uint256 assetsAfter,,) = _postAccrualAssets(target);

        if (supply == 0) {
            return shares;
        }

        return Math.mulDiv(shares, assetsAfter, supply);
    }

    function _dailyRateWad(uint16 feeBps) internal pure returns (uint256) {
        return Math.mulDiv(uint256(feeBps), WAD, 365 * 10_000);
    }

    function _retainedFactorLoop(uint16 feeBps, uint256 epochs) internal pure returns (uint256 retainedFactorWad) {
        retainedFactorWad = WAD;
        uint256 retentionFactorWad = WAD - _dailyRateWad(feeBps);

        for (uint256 index = 0; index < epochs; ++index) {
            retainedFactorWad = Math.mulDiv(retainedFactorWad, retentionFactorWad, WAD);
        }
    }

    function _theoreticalFeeWad(uint256 assetsBefore, uint16 feeBps, uint256 epochs) internal pure returns (uint256) {
        uint256 retainedFactorWad = _retainedFactorLoop(feeBps, epochs);
        return Math.mulDiv(assetsBefore, WAD - retainedFactorWad, 1);
    }

    function _theoreticalFeeWadUsingRpow(uint256 assetsBefore, uint16 feeBps, uint256 epochs)
        internal
        pure
        returns (uint256)
    {
        uint256 retainedFactorWad = LibFixedPointMath.rpow(WAD - _dailyRateWad(feeBps), epochs, WAD);
        return Math.mulDiv(assetsBefore, WAD - retainedFactorWad, 1);
    }
}
