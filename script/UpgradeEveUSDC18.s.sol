// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Script, console2} from "../lib/forge-std/src/Script.sol";

import {EveUSDC} from "../src/EveUSDC.sol";
import {MakerLendingRouter} from "../src/MakerLendingRouter.sol";
import {SEveUSDCLending} from "../src/SEveUSDCLending.sol";
import {SEveUSDCVault} from "../src/SEveUSDCVault.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {TradeRouterFacet} from "../src/facets/TradeRouterFacet.sol";
import {TradeRouterSellFacet} from "../src/facets/TradeRouterSellFacet.sol";
import {VaultRouterFacet} from "../src/facets/VaultRouterFacet.sol";
import {ITradeRouter} from "../src/interfaces/ITradeRouter.sol";
import {IVaultRouter} from "../src/interfaces/IVaultRouter.sol";
import {LibEveUSDCUnits} from "../src/libraries/LibEveUSDCUnits.sol";

contract UpgradeEveUSDC18 is Script {
    using SafeERC20 for IERC20;

    struct UpgradeDeployment {
        address eveUSDC;
        address seveUsdcVault;
        address seveUsdcLending;
        address makerLendingRouter;
        address tradeRouterFacet;
        address tradeRouterSellFacet;
        address vaultRouterFacet;
    }

    struct UpgradeConfig {
        uint256 privateKey;
        address owner;
        address diamond;
        address usdc;
        address conditionalTokens;
        address parimutuelShareToken;
        address feeRecipient;
        uint16 aumFeeBps;
        uint16 lendingMaxLtvBps;
        uint16 lendingOriginationFeeBps;
        uint16 lendingExtensionFeeBps;
        uint32 lendingMinDurationSeconds;
        uint32 lendingMaxDurationSeconds;
        uint32 lendingGracePeriodSeconds;
        uint16 parimutuelEntryFeeBps;
        uint128 parimutuelMinEntry;
        uint128 marketCreationFee;
        uint128 spotBookCreationFee;
        uint256 bootstrapUsdc;
    }

    function run() external returns (UpgradeDeployment memory deployment) {
        UpgradeConfig memory config = _loadConfig();

        vm.startBroadcast(config.privateKey);
        deployment = _deployPeripherals(config);
        DiamondCutFacet(config.diamond).diamondCut(_routerFacetCuts(deployment), address(0), "");
        _configurePeripherals(deployment, config);
        _configureDiamond(deployment, config);
        _bootstrapVault(config.usdc, deployment.eveUSDC, deployment.seveUsdcVault, config.owner, config.bootstrapUsdc);
        vm.stopBroadcast();

        _verifyUpgrade(deployment, config.diamond);
        _logDeployment(deployment, config.diamond);
    }

    function _loadConfig() private view returns (UpgradeConfig memory config) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        config.privateKey = privateKey;
        config.owner = vm.addr(privateKey);
        config.diamond = vm.envAddress("DIAMOND");
        config.usdc = vm.envAddress("USDC_TOKEN");
        config.conditionalTokens = vm.envAddress("CONDITIONAL_TOKENS");
        config.parimutuelShareToken = vm.envAddress("PARIMUTUEL_SHARE_TOKEN");
        config.feeRecipient = vm.envOr("FEE_RECIPIENT", config.owner);
        config.aumFeeBps = uint16(vm.envOr("AUM_FEE_BPS", uint256(200)));
        config.lendingMaxLtvBps = uint16(vm.envOr("LENDING_MAX_LTV_BPS", uint256(9_500)));
        config.lendingOriginationFeeBps = uint16(vm.envOr("LENDING_ORIGINATION_FEE_BPS", uint256(100)));
        config.lendingExtensionFeeBps = uint16(vm.envOr("LENDING_EXTENSION_FEE_BPS", uint256(50)));
        config.lendingMinDurationSeconds = uint32(vm.envOr("LENDING_MIN_DURATION_SECONDS", uint256(1 days)));
        config.lendingMaxDurationSeconds = uint32(vm.envOr("LENDING_MAX_DURATION_SECONDS", uint256(400 days)));
        config.lendingGracePeriodSeconds = uint32(vm.envOr("LENDING_GRACE_PERIOD_SECONDS", uint256(1 days)));
        config.parimutuelEntryFeeBps = uint16(vm.envOr("PARIMUTUEL_ENTRY_FEE_BPS", uint256(250)));
        config.parimutuelMinEntry = uint128(vm.envOr("PARIMUTUEL_MIN_ENTRY", uint256(1e18)));
        config.marketCreationFee = uint128(vm.envOr("MARKET_CREATION_FEE", uint256(1e18)));
        config.spotBookCreationFee = uint128(vm.envOr("SPOT_BOOK_CREATION_FEE", uint256(250e18)));
        config.bootstrapUsdc = vm.envOr("INITIAL_VAULT_BOOTSTRAP", uint256(1e6));
    }

    function _deployPeripherals(UpgradeConfig memory config) private returns (UpgradeDeployment memory deployment) {
        deployment.eveUSDC = address(new EveUSDC(config.usdc, config.owner, config.owner));
        deployment.seveUsdcVault = address(
            new SEveUSDCVault(deployment.eveUSDC, config.owner, config.feeRecipient, config.aumFeeBps, config.diamond)
        );
        deployment.seveUsdcLending =
            address(new SEveUSDCLending(deployment.seveUsdcVault, deployment.eveUSDC, config.owner));
        deployment.makerLendingRouter = address(
            new MakerLendingRouter(
                config.usdc,
                deployment.eveUSDC,
                deployment.seveUsdcVault,
                deployment.seveUsdcLending,
                config.diamond,
                config.conditionalTokens
            )
        );
        deployment.tradeRouterFacet = address(new TradeRouterFacet());
        deployment.tradeRouterSellFacet = address(new TradeRouterSellFacet());
        deployment.vaultRouterFacet = address(new VaultRouterFacet());
    }

    function _configurePeripherals(UpgradeDeployment memory deployment, UpgradeConfig memory config) private {
        SEveUSDCVault(deployment.seveUsdcVault).setLendingContract(deployment.seveUsdcLending);
        SEveUSDCLending(deployment.seveUsdcLending)
            .setLendingConfig(
                config.lendingMaxLtvBps,
                config.lendingOriginationFeeBps,
                config.lendingExtensionFeeBps,
                config.lendingMinDurationSeconds,
                config.lendingMaxDurationSeconds,
                config.lendingGracePeriodSeconds
            );
        SEveUSDCLending(deployment.seveUsdcLending).setApprovedRouter(deployment.makerLendingRouter, true);
    }

    function _configureDiamond(UpgradeDeployment memory deployment, UpgradeConfig memory config) private {
        OwnershipFacet(config.diamond).setCollateralToken(deployment.eveUSDC);
        OwnershipFacet(config.diamond).setStakingVault(deployment.seveUsdcVault);
        OwnershipFacet(config.diamond).setMarketCreationFee(config.marketCreationFee);
        OwnershipFacet(config.diamond).setSpotBookCreationFee(config.spotBookCreationFee);
        OwnershipFacet(config.diamond)
            .setParimutuelConfig(config.parimutuelShareToken, config.parimutuelEntryFeeBps, config.parimutuelMinEntry);
    }

    function _verifyUpgrade(UpgradeDeployment memory deployment, address diamond) private view {
        _assertSelector(diamond, ITradeRouter.buyWithEveUSDC.selector, deployment.tradeRouterFacet);
        _assertSelector(diamond, ITradeRouter.buyWithUSDC.selector, deployment.tradeRouterFacet);
        _assertSelector(diamond, ITradeRouter.sellWithEveUSDC.selector, deployment.tradeRouterSellFacet);
        _assertSelector(diamond, ITradeRouter.sellWithUSDC.selector, deployment.tradeRouterSellFacet);
        _assertSelector(diamond, ITradeRouter.previewSellBest.selector, deployment.tradeRouterSellFacet);
        _assertSelector(diamond, ITradeRouter.splitWithUSDC.selector, deployment.tradeRouterFacet);
        _assertSelector(diamond, IVaultRouter.wrapAndDeposit.selector, deployment.vaultRouterFacet);
        _assertSelector(diamond, IVaultRouter.redeemAndUnwrap.selector, deployment.vaultRouterFacet);
        _assertSelector(diamond, IVaultRouter.wrapETHToEveETH.selector, deployment.vaultRouterFacet);
        require(EveUSDC(deployment.eveUSDC).decimals() == 18, "eveUSDC decimals mismatch");
        require(SEveUSDCVault(deployment.seveUsdcVault).asset() == deployment.eveUSDC, "vault asset mismatch");
    }

    function _logDeployment(UpgradeDeployment memory deployment, address diamond) private view {
        console2.log("eveUSDC", deployment.eveUSDC);
        console2.log("seveUsdcVault", deployment.seveUsdcVault);
        console2.log("seveUsdcLending", deployment.seveUsdcLending);
        console2.log("makerLendingRouter", deployment.makerLendingRouter);
        console2.log("tradeRouterFacet", deployment.tradeRouterFacet);
        console2.log("tradeRouterSellFacet", deployment.tradeRouterSellFacet);
        console2.log("vaultRouterFacet", deployment.vaultRouterFacet);
        console2.log("diamond", diamond);
    }

    function _routerFacetCuts(UpgradeDeployment memory deployment)
        private
        pure
        returns (DiamondCutFacet.FacetCut[] memory cuts)
    {
        cuts = new DiamondCutFacet.FacetCut[](3);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.tradeRouterFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _tradeRouterSelectors()
        });
        cuts[1] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.tradeRouterSellFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _tradeRouterSellSelectors()
        });
        cuts[2] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.vaultRouterFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _vaultRouterSelectors()
        });
    }

    function _tradeRouterSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ITradeRouter.buyWithEveUSDC.selector;
        selectors[1] = ITradeRouter.buyWithUSDC.selector;
        selectors[2] = ITradeRouter.splitWithUSDC.selector;
    }

    function _tradeRouterSellSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ITradeRouter.sellWithEveUSDC.selector;
        selectors[1] = ITradeRouter.sellWithUSDC.selector;
        selectors[2] = ITradeRouter.previewSellBest.selector;
    }

    function _vaultRouterSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IVaultRouter.wrapAndDeposit.selector;
        selectors[1] = IVaultRouter.redeemAndUnwrap.selector;
        selectors[2] = IVaultRouter.wrapETHToEveETH.selector;
    }

    function _bootstrapVault(address usdc, address eveUSDC, address vault, address owner, uint256 bootstrapUsdc)
        private
    {
        if (bootstrapUsdc == 0 || SEveUSDCVault(vault).totalSupply() != 0) {
            return;
        }

        uint256 bootstrapAssets = LibEveUSDCUnits.toEveUSDC(bootstrapUsdc);
        IERC20(usdc).forceApprove(eveUSDC, bootstrapUsdc);
        EveUSDC(eveUSDC).wrap(bootstrapUsdc, owner);
        IERC20(eveUSDC).forceApprove(vault, bootstrapAssets);
        SEveUSDCVault(vault).deposit(bootstrapAssets, owner);
    }

    function _assertSelector(address diamond, bytes4 selector, address expectedFacet) private view {
        address actualFacet = _facetAddress(diamond, selector);
        require(actualFacet == expectedFacet, "selector not upgraded");
    }

    function _facetAddress(address diamond, bytes4 selector) private view returns (address facet) {
        (bool ok, bytes memory data) = diamond.staticcall(abi.encodeWithSignature("facetAddress(bytes4)", selector));
        require(ok, "facetAddress failed");
        facet = abi.decode(data, (address));
    }
}
