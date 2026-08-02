// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCVault} from "../../src/interfaces/ISEveUSDCVault.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {MockUSDC} from "../helpers/MockUSDC.sol";
import {VaultFeeRoutingFixture} from "../helpers/VaultFeeRoutingFixture.sol";

contract VaultFeeRoutingTest is VaultFeeRoutingFixture {
    uint72 internal constant TWO_USDC = 2_000_000_000_000_000_000;

    event StakingVaultSet(address indexed previousStakingVault, address indexed newStakingVault);
    event OrderbookFeeSplitSet(uint16 makerFeeBps, uint16 creatorFeeBps, uint16 protocolFeeBps, uint16 vaultFeeBps);
    event RevenueNotified(address indexed caller, uint256 assets);

    function test_FillRoutesConfiguredVaultFeeShareToVault() public {
        uint16 vaultBps = 100; // 1% of total fee
        _depositStake(1_000e6);
        _configureVaultRouting(address(vault), vaultBps);

        (bytes32 marketId,) = _createTradingMarket("vault-routed-fill", 7 days);
        _splitFromMaker(marketId, DEFAULT_MAKER_INVENTORY);
        _approvePositions(maker);
        uint256 curveId =
            _postCurveFromMaker(marketId, true, DEFAULT_MAKER_INVENTORY, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);

        uint256 treasuryBalanceBefore = eveUSDC.balanceOf(treasury);
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultSupplyBefore = vault.totalSupply();

        (, uint128 fee,) = _fillCurveFromTaker(curveId, DEFAULT_FILL_COLLATERAL);
        uint128 expectedVaultShare = _vaultShare(fee, vaultBps);
        uint128 expectedTreasuryShare = _treasuryShare(fee, vaultBps);

        (, uint128 protocolFeesAccrued,,) = _storedMarketFees(marketId);

        assertEq(eveUSDC.balanceOf(treasury) - treasuryBalanceBefore, expectedTreasuryShare);
        assertEq(vault.totalAssets() - vaultAssetsBefore, expectedVaultShare);
        assertEq(vault.totalSupply(), vaultSupplyBefore);
        assertEq(protocolFeesAccrued, expectedTreasuryShare);
    }

    function test_FillRoutesVaultFeeWhenAumFeesExceedIdleVaultLiquidity() public {
        uint16 vaultBps = 100;

        vm.prank(owner);
        vault.setAumFeeBps(10_000);

        _depositStake(1_000e6);

        vm.prank(owner);
        vault.setLendingContract(address(this));

        vault.reportLoan(990e6);
        vault.disburseLoan(makeAddr("vault-aum-borrower"), 990e6, 0);

        uint256 idleBeforeAccrual = eveUSDC.balanceOf(address(vault));
        vm.warp(block.timestamp + 30 days);
        (uint256 previewFee,) = vault.previewAccruedAum();
        assertGt(previewFee, idleBeforeAccrual);

        vault.accrueAum();
        uint256 unpaidBeforeFill = vault.unpaidAumFees();
        assertGt(unpaidBeforeFill, 0);
        assertEq(eveUSDC.balanceOf(address(vault)), 0);

        _configureVaultRouting(address(vault), vaultBps);

        (bytes32 marketId,) = _createTradingMarket("vault-illiquid-aum-routed-fill", 7 days);
        _splitFromMaker(marketId, DEFAULT_MAKER_INVENTORY);
        _approvePositions(maker);
        uint256 curveId =
            _postCurveFromMaker(marketId, true, DEFAULT_MAKER_INVENTORY, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);

        (, uint128 fee,) = _fillCurveFromTaker(curveId, DEFAULT_FILL_COLLATERAL);
        uint128 expectedVaultShare = _vaultShare(fee, vaultBps);
        uint256 expectedDebtReduction = expectedVaultShare < unpaidBeforeFill ? expectedVaultShare : unpaidBeforeFill;
        uint256 expectedVaultIdle = expectedVaultShare - expectedDebtReduction;

        assertEq(vault.unpaidAumFees(), unpaidBeforeFill - expectedDebtReduction);
        assertEq(eveUSDC.balanceOf(address(vault)), expectedVaultIdle);
    }

    function test_FillRoutesAllProtocolFeesToTreasuryWhenVaultFeeBpsIsZero() public {
        _depositStake(1_000e6);
        _configureVaultRouting(address(vault), 0);

        (bytes32 marketId,) = _createTradingMarket("vault-disabled-by-bps", 7 days);
        _splitFromMaker(marketId, DEFAULT_MAKER_INVENTORY);
        _approvePositions(maker);
        uint256 curveId =
            _postCurveFromMaker(marketId, true, DEFAULT_MAKER_INVENTORY, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);

        uint256 treasuryBalanceBefore = eveUSDC.balanceOf(treasury);
        uint256 vaultAssetsBefore = vault.totalAssets();
        (, uint128 fee,) = _fillCurveFromTaker(curveId, DEFAULT_FILL_COLLATERAL);
        uint128 expectedTreasuryShare = _treasuryShare(fee, 0);

        (, uint128 protocolFeesAccrued,,) = _storedMarketFees(marketId);

        assertEq(eveUSDC.balanceOf(treasury) - treasuryBalanceBefore, expectedTreasuryShare);
        assertEq(vault.totalAssets() - vaultAssetsBefore, 0);
        assertEq(protocolFeesAccrued, expectedTreasuryShare);
    }

    function test_FillRoutesAllFeesToTreasuryWhenStakingVaultIsUnset() public {
        _depositStake(1_000e6);
        // Set fee split with vault share but no vault address
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(8_500, 500, 900, 100);

        (bytes32 marketId,) = _createTradingMarket("vault-disabled-by-address", 7 days);
        _splitFromMaker(marketId, DEFAULT_MAKER_INVENTORY);
        _approvePositions(maker);
        uint256 curveId =
            _postCurveFromMaker(marketId, true, DEFAULT_MAKER_INVENTORY, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        uint256 treasuryBalanceBefore = eveUSDC.balanceOf(treasury);
        uint256 vaultAssetsBefore = vault.totalAssets();
        (, uint128 fee,) = _fillCurveFromTaker(curveId, DEFAULT_FILL_COLLATERAL);

        // When vault is address(0), vault share goes to treasury
        uint128 makerShare = _makerShare(fee);
        uint128 creatorShare = _creatorShare(fee);
        uint128 expectedTreasuryShare = fee - makerShare - creatorShare;

        (, uint128 protocolFeesAccrued,,) = _storedMarketFees(marketId);

        assertEq(eveUSDC.balanceOf(treasury) - treasuryBalanceBefore, expectedTreasuryShare);
        assertEq(vault.totalAssets() - vaultAssetsBefore, 0);
        assertEq(protocolFeesAccrued, expectedTreasuryShare);
    }

    function test_SpotQuoteFeesRouteToTreasuryWhenRewardTokenUnregistered() public {
        uint16 vaultBps = 100;
        MockUSDC spotBase = new MockUSDC();
        MockUSDC quoteToken = new MockUSDC();
        spotBase.mint(maker, 1_000e6);
        quoteToken.mint(taker, 1_000e6);

        _depositStake(1_000e6);
        _configureVaultRouting(address(vault), vaultBps);

        uint256 treasuryBalanceBefore = quoteToken.balanceOf(treasury);
        uint256 vaultQuoteBefore = quoteToken.balanceOf(address(vault));
        (, uint128 fee,) = _fillSpotAsk(spotBase, quoteToken, 420e6);
        uint128 expectedTreasuryShare = _protocolShare(fee);

        assertEq(quoteToken.balanceOf(treasury) - treasuryBalanceBefore, expectedTreasuryShare);
        assertEq(quoteToken.balanceOf(address(vault)) - vaultQuoteBefore, 0);
        assertEq(vault.rewardLiability(address(quoteToken)), 0);
    }

    function test_SpotQuoteFeesRouteToVaultWhenRewardTokenRegistered() public {
        uint16 vaultBps = 100;
        MockUSDC spotBase = new MockUSDC();
        MockUSDC quoteToken = new MockUSDC();
        spotBase.mint(maker, 1_000e6);
        quoteToken.mint(taker, 1_000e6);

        _depositStake(1_000e6);
        _registerRewardToken(quoteToken, maker);
        _configureVaultRouting(address(vault), vaultBps);

        uint256 treasuryBalanceBefore = quoteToken.balanceOf(treasury);
        uint256 vaultQuoteBefore = quoteToken.balanceOf(address(vault));
        (, uint128 fee,) = _fillSpotAsk(spotBase, quoteToken, 420e6);
        uint128 expectedVaultShare = _vaultShare(fee, vaultBps);
        uint128 expectedTreasuryShare = _treasuryShare(fee, vaultBps);

        assertEq(quoteToken.balanceOf(treasury) - treasuryBalanceBefore, expectedTreasuryShare);
        assertEq(quoteToken.balanceOf(address(vault)) - vaultQuoteBefore, expectedVaultShare);
        assertEq(vault.rewardLiability(address(quoteToken)), expectedVaultShare);
        assertEq(vault.previewRewards(staker, address(quoteToken)), expectedVaultShare);
    }

    function test_RewardTokenRegistrationFeePaysVaultTreasuryRecipient() public {
        MockUSDC quoteToken = new MockUSDC();
        uint256 registrationFee = vault.rewardTokenRegistrationFee();
        uint256 recipientBefore = eveUSDC.balanceOf(vaultFeeRecipient);
        uint256 vaultAssetsBefore = vault.totalAssets();

        _registerRewardToken(quoteToken, maker);

        assertEq(eveUSDC.balanceOf(vaultFeeRecipient) - recipientBefore, registrationFee);
        assertEq(vault.totalAssets(), vaultAssetsBefore);
        assertEq(eveUSDC.balanceOf(address(vault)), vaultAssetsBefore);
        assertTrue(vault.isRewardTokenActive(address(quoteToken)));
    }

    function test_GovernanceSettersAreOwnerOnlyAndEmitEvents() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setStakingVault(address(vault));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(8_500, 400, 1_000, 100);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit StakingVaultSet(address(0), address(vault));

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setStakingVault(address(vault));

        vm.expectEmit(false, false, false, true, address(diamond));
        emit OrderbookFeeSplitSet(8_500, 400, 1_000, 100);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(8_500, 400, 1_000, 100);

        // Must sum to 10000
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFeeSplit.selector, 10_100));
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(8_500, 500, 1_000, 100);

        assertEq(_marketConfig().stakingVault, address(vault));
        assertEq(_marketConfig().orderbookFeeConfig.vaultFeeBps, 100);
        assertEq(_marketConfig().orderbookFeeConfig.makerFeeBps, 8_500);
    }

    function _fillSpotAsk(MockUSDC spotBase, MockUSDC quoteToken, uint128 quoteIn)
        internal
        returns (uint128 sharesOut, uint128 fee, uint128 price)
    {
        bytes32 bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotBase),
                0,
                address(quoteToken),
                0,
                keccak256(abi.encode(address(spotBase), address(quoteToken), block.timestamp))
            );

        vm.startPrank(maker);
        spotBase.approve(address(diamond), 1_000e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 1_000e6, TWO_USDC, TWO_USDC, 180, 0, type(uint8).max);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares, uint128 previewFee, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, quoteIn);

        vm.startPrank(taker);
        quoteToken.approve(address(diamond), quoteIn);
        sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, quoteIn, 0, generation, commitment);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);
        fee = previewFee;
        price = previewPrice;
    }

    function _registerRewardToken(MockUSDC token, address registrant) internal {
        uint256 registrationFee = vault.rewardTokenRegistrationFee();
        _wrapFor(registrant, registrationFee);

        vm.startPrank(registrant);
        eveUSDC.approve(address(vault), registrationFee);
        vault.registerRewardToken(address(token));
        vm.stopPrank();
    }
}
