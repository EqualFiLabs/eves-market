// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "../libraries/Errors.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract DiamondCutFacet {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    event DiamondCut(FacetCut[] diamondCut, address init, bytes initCalldata);

    function diamondCut(FacetCut[] calldata diamondCut_, address init, bytes calldata initCalldata) external {
        LibDiamond.enforceIsContractOwner();

        for (uint256 index = 0; index < diamondCut_.length; ++index) {
            FacetCut calldata cut = diamondCut_[index];

            if (cut.action == FacetCutAction.Add) {
                bytes4[] memory selectorsToAdd = cut.functionSelectors;
                LibDiamond.addFunctions(cut.facetAddress, selectorsToAdd);
                continue;
            }

            bytes4[] memory selectors = cut.functionSelectors;
            _enforceSelectorsNotFrozen(selectors);

            if (cut.action == FacetCutAction.Replace) {
                LibDiamond.replaceFunctions(cut.facetAddress, selectors);
                continue;
            }

            if (cut.facetAddress != address(0)) {
                revert Errors.RemoveFacetMustBeZero(cut.facetAddress);
            }
            LibDiamond.removeFunctions(selectors);
        }

        emit DiamondCut(diamondCut_, init, initCalldata);
        LibDiamond.initializeDiamondCut(init, initCalldata);
    }

    function freezeFacet(bytes4[] calldata selectors) external {
        LibDiamond.enforceIsContractOwner();

        for (uint256 index = 0; index < selectors.length; ++index) {
            LibDiamond.freezeSelector(selectors[index]);
        }
    }

    function isSelectorFrozen(bytes4 selector) external view returns (bool) {
        return LibDiamond.isSelectorFrozen(selector);
    }

    function _enforceSelectorsNotFrozen(bytes4[] memory selectors) private view {
        for (uint256 index = 0; index < selectors.length; ++index) {
            if (LibDiamond.isSelectorFrozen(selectors[index])) {
                revert Errors.SelectorFrozen(selectors[index]);
            }
        }
    }
}
