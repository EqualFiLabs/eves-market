// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

import {IEveRiskShares} from "./interfaces/IEveRiskShares.sol";

contract EveRiskShares is ERC1155, IEveRiskShares {
    address public immutable override pool;
    string public constant override name = "EvRisk";
    string public constant override symbol = "EVRISK";

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert NotPool(msg.sender);
        }
        _;
    }

    constructor(address pool_, string memory uri_) ERC1155(uri_) {
        if (pool_ == address(0)) {
            revert ZeroAddress();
        }

        pool = pool_;
    }

    function mint(address to, uint256 id, uint256 amount) external override onlyPool {
        _mint(to, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) external override onlyPool {
        _burn(from, id, amount);
    }

    function batchMint(address to, uint256[] calldata ids, uint256[] calldata amounts) external override onlyPool {
        _mintBatch(to, ids, amounts, "");
    }

    function batchBurn(address from, uint256[] calldata ids, uint256[] calldata amounts) external override onlyPool {
        _burnBatch(from, ids, amounts);
    }
}
