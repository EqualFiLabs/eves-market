// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import {DiamondCutFacet} from "./facets/DiamondCutFacet.sol";
import {LibDiamond} from "./libraries/LibDiamond.sol";

error FunctionNotFound(bytes4 selector);

contract EveMarketDiamond is IERC1155Receiver {
    constructor(address initialOwner, address diamondCutFacet) {
        require(initialOwner != address(0), "zero owner");

        LibDiamond.setContractOwner(initialOwner);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = DiamondCutFacet.diamondCut.selector;
        selectors[1] = DiamondCutFacet.freezeFacet.selector;
        selectors[2] = DiamondCutFacet.isSelectorFrozen.selector;
        selectors[3] = DiamondCutFacet.scheduleGovernanceOperation.selector;
        selectors[4] = DiamondCutFacet.cancelGovernanceOperation.selector;
        selectors[5] = DiamondCutFacet.finalizeGovernanceDelay.selector;
        selectors[6] = DiamondCutFacet.governanceOperationId.selector;
        selectors[7] = DiamondCutFacet.governanceOperationReadyAt.selector;
        selectors[8] = DiamondCutFacet.governanceDelay.selector;
        selectors[9] = DiamondCutFacet.governanceDelayFinalized.selector;

        LibDiamond.addFunctions(diamondCutFacet, selectors);
    }

    fallback() external payable {
        address facet = LibDiamond.facetAddress(msg.sig);
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
