// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Base64} from "../../lib/openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibNativePosition} from "./LibNativePosition.sol";
import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

library LibMarketMetadata {
    uint8 internal constant YES_OUTCOME = 1;
    uint8 internal constant NO_OUTCOME = 2;
    uint256 internal constant MAX_METADATA_QUESTION_BYTES = 512;
    uint256 internal constant MAX_METADATA_CATEGORY_BYTES = 80;
    uint256 internal constant MAX_METADATA_RESOLUTION_SOURCE_BYTES = 512;
    uint256 internal constant MAX_DISPLAY_SLUG_BYTES = 160;
    uint256 internal constant MAX_DISPLAY_TITLE_BYTES = 512;
    uint256 internal constant MAX_DISPLAY_SUBTITLE_BYTES = 512;
    uint256 internal constant MAX_DISPLAY_RULES_BYTES = 4096;
    uint256 internal constant MAX_DISPLAY_URL_BYTES = 512;
    uint256 internal constant MAX_DISPLAY_TAGS_JSON_BYTES = 2048;
    uint256 internal constant MAX_EXTERNAL_REF_BYTES = 256;

    string internal constant JSON_PREFIX = "data:application/json;base64,";
    string internal constant SVG_PREFIX = "data:image/svg+xml;base64,";

    function emptyDisplayInput() internal pure returns (MarketFactoryTypes.MarketDisplayInput memory display) {}

    function emptyExternalRefInput()
        internal
        pure
        returns (MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
    {}

    function emptyGroupMarketDisplayInput()
        internal
        pure
        returns (MarketFactoryTypes.GroupMarketDisplayInput memory display)
    {}

    function marketInfo(LibEveMarket.Market storage market)
        internal
        view
        returns (MarketFactoryTypes.MarketInfo memory info)
    {
        info = MarketFactoryTypes.MarketInfo({
            marketId: market.marketId,
            creator: market.creator,
            collateralToken: market.collateralToken,
            questionId: market.questionId,
            resolutionId: market.resolutionId,
            conditionId: market.conditionId,
            yesPositionId: market.yesPositionId,
            noPositionId: market.noPositionId,
            createdAt: market.createdAt,
            tradingStartTime: market.tradingStartTime,
            expiryTime: market.expiryTime,
            resolutionTime: market.resolutionTime,
            state: uint8(market.state),
            outcome: uint8(market.outcome),
            creationFeePaid: market.creationFeePaid,
            creationBond: market.creationBond,
            creationBondReleased: market.creationBondReleased,
            totalQuoteVolume: market.totalQuoteVolume,
            creatorFeesEscrowed: market.creatorFeesEscrowed,
            protocolFeesAccrued: market.protocolFeesAccrued,
            lastTradePrice: uint128(market.lastTradePrice),
            totalCurveCount: market.curveCount,
            creatorSettledHonestly: market.creatorSettledHonestly,
            creatorFeeEligible: market.creatorFeeEligible,
            creationBondReturnable: market.creationBondReturnable,
            marketType: uint8(market.marketType),
            positionTokenType: uint8(market.positionTokenType),
            positionToken: market.positionToken,
            orderbookEntryFeeBps: market.orderbookFeeConfig.entryFeeBps,
            orderbookMakerFeeBps: market.orderbookFeeConfig.makerFeeBps,
            orderbookCreatorFeeBps: market.orderbookFeeConfig.creatorFeeBps,
            orderbookProtocolFeeBps: market.orderbookFeeConfig.protocolFeeBps,
            orderbookSeniorPoolFeeBps: market.orderbookFeeConfig.seniorPoolFeeBps,
            parimutuelEntryFeeBps: market.parimutuelFeeConfig.entryFeeBps,
            parimutuelCreatorFeeBps: market.parimutuelFeeConfig.creatorFeeBps,
            parimutuelProtocolFeeBps: market.parimutuelFeeConfig.protocolFeeBps,
            parimutuelSeniorPoolFeeBps: market.parimutuelFeeConfig.seniorPoolFeeBps,
            collateralProfileId: market.collateralProfileId,
            payoutUnit: market.payoutUnit,
            delayedExecutionEnabled: market.delayedExecutionEnabled
        });
    }

    function marketMetadataView(LibEveMarket.MarketMetadata storage metadata)
        internal
        view
        returns (MarketFactoryTypes.MarketMetadataView memory view_)
    {
        view_ = MarketFactoryTypes.MarketMetadataView({
            marketId: metadata.marketId,
            question: metadata.question,
            category: metadata.category,
            resolutionSource: metadata.resolutionSource,
            creator: metadata.creator,
            tradingStartTime: metadata.tradingStartTime,
            expiryTime: metadata.expiryTime,
            marketType: uint8(metadata.marketType),
            positionTokenType: uint8(metadata.positionTokenType),
            collateralToken: metadata.collateralToken,
            positionToken: metadata.positionToken,
            resolutionId: metadata.resolutionId,
            conditionId: metadata.conditionId,
            yesPositionId: metadata.yesPositionId,
            noPositionId: metadata.noPositionId,
            exists: metadata.exists,
            collateralProfileId: metadata.collateralProfileId,
            payoutUnit: metadata.payoutUnit
        });
    }

    function syncExpiredMarket(LibEveMarket.Market storage market) internal returns (uint8 state_) {
        if (market.state == LibEveMarket.MarketState.Scheduled && block.timestamp >= market.tradingStartTime) {
            market.state = LibEveMarket.MarketState.Trading;
        }

        if (
            (market.state == LibEveMarket.MarketState.Trading || market.state == LibEveMarket.MarketState.Scheduled)
                && block.timestamp >= market.expiryTime
        ) {
            market.state = LibEveMarket.MarketState.Pending;
            emit Events.MarketExpired(market.marketId);
        }

        state_ = uint8(market.state);
    }

    function registerMarketMetadata(
        LibEveMarket.Market storage market,
        string memory question,
        string memory category,
        string memory resolutionSource
    ) internal {
        _validateRequiredField("question", bytes(question).length);
        _validateRequiredField("category", bytes(category).length);
        _validateRequiredField("resolutionSource", bytes(resolutionSource).length);
        _validateFieldLength("question", bytes(question).length, MAX_METADATA_QUESTION_BYTES);
        _validateFieldLength("category", bytes(category).length, MAX_METADATA_CATEGORY_BYTES);
        _validateFieldLength("resolutionSource", bytes(resolutionSource).length, MAX_METADATA_RESOLUTION_SOURCE_BYTES);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.marketMetadata[market.marketId] = LibEveMarket.MarketMetadata({
            marketId: market.marketId,
            question: question,
            category: category,
            resolutionSource: resolutionSource,
            creator: market.creator,
            tradingStartTime: market.tradingStartTime,
            expiryTime: market.expiryTime,
            marketType: market.marketType,
            positionTokenType: market.positionTokenType,
            collateralToken: market.collateralToken,
            positionToken: market.positionToken,
            resolutionId: market.resolutionId,
            conditionId: market.conditionId,
            yesPositionId: market.yesPositionId,
            noPositionId: market.noPositionId,
            exists: true,
            collateralProfileId: market.collateralProfileId,
            payoutUnit: market.payoutUnit
        });

        if (market.marketType != LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            state.positionMetadata[market.positionToken][market.yesPositionId] =
                LibEveMarket.PositionMetadata({marketId: market.marketId, outcome: YES_OUTCOME, exists: true});
            state.positionMetadata[market.positionToken][market.noPositionId] =
                LibEveMarket.PositionMetadata({marketId: market.marketId, outcome: NO_OUTCOME, exists: true});
            if (market.positionTokenType == LibEveMarket.PositionTokenType.CTF) {
                state.nativePositionMetadata[market.yesPositionId] = LibEveMarket.NativePositionMetadata({
                    moduleId: LibNativePosition.MODULE_BINARY,
                    conditionId: market.conditionId,
                    outcomeIndex: LibNativePosition.OUTCOME_YES,
                    marketId: market.marketId,
                    exists: true
                });
                state.nativePositionMetadata[market.noPositionId] = LibEveMarket.NativePositionMetadata({
                    moduleId: LibNativePosition.MODULE_BINARY,
                    conditionId: market.conditionId,
                    outcomeIndex: LibNativePosition.OUTCOME_NO,
                    marketId: market.marketId,
                    exists: true
                });
                state.ctfPositionMetadata[market.yesPositionId] = LibEveMarket.CTFPositionMetadata({
                    positionToken: market.positionToken,
                    collateralToken: market.collateralToken,
                    settlementAdapter: state.ctfSettlementAdapter,
                    conditionId: market.conditionId,
                    complementPositionId: market.noPositionId,
                    payoutUnit: market.payoutUnit,
                    exists: true
                });
                state.ctfPositionMetadata[market.noPositionId] = LibEveMarket.CTFPositionMetadata({
                    positionToken: market.positionToken,
                    collateralToken: market.collateralToken,
                    settlementAdapter: state.ctfSettlementAdapter,
                    conditionId: market.conditionId,
                    complementPositionId: market.yesPositionId,
                    payoutUnit: market.payoutUnit,
                    exists: true
                });
                state.ctfConditionYesPositionId[market.conditionId] = market.yesPositionId;
                state.ctfConditionNoPositionId[market.conditionId] = market.noPositionId;
            }
        }
    }

    function registerMarketDisplayMetadata(
        bytes32 marketId,
        MarketFactoryTypes.MarketDisplayInput memory display,
        bytes32 externalRefHash
    ) internal {
        _validateMarketDisplay(display);

        bytes32 metadataHash = _marketDisplayHash(display);
        bytes32 rulesHash = _hashOptionalString(display.rules);

        LibEveMarket.store().marketDisplayMetadata[marketId] = LibEveMarket.MarketDisplayMetadata({
            marketId: marketId,
            slug: display.slug,
            title: display.title,
            metadataURI: display.metadataURI,
            metadataHash: metadataHash,
            rulesHash: rulesHash,
            externalRefHash: externalRefHash,
            exists: true
        });

        emit Events.MarketDisplayMetadataSet(
            marketId,
            display.slug,
            display.title,
            display.subtitle,
            display.rules,
            display.imageUrl,
            display.iconUrl,
            display.metadataURI,
            display.tagsJson,
            metadataHash,
            rulesHash
        );
    }

    function registerMarketExternalReference(
        bytes32 marketId,
        MarketFactoryTypes.ExternalMarketRefInput memory externalRef
    ) internal returns (bytes32 externalRefHash) {
        if (!_hasExternalRef(externalRef)) {
            return bytes32(0);
        }
        _validateExternalRef(externalRef);

        externalRefHash = _externalRefHash(externalRef);
        LibEveMarket.store().marketExternalRefs[marketId] = LibEveMarket.ExternalMarketReference({
            marketId: marketId,
            source: externalRef.source,
            sourceEventIdHash: _hashOptionalString(externalRef.sourceEventId),
            sourceMarketIdHash: _hashOptionalString(externalRef.sourceMarketId),
            sourceSlugHash: _hashOptionalString(externalRef.sourceSlug),
            sourceConditionIdHash: _hashOptionalString(externalRef.sourceConditionId),
            snapshotHash: externalRef.snapshotHash,
            exists: true
        });

        emit Events.MarketExternalReferenceSet(
            marketId,
            externalRef.source,
            _hashOptionalString(externalRef.sourceEventId),
            externalRef.sourceEventId,
            externalRef.sourceMarketId,
            externalRef.sourceSlug,
            externalRef.sourceConditionId,
            externalRef.snapshotHash
        );
    }

    function registerMarketGroup(bytes32 groupId, address creator, MarketFactoryTypes.GroupDisplayInput memory display)
        internal
    {
        _validateRequiredField("groupTitle", bytes(display.title).length);
        _validateMarketGroupDisplay(display);

        LibEveMarket.store().marketGroups[groupId] = LibEveMarket.MarketGroupMetadata({
            groupId: groupId,
            creator: creator,
            slug: display.slug,
            title: display.title,
            metadataURI: display.metadataURI,
            archetype: display.archetype,
            createdAt: uint64(block.timestamp),
            exists: true
        });

        emit Events.MarketGroupDisplaySet(groupId, display.slug, display.title, display.archetype, display.metadataURI);
    }

    function registerGroupMarketDisplay(
        bytes32 groupId,
        bytes32 marketId,
        uint16 sortOrder,
        MarketFactoryTypes.GroupMarketDisplayInput memory display
    ) internal {
        _validateGroupMarketDisplay(display);

        LibEveMarket.store().groupMarketDisplays[groupId][marketId] = LibEveMarket.GroupMarketDisplay({
            groupId: groupId,
            marketId: marketId,
            sortOrder: sortOrder,
            groupType: display.groupType,
            lineValueBps: display.lineValueBps,
            displayLabel: display.displayLabel,
            lineLabel: display.lineLabel,
            exists: true
        });

        emit Events.GroupMarketDisplaySet(
            groupId,
            marketId,
            sortOrder,
            display.groupType,
            display.lineValueBps,
            display.displayLabel,
            display.lineLabel
        );
    }

    function positionTokenURI(address positionToken, uint256 positionId) internal view returns (string memory uri) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.PositionMetadata storage position = state.positionMetadata[positionToken][positionId];
        if (!position.exists) {
            return "";
        }

        LibEveMarket.MarketMetadata storage metadata = state.marketMetadata[position.marketId];
        if (!metadata.exists) {
            return "";
        }

        return
            string.concat(JSON_PREFIX, Base64.encode(bytes(_tokenJson(positionToken, positionId, position, metadata))));
    }

    function outcomeLabel(uint8 outcome) internal pure returns (string memory) {
        if (outcome == YES_OUTCOME) {
            return "YES";
        }
        if (outcome == NO_OUTCOME) {
            return "NO";
        }
        return "UNKNOWN";
    }

    function outcomeLabelFor(bytes32 marketId, uint8 outcome) internal view returns (string memory) {
        LibEveMarket.MarketMetadata storage metadata = LibEveMarket.store().marketMetadata[marketId];
        if (metadata.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            string[] storage labels = LibEveMarket.store().multiOutcomeLabels[marketId];
            if (outcome < labels.length) {
                return labels[outcome];
            }
        }
        return outcomeLabel(outcome);
    }

    function marketTypeLabel(LibEveMarket.MarketType marketType) internal pure returns (string memory) {
        if (marketType == LibEveMarket.MarketType.CLOB) {
            return "CLOB";
        }
        if (marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            return "MULTI_OUTCOME_ORDERBOOK";
        }
        return "PARIMUTUEL";
    }

    function _tokenJson(
        address positionToken,
        uint256 positionId,
        LibEveMarket.PositionMetadata storage position,
        LibEveMarket.MarketMetadata storage metadata
    ) internal view returns (string memory) {
        string memory outcome = outcomeLabelFor(position.marketId, position.outcome);
        string memory marketType = marketTypeLabel(metadata.marketType);

        return string.concat(
            '{"name":"Eves Market ',
            outcome,
            ' Position",',
            '"description":"',
            outcome,
            " position for an Eves Market ",
            marketType,
            ' prediction market.",',
            _metadataFieldsJson(positionToken, positionId, metadata, outcome, marketType),
            '"image":"',
            _imageUri(outcome, marketType),
            '",',
            '"attributes":',
            _attributesJson(metadata, outcome, marketType),
            "}"
        );
    }

    function _metadataFieldsJson(
        address positionToken,
        uint256 positionId,
        LibEveMarket.MarketMetadata storage metadata,
        string memory outcome,
        string memory marketType
    ) internal view returns (string memory) {
        string memory head = string.concat(
            '"question":"',
            Strings.escapeJSON(metadata.question),
            '",',
            '"outcome":"',
            outcome,
            '",',
            '"category":"',
            Strings.escapeJSON(metadata.category),
            '",',
            '"resolution_source":"',
            Strings.escapeJSON(metadata.resolutionSource),
            '",',
            '"market_type":"',
            marketType,
            '",'
        );

        string memory tail = string.concat(
            '"market_id":"',
            Strings.toHexString(uint256(metadata.marketId), 32),
            '",',
            '"resolution_id":"',
            Strings.toHexString(uint256(metadata.resolutionId), 32),
            '",',
            '"condition_id":"',
            Strings.toHexString(uint256(metadata.conditionId), 32),
            '",',
            '"position_token":"',
            Strings.toHexString(positionToken),
            '",',
            '"position_id":"',
            Strings.toString(positionId),
            '",',
            '"creator":"',
            Strings.toHexString(metadata.creator),
            '",',
            '"trading_start_time":',
            Strings.toString(metadata.tradingStartTime),
            ",",
            '"collateral_token":"',
            Strings.toHexString(metadata.collateralToken),
            '",',
            '"expiry_time":',
            Strings.toString(metadata.expiryTime),
            ","
        );

        return string.concat(head, tail);
    }

    function _attributesJson(
        LibEveMarket.MarketMetadata storage metadata,
        string memory outcome,
        string memory marketType
    ) internal view returns (string memory) {
        return string.concat(
            '[{"trait_type":"Protocol","value":"Eves Market"},',
            '{"trait_type":"Market Type","value":"',
            marketType,
            '"},',
            '{"trait_type":"Outcome","value":"',
            outcome,
            '"},',
            '{"trait_type":"Category","value":"',
            Strings.escapeJSON(metadata.category),
            '"},',
            '{"trait_type":"Resolution Source","value":"',
            Strings.escapeJSON(metadata.resolutionSource),
            '"},',
            '{"display_type":"date","trait_type":"Trading Start","value":',
            Strings.toString(metadata.tradingStartTime),
            "},",
            '{"display_type":"date","trait_type":"Expiry","value":',
            Strings.toString(metadata.expiryTime),
            "},",
            '{"trait_type":"Market ID","value":"',
            Strings.toHexString(uint256(metadata.marketId), 32),
            '"}]'
        );
    }

    function _imageUri(string memory outcome, string memory marketType) internal pure returns (string memory) {
        return string.concat(SVG_PREFIX, Base64.encode(bytes(_svgImage(outcome, marketType))));
    }

    function _svgImage(string memory outcome, string memory marketType) internal pure returns (string memory) {
        bool yesOutcome = Strings.equal(outcome, "YES");
        bool parimutuel = Strings.equal(marketType, "PARIMUTUEL");
        string memory accent = yesOutcome ? "#16a34a" : "#dc2626";
        string memory glow = yesOutcome ? "#86efac" : "#fca5a5";
        string memory subtitle = parimutuel ? "Parimutuel Share" : "Orderbook Position";

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='1200' height='1200' viewBox='0 0 1200 1200'>",
            "<rect width='1200' height='1200' fill='#111827'/>",
            "<circle cx='600' cy='560' r='390' fill='",
            accent,
            "' fill-opacity='0.16'/>",
            "<circle cx='600' cy='560' r='250' fill='",
            accent,
            "' fill-opacity='0.28' stroke='",
            glow,
            "' stroke-width='8'/>",
            "<text x='600' y='260' text-anchor='middle' fill='#e5e7eb' font-family='Inter,Arial,sans-serif' font-size='56'>Eves Market</text>",
            "<text x='600' y='620' text-anchor='middle' fill='#ffffff' font-family='Inter,Arial,sans-serif' font-size='190' font-weight='800'>",
            outcome,
            "</text>",
            "<text x='600' y='770' text-anchor='middle' fill='#cbd5e1' font-family='Inter,Arial,sans-serif' font-size='52'>",
            subtitle,
            "</text>",
            "</svg>"
        );
    }

    function _validateFieldLength(string memory fieldName, uint256 length, uint256 maxLength) internal pure {
        if (length > maxLength) {
            revert Errors.MetadataFieldTooLong(fieldName, length, maxLength);
        }
    }

    function _validateRequiredField(string memory fieldName, uint256 length) internal pure {
        if (length == 0) {
            revert Errors.MetadataFieldRequired(fieldName);
        }
    }

    function _validateMarketDisplay(MarketFactoryTypes.MarketDisplayInput memory display) internal pure {
        _validateFieldLength("slug", bytes(display.slug).length, MAX_DISPLAY_SLUG_BYTES);
        _validateFieldLength("title", bytes(display.title).length, MAX_DISPLAY_TITLE_BYTES);
        _validateFieldLength("subtitle", bytes(display.subtitle).length, MAX_DISPLAY_SUBTITLE_BYTES);
        _validateFieldLength("rules", bytes(display.rules).length, MAX_DISPLAY_RULES_BYTES);
        _validateFieldLength("imageUrl", bytes(display.imageUrl).length, MAX_DISPLAY_URL_BYTES);
        _validateFieldLength("iconUrl", bytes(display.iconUrl).length, MAX_DISPLAY_URL_BYTES);
        _validateFieldLength("metadataURI", bytes(display.metadataURI).length, MAX_DISPLAY_URL_BYTES);
        _validateFieldLength("tagsJson", bytes(display.tagsJson).length, MAX_DISPLAY_TAGS_JSON_BYTES);
    }

    function _validateMarketGroupDisplay(MarketFactoryTypes.GroupDisplayInput memory display) internal pure {
        _validateFieldLength("slug", bytes(display.slug).length, MAX_DISPLAY_SLUG_BYTES);
        _validateFieldLength("title", bytes(display.title).length, MAX_DISPLAY_TITLE_BYTES);
        _validateFieldLength("metadataURI", bytes(display.metadataURI).length, MAX_DISPLAY_URL_BYTES);
        _validateExternalRef(display.externalRef);
    }

    function _validateGroupMarketDisplay(MarketFactoryTypes.GroupMarketDisplayInput memory display) internal pure {
        _validateFieldLength("displayLabel", bytes(display.displayLabel).length, MAX_DISPLAY_TITLE_BYTES);
        _validateFieldLength("lineLabel", bytes(display.lineLabel).length, MAX_DISPLAY_TITLE_BYTES);
    }

    function _validateExternalRef(MarketFactoryTypes.ExternalMarketRefInput memory externalRef) internal pure {
        _validateFieldLength("sourceEventId", bytes(externalRef.sourceEventId).length, MAX_EXTERNAL_REF_BYTES);
        _validateFieldLength("sourceMarketId", bytes(externalRef.sourceMarketId).length, MAX_EXTERNAL_REF_BYTES);
        _validateFieldLength("sourceSlug", bytes(externalRef.sourceSlug).length, MAX_EXTERNAL_REF_BYTES);
        _validateFieldLength("sourceConditionId", bytes(externalRef.sourceConditionId).length, MAX_EXTERNAL_REF_BYTES);
    }

    function _hasExternalRef(MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
        internal
        pure
        returns (bool)
    {
        return externalRef.source != 0 || bytes(externalRef.sourceEventId).length != 0
            || bytes(externalRef.sourceMarketId).length != 0 || bytes(externalRef.sourceSlug).length != 0
            || bytes(externalRef.sourceConditionId).length != 0 || externalRef.snapshotHash != bytes32(0);
    }

    function _marketDisplayHash(MarketFactoryTypes.MarketDisplayInput memory display) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                display.slug,
                display.title,
                display.subtitle,
                display.rules,
                display.imageUrl,
                display.iconUrl,
                display.metadataURI,
                display.tagsJson
            )
        );
    }

    function _externalRefHash(MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                externalRef.source,
                externalRef.sourceEventId,
                externalRef.sourceMarketId,
                externalRef.sourceSlug,
                externalRef.sourceConditionId,
                externalRef.snapshotHash
            )
        );
    }

    function _hashOptionalString(string memory value) internal pure returns (bytes32) {
        if (bytes(value).length == 0) {
            return bytes32(0);
        }
        return keccak256(bytes(value));
    }
}
