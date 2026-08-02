// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "../lib/forge-std/src/Script.sol";

import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {BookFacet} from "../src/facets/BookFacet.sol";
import {BookTradeFacet} from "../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../src/facets/BookSellFacet.sol";
import {IBookAdminFacet} from "../src/interfaces/IBookAdminFacet.sol";
import {IBookTradeFacet} from "../src/interfaces/IBookTradeFacet.sol";

contract UpgradeBookDecommission is Script {
    struct UpgradeDeployment {
        address bookFacet;
        address bookTradeFacet;
        address bookSellFacet;
    }

    function run() external returns (UpgradeDeployment memory deployment) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address diamond = vm.envAddress("DIAMOND");

        vm.startBroadcast(privateKey);
        deployment.bookFacet = address(new BookFacet());
        deployment.bookTradeFacet = address(new BookTradeFacet());
        deployment.bookSellFacet = address(new BookSellFacet());

        DiamondCutFacet.FacetCut[] memory cuts = _buildCuts(diamond, deployment);
        DiamondCutFacet(diamond).diamondCut(cuts, address(0), "");
        vm.stopBroadcast();

        _assertSelector(diamond, IBookAdminFacet.createBook.selector, deployment.bookFacet);
        _assertSelector(diamond, IBookAdminFacet.computeBookId.selector, deployment.bookFacet);
        _assertSelector(diamond, IBookAdminFacet.getBookInfo.selector, deployment.bookFacet);
        _assertSelector(diamond, IBookAdminFacet.getMarketSideBook.selector, deployment.bookFacet);
        _assertSelector(diamond, IBookAdminFacet.requestBookDecommission.selector, deployment.bookFacet);
        _assertSelector(diamond, IBookAdminFacet.finalizeBookDecommission.selector, deployment.bookFacet);
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
        cuts = new DiamondCutFacet.FacetCut[](4);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _bookReplacementSelectors()
        });
        cuts[1] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookFacet,
            action: _selectorAction(diamond, IBookAdminFacet.requestBookDecommission.selector),
            functionSelectors: _bookDecommissionSelectors()
        });
        cuts[2] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookTradeFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _bookTradeSelectors()
        });
        cuts[3] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.bookSellFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _bookSellSelectors()
        });
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

    function _bookReplacementSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.computeBookId.selector;
        selectors[2] = IBookAdminFacet.getBookInfo.selector;
        selectors[3] = IBookAdminFacet.getMarketSideBook.selector;
    }

    function _bookDecommissionSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[1] = IBookAdminFacet.finalizeBookDecommission.selector;
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
