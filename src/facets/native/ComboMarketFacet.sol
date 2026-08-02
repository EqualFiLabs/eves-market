// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IComboMarketFacet} from "../../interfaces/IComboMarketFacet.sol";
import {NativePositionTypes} from "../../types/NativePositionTypes.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCLOBBook} from "../../libraries/LibCLOBBook.sol";
import {LibComboMarket} from "../../libraries/LibComboMarket.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {LibReentrancy} from "../../libraries/LibReentrancy.sol";

contract ComboMarketFacet is IComboMarketFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function createComboMarket(bytes32[] calldata marketIds, bool[] calldata yesLegs)
        external
        nonReentrant
        returns (ComboMarketPreparation memory preparation)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256[] memory legs = _prepareComboLegs(state, marketIds, yesLegs);
        _storeComboCondition(state, legs, preparation);
        _createComboMarket(state, msg.sender, preparation);
    }

    function computeComboBookId(bytes32 comboMarketId, bool isYesSide) external pure returns (bytes32 bookId) {
        bookId = LibCLOBBook.marketBookId(comboMarketId, isYesSide);
    }

    function getComboMarket(bytes32 comboMarketId)
        external
        view
        returns (NativePositionTypes.ComboMarketView memory comboMarket)
    {
        LibEveMarket.ComboMarket storage stored = LibEveMarket.store().comboMarkets[comboMarketId];
        comboMarket = NativePositionTypes.ComboMarketView({
            marketId: stored.marketId,
            conditionId: stored.conditionId,
            positionToken: stored.positionToken,
            yesPositionId: stored.yesPositionId,
            noPositionId: stored.noPositionId,
            yesBookId: stored.yesBookId,
            noBookId: stored.noBookId,
            creator: stored.creator,
            collateralToken: stored.collateralToken,
            createdAt: stored.createdAt,
            expiryTime: stored.expiryTime,
            exists: stored.exists
        });
    }

    function getComboBook(address positionToken, uint256 positionId) external view returns (bytes32 bookId) {
        bookId = LibEveMarket.store().comboBookByPositionKey[LibComboMarket.positionKey(positionToken, positionId)];
    }

    function _prepareComboLegs(
        LibEveMarket.EveMarketStorage storage state,
        bytes32[] calldata marketIds,
        bool[] calldata yesLegs
    ) internal returns (uint256[] memory legs) {
        uint256 length = marketIds.length;
        if (length != yesLegs.length) {
            revert Errors.ArrayLengthMismatch(length, yesLegs.length);
        }

        legs = new uint256[](length);
        for (uint256 index; index < length; ++index) {
            LibNativePosition.BinaryPositionIds memory ids =
                LibNativePosition.prepareBinaryCondition(state, marketIds[index]);
            legs[index] = yesLegs[index] ? ids.yesPositionId : ids.noPositionId;
        }
        _sortAscending(legs);
        LibCombinatorialPosition.validateCanonicalLiveBinaryLegsMemory(state, legs);
    }

    function _storeComboCondition(
        LibEveMarket.EveMarketStorage storage state,
        uint256[] memory legs,
        ComboMarketPreparation memory preparation
    ) internal {
        bool created;
        (preparation.conditionId, preparation.yesPositionId, preparation.noPositionId, created) =
            LibCombinatorialPosition.storeComboConditionFromMemory(state, legs);
        preparation.marketId = preparation.conditionId;
        preparation.yesBookId = LibCLOBBook.marketBookId(preparation.marketId, true);
        preparation.noBookId = LibCLOBBook.marketBookId(preparation.marketId, false);

        if (created) {
            LibEveMarket.ComboCondition storage condition = state.comboConditions[preparation.conditionId];
            emit Events.ComboConditionPrepared(
                preparation.conditionId,
                condition.legsHash,
                condition.legCount,
                preparation.yesPositionId,
                preparation.noPositionId,
                legs
            );
        }
    }

    function _createComboMarket(
        LibEveMarket.EveMarketStorage storage state,
        address creator,
        ComboMarketPreparation memory preparation
    ) internal {
        if (state.comboMarkets[preparation.marketId].exists) {
            revert Errors.ComboMarketAlreadyExists(preparation.marketId);
        }

        address positionToken = state.config.evesPositionManager;
        if (positionToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        address collateralToken = LibCombinatorialPosition.collateralTokenFor(state, preparation.conditionId);
        uint64 expiryTime =
            LibCombinatorialPosition.requireLiveConditionAndEarliestExpiry(state, preparation.conditionId);
        _collectComboMarketCreationFee(state, preparation.marketId, creator);
        _registerComboMarketBook(state, preparation, true, positionToken, collateralToken, expiryTime, creator);
        _registerComboMarketBook(state, preparation, false, positionToken, collateralToken, expiryTime, creator);

        LibEveMarket.ComboMarket storage comboMarket = state.comboMarkets[preparation.marketId];
        comboMarket.marketId = preparation.marketId;
        comboMarket.conditionId = preparation.conditionId;
        comboMarket.positionToken = positionToken;
        comboMarket.yesPositionId = preparation.yesPositionId;
        comboMarket.noPositionId = preparation.noPositionId;
        comboMarket.yesBookId = preparation.yesBookId;
        comboMarket.noBookId = preparation.noBookId;
        comboMarket.creator = creator;
        comboMarket.collateralToken = collateralToken;
        comboMarket.createdAt = uint64(block.timestamp);
        comboMarket.expiryTime = expiryTime;
        comboMarket.exists = true;

        state.comboBookByPositionKey[LibComboMarket.positionKey(positionToken, preparation.yesPositionId)] =
        preparation.yesBookId;
        state.comboBookByPositionKey[LibComboMarket.positionKey(positionToken, preparation.noPositionId)] =
        preparation.noBookId;

        emit Events.ComboMarketCreated(
            preparation.marketId,
            preparation.conditionId,
            creator,
            positionToken,
            preparation.yesPositionId,
            preparation.noPositionId,
            preparation.yesBookId,
            preparation.noBookId,
            collateralToken,
            expiryTime
        );
    }

    function _registerComboMarketBook(
        LibEveMarket.EveMarketStorage storage state,
        ComboMarketPreparation memory preparation,
        bool isYesSide,
        address positionToken,
        address collateralToken,
        uint64 expiryTime,
        address creator
    ) internal {
        LibCLOBBook.registerComboMarketBook(
            state,
            isYesSide ? preparation.yesBookId : preparation.noBookId,
            preparation.marketId,
            isYesSide,
            positionToken,
            isYesSide ? preparation.yesPositionId : preparation.noPositionId,
            collateralToken,
            expiryTime,
            creator
        );
    }

    function _sortAscending(uint256[] memory values) internal pure {
        uint256 length = values.length;
        for (uint256 index = 1; index < length; ++index) {
            uint256 value = values[index];
            uint256 cursor = index;
            while (cursor != 0 && values[cursor - 1] > value) {
                values[cursor] = values[cursor - 1];
                --cursor;
            }
            values[cursor] = value;
        }
    }

    function _collectComboMarketCreationFee(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        address creator
    ) internal {
        uint128 fee = state.config.comboMarketCreationFee;
        if (fee == 0 || creator == LibDiamond.contractOwner()) {
            return;
        }
        if (state.config.collateralToken == address(0) || state.config.eveTreasury == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20(state.config.collateralToken).safeTransferFrom(creator, state.config.eveTreasury, fee);
        emit Events.ComboMarketCreationFeePaid(marketId, creator, state.config.eveTreasury, fee);
    }
}
