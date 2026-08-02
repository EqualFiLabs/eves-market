// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console2} from "../lib/forge-std/src/Script.sol";

import {CurveCLOBFacet} from "../src/facets/CurveCLOBFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {FeeRouterFacet} from "../src/facets/FeeRouterFacet.sol";
import {OBRResolutionFacet} from "../src/facets/OBRResolutionFacet.sol";
import {BookTradeFacet} from "../src/facets/BookTradeFacet.sol";
import {TradeRouterFacet} from "../src/facets/TradeRouterFacet.sol";
import {TradeRouterSellFacet} from "../src/facets/TradeRouterSellFacet.sol";
import {IBookAdminFacet} from "../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../src/types/CurveCLOBTypes.sol";
import {IFeeRouterFacet} from "../src/interfaces/IFeeRouterFacet.sol";
import {IOBRResolutionFacet} from "../src/interfaces/IOBRResolutionFacet.sol";
import {ITradeRouter} from "../src/interfaces/ITradeRouter.sol";

contract UpgradeBaseSepoliaTradingRewards is Script {
    struct UpgradeDeployment {
        address obrResolutionFacet;
        address feeRouterFacet;
        address curveCLOBFacet;
        address bookTradeFacet;
        address tradeRouterFacet;
        address tradeRouterSellFacet;
    }

    struct UpgradeConfig {
        uint256 privateKey;
        address diamond;
    }

    function run() external returns (UpgradeDeployment memory deployment) {
        UpgradeConfig memory config = _loadConfig();

        vm.startBroadcast(config.privateKey);
        deployment.obrResolutionFacet = address(new OBRResolutionFacet());
        deployment.feeRouterFacet = address(new FeeRouterFacet());
        deployment.curveCLOBFacet = address(new CurveCLOBFacet());
        deployment.bookTradeFacet = address(new BookTradeFacet());
        deployment.tradeRouterFacet = address(new TradeRouterFacet());
        deployment.tradeRouterSellFacet = address(new TradeRouterSellFacet());

        DiamondCutFacet(config.diamond).diamondCut(_buildCuts(config.diamond, deployment), address(0), "");
        vm.stopBroadcast();

        _verifyUpgrade(config.diamond, deployment);
        _logDeployment(config.diamond, deployment);
    }

    function _loadConfig() private view returns (UpgradeConfig memory config) {
        config.privateKey = vm.envUint("PRIVATE_KEY");
        config.diamond = vm.envAddress("DIAMOND");
    }

    function _buildCuts(address diamond, UpgradeDeployment memory deployment)
        private
        view
        returns (DiamondCutFacet.FacetCut[] memory cuts)
    {
        cuts = new DiamondCutFacet.FacetCut[](10);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.obrResolutionFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _obrResolutionSelectors()
        });
        cuts[1] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.feeRouterFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _existingFeeRouterSelectors()
        });
        cuts[2] = _singleSelectorCut(
            diamond, deployment.feeRouterFacet, IFeeRouterFacet.configureMarketMakerRewards.selector
        );
        cuts[3] =
            _singleSelectorCut(diamond, deployment.feeRouterFacet, IFeeRouterFacet.fundMarketMakerRewards.selector);
        cuts[4] =
            _singleSelectorCut(diamond, deployment.feeRouterFacet, IFeeRouterFacet.claimMarketMakerRewards.selector);
        cuts[5] =
            _singleSelectorCut(diamond, deployment.feeRouterFacet, IFeeRouterFacet.previewMarketMakerRewards.selector);
        cuts[6] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.curveCLOBFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _curveTradeSelectors()
        });
        cuts[7] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookTradeFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _bookTradeSelectors()
        });
        cuts[8] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.tradeRouterFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _existingTradeRouterSelectors()
        });
        cuts[9] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.tradeRouterSellFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _tradeRouterSellSelectors()
        });
    }

    function _singleSelectorCut(address diamond, address facet, bytes4 selector)
        private
        view
        returns (DiamondCutFacet.FacetCut memory cut)
    {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        cut = DiamondCutFacet.FacetCut({
            facetAddress: facet, action: _selectorAction(diamond, selector), functionSelectors: selectors
        });
    }

    function _selectorAction(address diamond, bytes4 selector)
        private
        view
        returns (DiamondCutFacet.FacetCutAction action)
    {
        return _facetAddress(diamond, selector) == address(0)
            ? DiamondCutFacet.FacetCutAction.Add
            : DiamondCutFacet.FacetCutAction.Replace;
    }

    function _obrResolutionSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IOBRResolutionFacet.settleMarket.selector;
        selectors[1] = IOBRResolutionFacet.openResolution.selector;
        selectors[2] = IOBRResolutionFacet.disputeResolution.selector;
        selectors[3] = IOBRResolutionFacet.adminFinalizeResolution.selector;
        selectors[4] = IOBRResolutionFacet.getResolutionHistory.selector;
        selectors[5] = IOBRResolutionFacet.finalizeResolution.selector;
        selectors[6] = IOBRResolutionFacet.getMarketStatus.selector;
        selectors[7] = IOBRResolutionFacet.settleMarketEarly.selector;
        selectors[8] = IOBRResolutionFacet.finalizeFromJury.selector;
        selectors[9] = IOBRResolutionFacet.resolutionMode.selector;
    }

    function _existingFeeRouterSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IFeeRouterFacet.claimCreatorFees.selector;
        selectors[1] = IFeeRouterFacet.claimMakerFees.selector;
        selectors[2] = IFeeRouterFacet.previewMakerFees.selector;
        selectors[3] = IFeeRouterFacet.getMakerMarketAccounting.selector;
        selectors[4] = IFeeRouterFacet.claimBookCreatorFees.selector;
        selectors[5] = IFeeRouterFacet.claimBookMakerFees.selector;
        selectors[6] = IFeeRouterFacet.previewBookMakerFees.selector;
        selectors[7] = IFeeRouterFacet.getMakerBookAccounting.selector;
    }

    function _curveTradeSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function _bookTradeSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
        selectors[2] = IBookTradeFacet.sellBookBest.selector;
        selectors[3] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function _existingTradeRouterSelectors() private pure returns (bytes4[] memory selectors) {
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

    function _verifyUpgrade(address diamond, UpgradeDeployment memory deployment) private view {
        _assertSelectorRouting(diamond, deployment.obrResolutionFacet, _obrResolutionSelectors());
        _assertSelectorRouting(diamond, deployment.feeRouterFacet, _existingFeeRouterSelectors());
        _assertSelector(diamond, IFeeRouterFacet.configureMarketMakerRewards.selector, deployment.feeRouterFacet);
        _assertSelector(diamond, IFeeRouterFacet.fundMarketMakerRewards.selector, deployment.feeRouterFacet);
        _assertSelector(diamond, IFeeRouterFacet.claimMarketMakerRewards.selector, deployment.feeRouterFacet);
        _assertSelector(diamond, IFeeRouterFacet.previewMarketMakerRewards.selector, deployment.feeRouterFacet);
        _assertSelectorRouting(diamond, deployment.curveCLOBFacet, _curveTradeSelectors());
        _assertSelectorRouting(diamond, deployment.bookTradeFacet, _bookTradeSelectors());
        _assertSelectorRouting(diamond, deployment.tradeRouterFacet, _existingTradeRouterSelectors());
        _assertSelectorRouting(diamond, deployment.tradeRouterSellFacet, _tradeRouterSellSelectors());
    }

    function _assertSelectorRouting(address diamond, address facet, bytes4[] memory selectors) private view {
        for (uint256 index = 0; index < selectors.length; ++index) {
            _assertSelector(diamond, selectors[index], facet);
        }
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

    function _logDeployment(address diamond, UpgradeDeployment memory deployment) private pure {
        console2.log("diamond", diamond);
        console2.log("obrResolutionFacet", deployment.obrResolutionFacet);
        console2.log("feeRouterFacet", deployment.feeRouterFacet);
        console2.log("curveCLOBFacet", deployment.curveCLOBFacet);
        console2.log("bookTradeFacet", deployment.bookTradeFacet);
        console2.log("tradeRouterFacet", deployment.tradeRouterFacet);
        console2.log("tradeRouterSellFacet", deployment.tradeRouterSellFacet);
    }
}
