// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

import {IParlayMetadataProvider} from "../interfaces/IParlayMetadataProvider.sol";
import {IParlayTicketToken} from "../interfaces/IParlayTicketToken.sol";

contract ParlayTicketToken is ERC1155, IParlayTicketToken {
    address public immutable override diamond;

    modifier onlyDiamond() {
        if (msg.sender != diamond) {
            revert NotDiamond(msg.sender);
        }
        _;
    }

    constructor(address diamond_, string memory uri_) ERC1155(uri_) {
        diamond = diamond_;
    }

    function mint(address to, uint256 id, uint256 amount) external override onlyDiamond {
        _mint(to, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) external override onlyDiamond {
        _burn(from, id, amount);
    }

    function uri(uint256 id) public view override returns (string memory) {
        if (diamond.code.length != 0) {
            try IParlayMetadataProvider(diamond).parlayTicketURI(address(this), id) returns (
                string memory metadataUri
            ) {
                if (bytes(metadataUri).length != 0) {
                    return metadataUri;
                }
            } catch {}
        }

        return super.uri(id);
    }
}
