// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library LibComboMarket {
    bytes32 internal constant COMBO_POSITION_BOOK_DOMAIN = keccak256("eve.combo.position.book");

    function positionKey(address positionToken, uint256 positionId) internal pure returns (bytes32 key) {
        key = keccak256(abi.encode(COMBO_POSITION_BOOK_DOMAIN, positionToken, positionId));
    }
}
