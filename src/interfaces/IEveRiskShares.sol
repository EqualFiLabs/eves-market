// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

interface IEveRiskShares is IERC1155 {
    error ZeroAddress();
    error NotPool(address caller);

    function pool() external view returns (address);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function mint(address to, uint256 id, uint256 amount) external;

    function burn(address from, uint256 id, uint256 amount) external;

    function batchMint(address to, uint256[] calldata ids, uint256[] calldata amounts) external;

    function batchBurn(address from, uint256[] calldata ids, uint256[] calldata amounts) external;
}
