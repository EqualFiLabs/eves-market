// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IEvesNegRiskAdapter} from "../interfaces/IEvesNegRiskAdapter.sol";
import {IMultiOutcomeOrderbookFacet} from "../interfaces/IMultiOutcomeOrderbookFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibCollateralProfile} from "../libraries/LibCollateralProfile.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../libraries/LibMarketCreation.sol";
import {LibMarketMetadata} from "../libraries/LibMarketMetadata.sol";
import {LibMultiOutcome} from "../libraries/LibMultiOutcome.sol";
import {LibNativePosition} from "../libraries/LibNativePosition.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

contract MultiOutcomeOrderbookFacet {
    using SafeERC20 for IERC20;

    uint128 internal constant DEFAULT_COLLATERAL_PAYOUT_UNIT = 1 ether;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    struct MultiOutcomeCollateralContext {
        uint8 profileId;
        address collateralToken;
        uint128 payoutUnit;
        uint128 marketCreationFee;
        bool emitProfileEvent;
    }

    struct MultiOutcomeCreationContext {
        bytes32 marketId;
        uint8 outcomeCount;
        bytes32 outcomesHash;
        bytes32 conditionId;
        address positionToken;
        address adapter;
    }

    function createMultiOutcomeMarket(IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams calldata params)
        external
        nonReentrant
        returns (bytes32 marketId)
    {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        marketId = _createMultiOutcomeMarket(
            params,
            MultiOutcomeCollateralContext({
                profileId: 0,
                collateralToken: config.collateralToken,
                payoutUnit: DEFAULT_COLLATERAL_PAYOUT_UNIT,
                marketCreationFee: config.marketCreationFee,
                emitProfileEvent: false
            })
        );
    }

    function createMultiOutcomeMarketWithCollateralProfile(
        uint8 profileId,
        IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams calldata params
    ) external nonReentrant returns (bytes32 marketId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.CollateralProfile storage profile = LibCollateralProfile.requireEnabled(state, profileId);
        marketId = _createMultiOutcomeMarket(
            params,
            MultiOutcomeCollateralContext({
                profileId: profileId,
                collateralToken: profile.collateralToken,
                payoutUnit: profile.payoutUnit,
                marketCreationFee: profile.marketCreationFee,
                emitProfileEvent: true
            })
        );
    }

    function _createMultiOutcomeMarket(
        IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams calldata params,
        MultiOutcomeCollateralContext memory collateralContext
    ) internal returns (bytes32 marketId) {
        LibMultiOutcome.validateLabels(params.outcomes);
        LibMultiOutcome.validateOutcomeDisplayLength(params.outcomes.length, params.outcomeDisplay.length);
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        address adapterAddress = state.negRiskAdapter;
        if (adapterAddress == address(0)) {
            revert Errors.ZeroAddress();
        }
        IEvesNegRiskAdapter adapter = IEvesNegRiskAdapter(adapterAddress);
        if (adapter.collateralToken() != collateralContext.collateralToken) {
            revert Errors.UnsupportedCollateralToken(adapter.collateralToken(), collateralContext.collateralToken);
        }
        if (adapter.conditionalTokens() != state.config.defaultConditionalTokens) {
            revert Errors.UnsupportedCollateralToken(state.config.defaultConditionalTokens, adapter.conditionalTokens());
        }

        LibMarketCreation.CreationInput memory creation = LibMarketCreation.profileCreationInputForCaller(
            state.config, collateralContext.marketCreationFee, params.tradingStartTime, params.expiryTime
        );
        MultiOutcomeCreationContext memory creationContext;
        creationContext.positionToken = adapter.conditionalTokens();
        creationContext.adapter = adapterAddress;
        creationContext.outcomeCount = LibMultiOutcome.validateOutcomeCount(params.outcomes.length);
        creationContext.outcomesHash = LibMultiOutcome.outcomesHash(params.outcomes);

        marketId = LibMarketCreation.multiOutcomeMarketIdFor(
            params.question,
            params.category,
            params.tradingStartTime,
            params.expiryTime,
            collateralContext.collateralToken,
            collateralContext.profileId,
            collateralContext.payoutUnit,
            creationContext.outcomeCount,
            creationContext.outcomesHash,
            LibEveMarket.PositionTokenType.CTF
        );
        creationContext.marketId = marketId;
        if (state.markets[marketId].marketId != bytes32(0)) {
            revert Errors.MarketAlreadyExists(marketId);
        }

        LibMarketCreation.validateFunding(
            IERC20(collateralContext.collateralToken),
            IERC20(state.config.bondToken),
            msg.sender,
            creation.creationFee,
            creation.creationBond,
            0
        );

        creationContext.conditionId = adapter.prepareEvent(marketId, creationContext.outcomeCount);

        LibEveMarket.Market storage market =
            _storeMultiOutcomeMarket(state, params, collateralContext, creation, creationContext);

        LibMarketCreation.collectCreationFee(
            collateralContext.collateralToken, state.config.eveTreasury, msg.sender, creation.creationFee
        );
        LibMarketCreation.collectCreationBond(state.config.bondToken, marketId, msg.sender, creation.creationBond);

        _emitCreated(market, creationContext.outcomeCount, creationContext.outcomesHash);
        if (collateralContext.emitProfileEvent) {
            emit Events.MarketCollateralProfile(
                marketId,
                collateralContext.profileId,
                collateralContext.collateralToken,
                collateralContext.payoutUnit,
                creation.creationFee
            );
        }
    }

    function _storeMultiOutcomeMarket(
        LibEveMarket.EveMarketStorage storage state,
        IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams calldata params,
        MultiOutcomeCollateralContext memory collateralContext,
        LibMarketCreation.CreationInput memory creation,
        MultiOutcomeCreationContext memory creationContext
    ) internal returns (LibEveMarket.Market storage market) {
        LibMarketCreation.CreationDetails memory details =
            LibMarketCreation.prepareNativeMarketDetails(
                params.question, params.category, params.tradingStartTime, params.expiryTime, creationContext.marketId
            );
        details.conditionId = creationContext.conditionId;

        market = state.markets[creationContext.marketId];
        LibMarketCreation.storeMarket(
            market,
            creationContext.marketId,
            LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK,
            LibEveMarket.PositionTokenType.CTF,
            creationContext.positionToken,
            collateralContext.collateralToken,
            msg.sender,
            details,
            creation
        );
        market.collateralProfileId = collateralContext.profileId;
        market.payoutUnit = collateralContext.payoutUnit;

        LibMarketMetadata.registerMarketMetadata(market, params.question, params.category, params.resolutionSource);
        bytes32 externalRefHash = LibMarketMetadata.registerMarketExternalReference(market.marketId, params.externalRef);
        LibMarketMetadata.registerMarketDisplayMetadata(market.marketId, params.display, externalRefHash);
        _storeOutcomes(
            state,
            creationContext.marketId,
            creationContext.conditionId,
            creationContext.outcomesHash,
            creationContext.adapter,
            params.outcomes,
            params.outcomeDisplay
        );
        _ensureAllOutcomeBooks(state, market);
    }

    function splitOutcomeSet(bytes32 marketId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint256[] memory positionIds)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireUnresolvedMultiOutcome(state, marketId);
        LibEveMarket.Market storage market = state.markets[marketId];
        IERC20 collateral = IERC20(market.collateralToken);
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        collateral.forceApprove(multi.adapter, amount);
        IEvesNegRiskAdapter(multi.adapter).splitEvent(multi.conditionId, amount, receiver);
        collateral.forceApprove(multi.adapter, 0);
        positionIds = new uint256[](multi.outcomeCount);
        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            positionIds[outcome] = state.multiOutcomePositionIds[marketId][outcome];
        }

        emit Events.OutcomeSetSplit(marketId, msg.sender, amount);
    }

    function mergeOutcomeSet(bytes32 marketId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint128 collateralOut)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireUnresolvedMultiOutcome(state, marketId);
        LibEveMarket.Market storage market = state.markets[marketId];
        IERC1155 positionToken = IERC1155(market.positionToken);
        uint256[] memory positionIds = new uint256[](multi.outcomeCount);
        uint256[] memory amounts = new uint256[](multi.outcomeCount);
        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            uint256 positionId = state.multiOutcomePositionIds[marketId][outcome];
            positionIds[outcome] = positionId;
            amounts[outcome] = amount;
            uint256 balance = positionToken.balanceOf(msg.sender, positionId);
            if (balance < amount) {
                revert Errors.MissingCompleteOutcomeSet(marketId, outcome, amount, balance);
            }
        }

        positionToken.safeBatchTransferFrom(msg.sender, address(this), positionIds, amounts, "");
        positionToken.setApprovalForAll(multi.adapter, true);
        IEvesNegRiskAdapter(multi.adapter).mergeEvent(multi.conditionId, amount, receiver);
        positionToken.setApprovalForAll(multi.adapter, false);
        collateralOut = amount;

        emit Events.OutcomeSetMerged(marketId, msg.sender, amount);
    }

    function redeemOutcome(bytes32 marketId, uint8 outcome, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint128 collateralOut)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        if (!multi.resolved) {
            revert Errors.MultiOutcomeMarketNotResolved(marketId);
        }
        LibMultiOutcome.requireOutcome(multi, outcome);

        LibEveMarket.Market storage market = state.markets[marketId];
        uint256 positionId = state.multiOutcomePositionIds[marketId][outcome];
        IERC1155 positionToken = IERC1155(market.positionToken);
        positionToken.safeTransferFrom(msg.sender, address(this), positionId, amount, "");
        positionToken.setApprovalForAll(multi.adapter, true);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        uint256 payout = IEvesNegRiskAdapter(multi.adapter)
            .redeemPositions(state.multiOutcomeConditionIds[marketId][outcome], amounts, receiver);
        positionToken.setApprovalForAll(multi.adapter, false);
        collateralOut = uint128(payout);

        emit Events.OutcomeRedeemed(marketId, msg.sender, outcome, amount, collateralOut);
    }

    function _storeOutcomes(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        bytes32 eventId,
        bytes32 outcomesHash,
        address adapterAddress,
        string[] calldata outcomes,
        IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[] calldata outcomeDisplay
    ) internal {
        uint8 outcomeCount = uint8(outcomes.length);
        IEvesNegRiskAdapter adapter = IEvesNegRiskAdapter(adapterAddress);
        address positionToken = adapter.conditionalTokens();
        address collateralToken = state.markets[marketId].collateralToken;
        uint128 payoutUnit = state.markets[marketId].payoutUnit;
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
        multi.marketId = marketId;
        multi.conditionId = eventId;
        multi.outcomesHash = outcomesHash;
        multi.outcomeCount = outcomeCount;
        multi.exists = true;
        multi.adapter = adapterAddress;
        multi.wrappedCollateral = adapter.wrappedCollateral();

        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            state.multiOutcomeLabels[marketId].push(outcomes[outcome]);
            bytes32 questionId = adapter.questionIdFor(eventId, outcome);
            bytes32 conditionId = adapter.conditionIdFor(eventId, outcome);
            uint256 yesPositionId = adapter.positionIdFor(eventId, outcome, true);
            uint256 noPositionId = adapter.positionIdFor(eventId, outcome, false);
            state.multiOutcomeQuestionIds[marketId][outcome] = questionId;
            state.multiOutcomeConditionIds[marketId][outcome] = conditionId;
            state.multiOutcomePositionIds[marketId][outcome] = yesPositionId;
            state.multiOutcomeNoPositionIds[marketId][outcome] = noPositionId;
            state.positionMetadata[positionToken][yesPositionId] =
                LibEveMarket.PositionMetadata({marketId: marketId, outcome: outcome, exists: true});
            state.nativePositionMetadata[yesPositionId] = LibEveMarket.NativePositionMetadata({
                moduleId: LibNativePosition.MODULE_NEGRISK,
                conditionId: conditionId,
                outcomeIndex: LibNativePosition.OUTCOME_YES,
                marketId: marketId,
                exists: true
            });
            state.nativePositionMetadata[noPositionId] = LibEveMarket.NativePositionMetadata({
                moduleId: LibNativePosition.MODULE_NEGRISK,
                conditionId: conditionId,
                outcomeIndex: LibNativePosition.OUTCOME_NO,
                marketId: marketId,
                exists: true
            });
            state.ctfPositionMetadata[yesPositionId] = LibEveMarket.CTFPositionMetadata({
                positionToken: positionToken,
                collateralToken: collateralToken,
                settlementAdapter: adapterAddress,
                conditionId: conditionId,
                complementPositionId: noPositionId,
                payoutUnit: payoutUnit,
                exists: true
            });
            state.ctfPositionMetadata[noPositionId] = LibEveMarket.CTFPositionMetadata({
                positionToken: positionToken,
                collateralToken: collateralToken,
                settlementAdapter: adapterAddress,
                conditionId: conditionId,
                complementPositionId: yesPositionId,
                payoutUnit: payoutUnit,
                exists: true
            });
            state.ctfConditionYesPositionId[conditionId] = yesPositionId;
            state.ctfConditionNoPositionId[conditionId] = noPositionId;
            _storeOutcomeDisplay(state, marketId, outcome, outcomes[outcome], outcomeDisplay);
            emit Events.OutcomePositionPrepared(marketId, outcome, yesPositionId);
        }
    }

    function _storeOutcomeDisplay(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint8 outcome,
        string calldata fallbackLabel,
        IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[] calldata outcomeDisplay
    ) internal {
        if (outcomeDisplay.length == 0) {
            state.multiOutcomeDisplays[marketId][outcome] = LibEveMarket.MultiOutcomeDisplay({
                slug: "",
                displayLabel: fallbackLabel,
                abbreviation: "",
                iconUrl: "",
                externalRefHash: bytes32(0),
                exists: true
            });
            emit Events.MultiOutcomeDisplaySet(marketId, outcome, "", fallbackLabel, "", "", "", bytes32(0));
            return;
        }

        IMultiOutcomeOrderbookFacet.OutcomeDisplayInput calldata display = outcomeDisplay[outcome];
        string memory displayLabel = bytes(display.displayLabel).length == 0 ? fallbackLabel : display.displayLabel;
        LibMultiOutcome.validateOutcomeDisplay(display, displayLabel);
        bytes32 externalRefHash =
            bytes(display.externalOutcomeId).length == 0 ? bytes32(0) : keccak256(bytes(display.externalOutcomeId));

        state.multiOutcomeDisplays[marketId][outcome] = LibEveMarket.MultiOutcomeDisplay({
            slug: display.slug,
            displayLabel: displayLabel,
            abbreviation: display.abbreviation,
            iconUrl: display.iconUrl,
            externalRefHash: externalRefHash,
            exists: true
        });
        emit Events.MultiOutcomeDisplaySet(
            marketId,
            outcome,
            display.slug,
            displayLabel,
            display.abbreviation,
            display.iconUrl,
            display.externalOutcomeId,
            externalRefHash
        );
    }

    function _emitCreated(LibEveMarket.Market storage market, uint8 outcomeCount, bytes32 outcomesHash) internal {
        emit Events.MultiOutcomeMarketCreated(
            market.marketId, market.conditionId, msg.sender, outcomeCount, outcomesHash
        );
    }

    function _ensureOutcomeBook(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        uint8 outcome
    ) internal returns (bytes32 bookId) {
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, market.marketId);
        LibMultiOutcome.requireOutcome(multi, outcome);

        bookId = state.multiOutcomeBookIds[market.marketId][outcome];
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.multiOutcomeBookId(market.marketId, outcome);
            state.multiOutcomeBookIds[market.marketId][outcome] = bookId;
        }

        if (state.books[bookId].bookId == bookId) {
            return bookId;
        }

        LibCLOBBook.registerOutcomeBook(
            state,
            bookId,
            market.marketId,
            market.positionToken,
            state.multiOutcomePositionIds[market.marketId][outcome],
            market.collateralToken,
            market.createdAt,
            market.expiryTime,
            market.orderbookFeeConfig,
            market.creator
        );
        emit Events.OutcomeBookPrepared(market.marketId, outcome, bookId);
    }

    function _ensureAllOutcomeBooks(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Market storage market)
        internal
    {
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, market.marketId);
        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            _ensureOutcomeBook(state, market, outcome);
        }
    }
}
