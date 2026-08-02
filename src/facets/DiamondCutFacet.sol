// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "../libraries/Errors.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibGovernanceDelay} from "../libraries/LibGovernanceDelay.sol";

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
    event GovernanceOperationScheduled(bytes32 indexed operationId, uint64 readyAt, bytes callData);
    event GovernanceOperationCancelled(bytes32 indexed operationId);
    event GovernanceDelayFinalized(address indexed previousOwner, address indexed finalOwner, uint64 delay);

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

    function scheduleGovernanceOperation(bytes calldata callData)
        external
        returns (bytes32 operationId_, uint64 readyAt)
    {
        LibDiamond.enforceIsContractOwnerRaw();
        operationId_ = LibGovernanceDelay.operationId(callData);
        readyAt = LibGovernanceDelay.schedule(operationId_);
        emit GovernanceOperationScheduled(operationId_, readyAt, callData);
    }

    function cancelGovernanceOperation(bytes32 operationId_) external {
        LibDiamond.enforceIsContractOwnerRaw();
        LibGovernanceDelay.cancel(operationId_);
        emit GovernanceOperationCancelled(operationId_);
    }

    function finalizeGovernanceDelay(address finalOwner) external {
        LibDiamond.enforceIsContractOwnerRaw();
        LibGovernanceDelay.Storage storage state = LibGovernanceDelay.s();
        if (state.finalized) revert Errors.GovernanceDelayAlreadyFinalized();
        if (finalOwner == address(0)) revert Errors.ZeroAddress();
        address previousOwner = LibDiamond.contractOwner();
        LibDiamond.setContractOwner(finalOwner);
        state.finalized = true;
        emit GovernanceDelayFinalized(previousOwner, finalOwner, LibGovernanceDelay.MINIMUM_DELAY);
    }

    function governanceOperationId(bytes calldata callData) external view returns (bytes32) {
        return LibGovernanceDelay.operationId(callData);
    }

    function governanceOperationReadyAt(bytes32 operationId_) external view returns (uint64) {
        return LibGovernanceDelay.s().readyAt[operationId_];
    }

    function governanceDelay() external pure returns (uint64) {
        return LibGovernanceDelay.MINIMUM_DELAY;
    }

    function governanceDelayFinalized() external view returns (bool) {
        return LibGovernanceDelay.s().finalized;
    }
}
