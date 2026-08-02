// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibGovernanceDelay} from "./LibGovernanceDelay.sol";

library LibDiamond {
    function contractOwner() internal view returns (address) {
        return LibEveMarket.store().contractOwner;
    }

    function setContractOwner(address newOwner) internal {
        LibEveMarket.store().contractOwner = newOwner;
    }

    function enforceIsContractOwner() internal {
        enforceIsContractOwnerRaw();
        if (LibGovernanceDelay.s().finalized) {
            LibGovernanceDelay.consume(LibGovernanceDelay.operationId(msg.data));
        }
    }

    function enforceIsContractOwnerRaw() internal view {
        if (msg.sender != contractOwner()) {
            revert Errors.NotContractOwner(msg.sender);
        }
    }

    function facetAddress(bytes4 selector) internal view returns (address) {
        return LibEveMarket.store().selectorToFacet[selector];
    }

    function isSelectorFrozen(bytes4 selector) internal view returns (bool) {
        return LibEveMarket.store().frozenSelectors[selector];
    }

    function freezeSelector(bytes4 selector) internal {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        if (state.selectorToFacet[selector] == address(0)) revert Errors.SelectorMissing(selector);
        state.frozenSelectors[selector] = true;
    }

    function addFunctions(address facet, bytes4[] memory selectors) internal {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();

        _enforceFacet(facet);
        _enforceSelectorsNotEmpty(selectors);

        if (state.facetFunctionSelectors[facet].length == 0) {
            state.facetAddresses.push(facet);
        }

        for (uint256 index = 0; index < selectors.length; ++index) {
            bytes4 selector = selectors[index];

            _enforceSelectorNotFrozen(state, selector);

            if (state.selectorToFacet[selector] != address(0)) {
                revert Errors.SelectorAlreadyExists(selector);
            }

            state.selectorToFacet[selector] = facet;
            state.facetFunctionSelectors[facet].push(selector);
        }
    }

    function replaceFunctions(address facet, bytes4[] memory selectors) internal {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();

        _enforceFacet(facet);
        _enforceSelectorsNotEmpty(selectors);

        if (state.facetFunctionSelectors[facet].length == 0) {
            state.facetAddresses.push(facet);
        }

        for (uint256 index = 0; index < selectors.length; ++index) {
            bytes4 selector = selectors[index];
            _enforceSelectorNotFrozen(state, selector);
            address oldFacet = state.selectorToFacet[selector];

            if (oldFacet == address(0)) {
                revert Errors.SelectorMissing(selector);
            }
            if (oldFacet == facet) {
                revert Errors.SelectorUnchanged(selector, facet);
            }

            _removeSelectorFromFacet(oldFacet, selector);
            state.selectorToFacet[selector] = facet;
            state.facetFunctionSelectors[facet].push(selector);
        }
    }

    function removeFunctions(bytes4[] memory selectors) internal {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();

        _enforceSelectorsNotEmpty(selectors);

        for (uint256 index = 0; index < selectors.length; ++index) {
            bytes4 selector = selectors[index];
            _enforceSelectorNotFrozen(state, selector);
            address oldFacet = state.selectorToFacet[selector];

            if (oldFacet == address(0)) {
                revert Errors.SelectorMissing(selector);
            }

            delete state.selectorToFacet[selector];
            _removeSelectorFromFacet(oldFacet, selector);
        }
    }

    function initializeDiamondCut(address init, bytes memory initCalldata) internal {
        if (init == address(0)) {
            if (initCalldata.length != 0) {
                revert Errors.InitCalldataWithoutInit();
            }
            return;
        }

        if (init.code.length == 0) {
            revert Errors.InitHasNoCode(init);
        }
        if (initCalldata.length == 0) {
            revert Errors.InitCalldataEmpty();
        }

        (bool success, bytes memory reason) = init.delegatecall(initCalldata);
        if (success) {
            return;
        }

        if (reason.length == 0) {
            revert Errors.DiamondInitFailed();
        }

        assembly {
            revert(add(reason, 0x20), mload(reason))
        }
    }

    function _removeSelectorFromFacet(address facet, bytes4 selector) private {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        bytes4[] storage selectors = state.facetFunctionSelectors[facet];

        for (uint256 index = 0; index < selectors.length; ++index) {
            if (selectors[index] != selector) {
                continue;
            }

            uint256 lastIndex = selectors.length - 1;
            if (index != lastIndex) {
                selectors[index] = selectors[lastIndex];
            }
            selectors.pop();

            if (selectors.length == 0) {
                delete state.facetFunctionSelectors[facet];
                _removeFacetAddress(facet);
            }
            return;
        }

        revert Errors.SelectorNotOnFacet(selector, facet);
    }

    function _removeFacetAddress(address facet) private {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        address[] storage facets = state.facetAddresses;

        for (uint256 index = 0; index < facets.length; ++index) {
            if (facets[index] != facet) {
                continue;
            }

            uint256 lastIndex = facets.length - 1;
            if (index != lastIndex) {
                facets[index] = facets[lastIndex];
            }
            facets.pop();
            return;
        }
    }

    function _enforceFacet(address facet) private view {
        if (facet == address(0)) {
            revert Errors.FacetIsZero();
        }
        if (facet.code.length == 0) {
            revert Errors.FacetHasNoCode(facet);
        }
    }

    function _enforceSelectorsNotEmpty(bytes4[] memory selectors) private pure {
        if (selectors.length == 0) {
            revert Errors.SelectorsEmpty();
        }
    }

    function _enforceSelectorNotFrozen(LibEveMarket.EveMarketStorage storage state, bytes4 selector) private view {
        if (state.frozenSelectors[selector]) revert Errors.SelectorFrozen(selector);
    }
}
