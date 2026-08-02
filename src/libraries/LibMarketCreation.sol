// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibMarketCreation {
    using SafeERC20 for IERC20;

    bytes32 internal constant MARKET_ID_DOMAIN = keccak256("EVE_MARKET_ID");
    bytes32 internal constant RESOLUTION_ID_DOMAIN = keccak256("EVE_MARKET_RESOLUTION");
    bytes32 internal constant PARIMUTUEL_POSITION_DOMAIN = keccak256("EVE_PARIMUTUEL_POSITION");
    uint256 internal constant BINARY_OUTCOME_SLOT_COUNT = 2;

    struct CreationDetails {
        bytes32 questionId;
        bytes32 resolutionId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    struct CreationInput {
        uint64 currentTimestamp;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint128 creationFee;
        uint128 creationBond;
    }

    function marketIdFor(
        string memory question,
        string memory category,
        uint64 expiryTime,
        address collateralToken,
        LibEveMarket.MarketType marketType,
        LibEveMarket.PositionTokenType positionTokenType
    ) internal pure returns (bytes32 marketId) {
        marketId = marketIdFor(question, category, 0, expiryTime, collateralToken, marketType, positionTokenType);
    }

    function marketIdFor(
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        address collateralToken,
        LibEveMarket.MarketType marketType,
        LibEveMarket.PositionTokenType positionTokenType
    ) internal pure returns (bytes32 marketId) {
        marketId = keccak256(
            abi.encode(
                MARKET_ID_DOMAIN,
                marketType,
                positionTokenType,
                keccak256(bytes(question)),
                keccak256(bytes(category)),
                tradingStartTime,
                expiryTime,
                collateralToken
            )
        );
    }

    function profileMarketIdFor(
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        address collateralToken,
        uint8 collateralProfileId,
        uint128 payoutUnit,
        LibEveMarket.MarketType marketType,
        LibEveMarket.PositionTokenType positionTokenType
    ) internal pure returns (bytes32 marketId) {
        marketId = keccak256(
            abi.encode(
                MARKET_ID_DOMAIN,
                marketType,
                positionTokenType,
                keccak256(bytes(question)),
                keccak256(bytes(category)),
                tradingStartTime,
                expiryTime,
                collateralToken,
                collateralProfileId,
                payoutUnit
            )
        );
    }

    function multiOutcomeMarketIdFor(
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        address collateralToken,
        uint8 collateralProfileId,
        uint128 payoutUnit,
        uint8 outcomeCount,
        bytes32 outcomesHash,
        LibEveMarket.PositionTokenType positionTokenType
    ) internal pure returns (bytes32 marketId) {
        marketId = keccak256(
            abi.encode(
                MARKET_ID_DOMAIN,
                LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK,
                positionTokenType,
                keccak256(bytes(question)),
                keccak256(bytes(category)),
                tradingStartTime,
                expiryTime,
                collateralToken,
                collateralProfileId,
                payoutUnit,
                outcomeCount,
                outcomesHash
            )
        );
    }

    function resolutionIdFor(bytes32 marketId) internal pure returns (bytes32 resolutionId) {
        resolutionId = keccak256(abi.encode(RESOLUTION_ID_DOMAIN, marketId));
    }

    function creationInputForCaller(LibEveMarket.MarketConfig storage config, uint64 expiryTime)
        internal
        view
        returns (CreationInput memory creation)
    {
        creation = creationInputForCaller(config, uint64(block.timestamp), expiryTime);
    }

    function creationInputForCaller(
        LibEveMarket.MarketConfig storage config,
        uint64 tradingStartTime,
        uint64 expiryTime
    ) internal view returns (CreationInput memory creation) {
        (creation.creationFee, creation.creationBond) = creationCostsForCaller(
            config.permissionlessCreationEnabled, config.marketCreationFee, config.marketCreationBond
        );
        creation.currentTimestamp =
            validateSchedule(tradingStartTime, expiryTime, config.minMarketDuration, config.maxMarketDuration);
        creation.tradingStartTime = tradingStartTime;
        creation.expiryTime = expiryTime;
    }

    function parimutuelCreationInputForCaller(
        LibEveMarket.MarketConfig storage config,
        uint64 tradingStartTime,
        uint64 expiryTime
    ) internal view returns (CreationInput memory creation) {
        (creation.creationFee, creation.creationBond) = parimutuelCreationCostsForCaller(
            config.permissionlessCreationEnabled, config.parimutuelCreationSeedAmount, config.marketCreationBond
        );
        creation.currentTimestamp =
            validateSchedule(tradingStartTime, expiryTime, config.minMarketDuration, config.maxMarketDuration);
        creation.tradingStartTime = tradingStartTime;
        creation.expiryTime = expiryTime;
    }

    function profileCreationInputForCaller(
        LibEveMarket.MarketConfig storage config,
        uint128 marketCreationFee,
        uint64 tradingStartTime,
        uint64 expiryTime
    ) internal view returns (CreationInput memory creation) {
        (creation.creationFee, creation.creationBond) = creationCostsForCaller(
            config.permissionlessCreationEnabled, marketCreationFee, config.marketCreationBond
        );
        creation.currentTimestamp =
            validateSchedule(tradingStartTime, expiryTime, config.minMarketDuration, config.maxMarketDuration);
        creation.tradingStartTime = tradingStartTime;
        creation.expiryTime = expiryTime;
    }

    function prepareCLOBCreationDetails(
        address conditionalTokens,
        address collateralToken,
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        bytes32 marketId
    ) internal view returns (CreationDetails memory details) {
        details.questionId = questionIdFor(question, category, tradingStartTime, expiryTime);
        details.resolutionId = resolutionIdFor(marketId);
        details.conditionId = LibCTF.conditionIdFor(conditionalTokens, details.resolutionId);
        (details.yesPositionId, details.noPositionId) =
            LibCTF.derivePositionIds(conditionalTokens, collateralToken, details.conditionId);
    }

    function prepareProfileCLOBCreationDetails(
        address conditionalTokens,
        address collateralToken,
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime
    ) internal view returns (CreationDetails memory details) {
        details.questionId = questionIdFor(question, category, tradingStartTime, expiryTime);
        details.resolutionId = details.questionId;
        details.conditionId = LibCTF.conditionIdFor(conditionalTokens, details.questionId);
        (details.yesPositionId, details.noPositionId) =
            LibCTF.derivePositionIds(conditionalTokens, collateralToken, details.conditionId);
    }

    function prepareNativeMarketDetails(
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        bytes32 marketId
    ) internal pure returns (CreationDetails memory details) {
        details.questionId = questionIdFor(question, category, tradingStartTime, expiryTime);
        details.resolutionId = resolutionIdFor(marketId);
    }

    function prepareParimutuelCreationDetails(
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        bytes32 marketId
    ) internal view returns (CreationDetails memory details) {
        details = prepareNativeMarketDetails(question, category, tradingStartTime, expiryTime, marketId);
        details.yesPositionId = parimutuelPositionId(marketId, 1);
        details.noPositionId = parimutuelPositionId(marketId, 2);
    }

    function parimutuelPositionId(bytes32 marketId, uint8 side) internal view returns (uint256 positionId) {
        positionId = parimutuelPositionId(address(this), marketId, side);
    }

    function parimutuelPositionId(address diamond, bytes32 marketId, uint8 side)
        internal
        pure
        returns (uint256 positionId)
    {
        positionId = uint256(keccak256(abi.encode(PARIMUTUEL_POSITION_DOMAIN, diamond, marketId, side)));
    }

    function validateFunding(
        IERC20 collateralToken,
        IERC20 bondToken,
        address creator,
        uint128 creationFee,
        uint128 creationBond,
        uint128 initialVolume
    ) internal view {
        uint256 balance = collateralToken.balanceOf(creator);
        uint256 allowance = collateralToken.allowance(creator, address(this));
        uint256 creationFeeAmount = uint256(creationFee);

        if (balance < creationFeeAmount || allowance < creationFeeAmount) {
            revert Errors.InsufficientCreationFeeOrReserve();
        }

        if (initialVolume > 0) {
            uint256 totalRequired = creationFeeAmount + initialVolume;

            if (balance < totalRequired || allowance < totalRequired) {
                revert Errors.InsufficientInitialLiquidityCollateral();
            }
        }

        if (creationBond == 0) {
            return;
        }

        uint256 bondBalance = bondToken.balanceOf(creator);
        uint256 bondAllowance = bondToken.allowance(creator, address(this));
        uint256 creationBondAmount = uint256(creationBond);

        if (bondBalance < creationBondAmount || bondAllowance < creationBondAmount) {
            revert Errors.InsufficientCreationBond();
        }
    }

    function collectCreationFee(address collateralToken, address eveTreasury, address payer, uint128 creationFee)
        internal
    {
        if (creationFee == 0) {
            return;
        }

        IERC20(collateralToken).safeTransferFrom(payer, eveTreasury, creationFee);
    }

    function collectCreationBond(address bondToken, bytes32 marketId, address payer, uint128 creationBond) internal {
        if (creationBond == 0) {
            return;
        }

        IERC20(bondToken).safeTransferFrom(payer, address(this), creationBond);
        emit Events.CreationBondLocked(marketId, payer, creationBond);
    }

    function storeMarket(
        LibEveMarket.Market storage market,
        bytes32 marketId,
        LibEveMarket.MarketType marketType,
        LibEveMarket.PositionTokenType positionTokenType,
        address positionToken,
        address collateralToken,
        address creator,
        CreationDetails memory details,
        CreationInput memory creation
    ) internal {
        market.marketId = marketId;
        market.marketType = marketType;
        market.positionTokenType = positionTokenType;
        market.positionToken = positionToken;
        market.collateralToken = collateralToken;
        market.creator = creator;
        market.questionId = details.questionId;
        market.resolutionId = details.resolutionId;
        market.conditionId = details.conditionId;
        market.yesPositionId = details.yesPositionId;
        market.noPositionId = details.noPositionId;
        market.createdAt = creation.currentTimestamp;
        market.tradingStartTime = creation.tradingStartTime;
        market.expiryTime = creation.expiryTime;
        market.orderbookFeeConfig = LibEveMarket.store().config.orderbookFeeConfig;
        market.parimutuelFeeConfig = LibEveMarket.store().config.parimutuelFeeConfig;
        market.creationFeePaid = creation.creationFee;
        market.creationBond = creation.creationBond;
        market.outcome = LibEveMarket.MarketOutcome.Unresolved;
        market.state = creation.currentTimestamp < creation.tradingStartTime
            ? LibEveMarket.MarketState.Scheduled
            : LibEveMarket.MarketState.Trading;
    }

    function questionIdFor(string memory question, string memory category, uint64 expiryTime)
        internal
        pure
        returns (bytes32 questionId)
    {
        questionId = questionIdFor(question, category, 0, expiryTime);
    }

    function questionIdFor(string memory question, string memory category, uint64 tradingStartTime, uint64 expiryTime)
        internal
        pure
        returns (bytes32 questionId)
    {
        questionId = keccak256(abi.encode(question, category, tradingStartTime, expiryTime));
    }

    function creationCostsForCaller(
        bool permissionlessCreationEnabled,
        uint128 configuredCreationFee,
        uint128 configuredCreationBond
    ) internal view returns (uint128 creationFee, uint128 creationBond) {
        bool isOwner = msg.sender == LibDiamond.contractOwner();
        if (isOwner) {
            return (0, 0);
        }

        _enforceCreationAllowed(permissionlessCreationEnabled);

        return (configuredCreationFee, configuredCreationBond);
    }

    function parimutuelCreationCostsForCaller(
        bool permissionlessCreationEnabled,
        uint128 configuredCreationSeedAmount,
        uint128 configuredCreationBond
    ) internal view returns (uint128 creationSeedAmount, uint128 creationBond) {
        bool isOwner = msg.sender == LibDiamond.contractOwner();
        if (!isOwner) {
            _enforceCreationAllowed(permissionlessCreationEnabled);
        }

        return (configuredCreationSeedAmount, isOwner ? 0 : configuredCreationBond);
    }

    function _enforceCreationAllowed(bool permissionlessCreationEnabled) private view {
        if (!permissionlessCreationEnabled) {
            revert Errors.PermissionlessCreationDisabled(msg.sender);
        }
    }

    function validateExpiry(uint64 expiryTime, uint64 minMarketDuration, uint64 maxMarketDuration)
        internal
        view
        returns (uint64 currentTimestamp)
    {
        currentTimestamp = validateSchedule(uint64(block.timestamp), expiryTime, minMarketDuration, maxMarketDuration);
    }

    function validateSchedule(
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint64 minMarketDuration,
        uint64 maxMarketDuration
    ) internal view returns (uint64 currentTimestamp) {
        currentTimestamp = uint64(block.timestamp);

        if (block.timestamp >= expiryTime) {
            revert Errors.ExpiryTooSoon(expiryTime, currentTimestamp + 1);
        }

        uint64 minExpiry = tradingStartTime + minMarketDuration;
        if (expiryTime < minExpiry) {
            revert Errors.ExpiryTooSoon(expiryTime, minExpiry);
        }

        uint64 maxExpiry = tradingStartTime + maxMarketDuration;
        if (expiryTime > maxExpiry) {
            revert Errors.ExpiryTooLate(expiryTime, maxExpiry);
        }
    }
}
