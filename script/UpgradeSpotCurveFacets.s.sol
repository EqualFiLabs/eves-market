// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "../lib/forge-std/src/Script.sol";

import {CurveCLOBFacet} from "../src/facets/CurveCLOBFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {BookOrderFacet} from "../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../src/facets/BookSellFacet.sol";
import {IBookAdminFacet} from "../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../src/types/CurveCLOBTypes.sol";

contract UpgradeSpotCurveFacets is Script {
    bytes4 private constant FILL_BEST_FOR_SELECTOR = bytes4(
        keccak256("fillBestFor((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))")
    );

    struct UpgradeDeployment {
        address curveCLOBFacet;
        address bookOrderFacet;
        address bookTradeFacet;
        address bookSellFacet;
    }

    function run() external returns (UpgradeDeployment memory deployment) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address diamond = vm.envAddress("DIAMOND");

        vm.startBroadcast(privateKey);
        deployment.curveCLOBFacet = address(new CurveCLOBFacet());
        deployment.bookOrderFacet = address(new BookOrderFacet());
        deployment.bookTradeFacet = address(new BookTradeFacet());
        deployment.bookSellFacet = address(new BookSellFacet());

        DiamondCutFacet.FacetCut[] memory cuts = _buildCuts(diamond, deployment);
        DiamondCutFacet(diamond).diamondCut(cuts, address(0), "");
        vm.stopBroadcast();

        _assertSelector(diamond, ICurveTradeFacet.fillCurve.selector, deployment.curveCLOBFacet);
        _assertSelector(diamond, ICurveTradeFacet.fillBest.selector, deployment.curveCLOBFacet);
        _assertSelector(diamond, FILL_BEST_FOR_SELECTOR, address(0));
        _assertSelector(diamond, IBookOrderFacet.postBookCurve.selector, deployment.bookOrderFacet);
        _assertSelector(diamond, IBookOrderFacet.postBookCurvesBatch.selector, deployment.bookOrderFacet);
        _assertSelector(diamond, IBookOrderFacet.topUpBookCurvesBatch.selector, deployment.bookOrderFacet);
        _assertSelector(diamond, IBookOrderFacet.reactivateBookCurve.selector, deployment.bookOrderFacet);
        _assertSelector(diamond, IBookTradeFacet.fillBookBest.selector, deployment.bookTradeFacet);
        _assertSelector(diamond, IBookTradeFacet.fillBookBestFor.selector, deployment.bookTradeFacet);
        _assertSelector(diamond, IBookTradeFacet.sellBookBest.selector, deployment.bookSellFacet);
        _assertSelector(diamond, IBookTradeFacet.sellBookBestFor.selector, deployment.bookSellFacet);
    }

    function _buildCuts(address diamond, UpgradeDeployment memory deployment)
        private
        view
        returns (DiamondCutFacet.FacetCut[] memory cuts)
    {
        bool removeFillBestFor = _facetAddress(diamond, FILL_BEST_FOR_SELECTOR) != address(0);
        cuts = new DiamondCutFacet.FacetCut[](removeFillBestFor ? 6 : 5);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.curveCLOBFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _curveTradeSelectors()
        });
        cuts[1] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookOrderFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _bookOrderReplacementSelectors()
        });
        cuts[2] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookOrderFacet,
            action: _selectorAction(diamond, IBookOrderFacet.reactivateBookCurve.selector),
            functionSelectors: _reactivationSelectors()
        });
        cuts[3] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookTradeFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _bookTradeSelectors()
        });
        cuts[4] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookSellFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _bookSellSelectors()
        });
        if (removeFillBestFor) {
            cuts[5] = DiamondCutFacet.FacetCut({
                facetAddress: address(0),
                action: DiamondCutFacet.FacetCutAction.Remove,
                functionSelectors: _removedCurveTradeSelectors()
            });
        }
    }

    function _selectorAction(address diamond, bytes4 selector)
        private
        view
        returns (DiamondCutFacet.FacetCutAction action)
    {
        address currentFacet = _facetAddress(diamond, selector);
        if (currentFacet == address(0)) {
            return DiamondCutFacet.FacetCutAction.Add;
        }
        return DiamondCutFacet.FacetCutAction.Replace;
    }

    function _curveTradeSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function _removedCurveTradeSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = FILL_BEST_FOR_SELECTOR;
    }

    function _bookOrderReplacementSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
    }

    function _reactivationSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.reactivateBookCurve.selector;
    }

    function _bookTradeSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
    }

    function _bookSellSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.sellBookBestFor.selector;
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
