// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "../../libraries/Errors.sol";
import {LibCLOBBook} from "../../libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../libraries/LibMarketCreation.sol";
import {LibParlay} from "../../libraries/LibParlay.sol";
import {ParlayBase} from "./ParlayBase.sol";

contract ParlayBookFacet is ParlayBase {
    function createParlayTicketBook(uint256 ticketId, uint8 tickPresetId, bytes32 salt)
        external
        nonReentrant
        returns (bytes32 bookId)
    {
        LibParlay.Config storage config = _requireConfig();
        _requireBucket(LibParlay.store(), ticketId);

        LibEveMarket.EveMarketStorage storage marketState = LibEveMarket.store();
        bookId = LibCLOBBook.standaloneBookId(
            msg.sender,
            LibEveMarket.BookAssetType.ERC1155,
            LibEveMarket.BaseTransferMode.EXACT,
            config.ticketToken,
            ticketId,
            marketState.config.collateralToken,
            tickPresetId,
            salt
        );
        if (marketState.books[bookId].bookId != bytes32(0)) {
            revert Errors.BookAlreadyExists(bookId);
        }

        LibMarketCreation.collectCreationFee(
            marketState.config.collateralToken,
            marketState.config.eveTreasury,
            msg.sender,
            marketState.config.spotBookCreationFee
        );
        LibCLOBBook.registerStandaloneBook(
            marketState,
            bookId,
            LibEveMarket.BookAssetType.ERC1155,
            LibEveMarket.BaseTransferMode.EXACT,
            config.ticketToken,
            ticketId,
            marketState.config.collateralToken,
            tickPresetId,
            LibCLOBBook.spotBookFeeConfig(marketState.config.spotFeeConfig),
            msg.sender
        );
    }
}
