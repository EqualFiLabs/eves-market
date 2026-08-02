// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {Errors} from "../libraries/Errors.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibMarketCreation} from "../libraries/LibMarketCreation.sol";
import {LibMarketMetadata} from "../libraries/LibMarketMetadata.sol";
import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

contract MarketViewFacet is MarketFactoryTypes {
    function getMarketPositions(bytes32 marketId)
        external
        view
        returns (bytes32 conditionId, address collateralToken, uint256 yesPositionId, uint256 noPositionId)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        conditionId = market.conditionId;
        collateralToken = market.collateralToken;
        yesPositionId = market.yesPositionId;
        noPositionId = market.noPositionId;
    }

    function getMarketTokenInfo(bytes32 marketId) external view returns (MarketTokenInfo memory tokenInfo) {
        LibEveMarket.Market storage market = LibMarketAccess.requireExistingMarket(LibEveMarket.store(), marketId);
        tokenInfo = MarketTokenInfo({
            positionTokenType: uint8(market.positionTokenType),
            positionToken: market.positionToken,
            collateralToken: market.collateralToken,
            resolutionId: market.resolutionId,
            conditionId: market.conditionId,
            yesPositionId: market.yesPositionId,
            noPositionId: market.noPositionId
        });
    }

    function getCollateralProfile(uint8 profileId) external view returns (CollateralProfileView memory profileView) {
        LibEveMarket.CollateralProfile storage profile = LibEveMarket.store().collateralProfiles[profileId];
        profileView = CollateralProfileView({
            collateralToken: profile.collateralToken,
            wrapperToken: profile.wrapperToken,
            payoutUnit: profile.payoutUnit,
            marketCreationFee: profile.marketCreationFee,
            enabled: profile.enabled
        });
    }

    function getCollateralProfileParimutuelConfig(uint8 profileId)
        external
        view
        returns (uint128 creationSeedAmount, uint128 minEntry)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        creationSeedAmount = state.parimutuelProfileCreationSeedAmount[profileId];
        minEntry = state.parimutuelProfileMinEntry[profileId];
    }

    function getCollateralProfileParlayUnderwritingFee(uint8 profileId)
        external
        view
        returns (uint128 underwritingFee)
    {
        underwritingFee = LibEveMarket.store().parlayUnderwritingFeeByProfile[profileId];
    }

    function getMarketInfo(bytes32 marketId) external view returns (MarketInfo memory marketInfo) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requireExistingMarket(state, marketId);

        marketInfo = LibMarketMetadata.marketInfo(market);
    }

    function getMarketSummaries(address user, bytes32[] calldata marketIds)
        external
        view
        returns (MarketSummary[] memory summaries)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 length = marketIds.length;
        bool includeBalances = user != address(0);

        summaries = new MarketSummary[](length);
        for (uint256 index = 0; index < length; ++index) {
            LibEveMarket.Market storage market = LibMarketAccess.requireExistingMarket(state, marketIds[index]);
            uint256 yesBalance;
            uint256 noBalance;

            if (includeBalances) {
                IERC1155 positionToken = IERC1155(market.positionToken);
                yesBalance = positionToken.balanceOf(user, market.yesPositionId);
                noBalance = positionToken.balanceOf(user, market.noPositionId);
            }

            summaries[index] = MarketSummary({
                marketInfo: LibMarketMetadata.marketInfo(market),
                disputeDeadline: state.resolutions[market.marketId].disputeDeadline,
                yesBalance: yesBalance,
                noBalance: noBalance
            });
        }
    }

    function getMarketConfig() external view returns (MarketConfigView memory config) {
        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;

        config = MarketConfigView({
            defaultConditionalTokens: marketConfig.defaultConditionalTokens,
            evesPositionManager: marketConfig.evesPositionManager,
            collateralToken: marketConfig.collateralToken,
            eveToken: marketConfig.eveToken,
            eveTreasury: marketConfig.eveTreasury,
            stakingVault: marketConfig.stakingVault,
            parimutuelShareToken: marketConfig.parimutuelShareToken,
            orderbookFeeConfig: BookFeeConfigView({
                entryFeeBps: marketConfig.orderbookFeeConfig.entryFeeBps,
                makerFeeBps: marketConfig.orderbookFeeConfig.makerFeeBps,
                creatorFeeBps: marketConfig.orderbookFeeConfig.creatorFeeBps,
                protocolFeeBps: marketConfig.orderbookFeeConfig.protocolFeeBps,
                vaultFeeBps: marketConfig.orderbookFeeConfig.vaultFeeBps
            }),
            spotFeeConfig: SpotFeeConfigView({
                tradeFeeBps: marketConfig.spotFeeConfig.tradeFeeBps,
                makerFeeBps: marketConfig.spotFeeConfig.makerFeeBps,
                protocolFeeBps: marketConfig.spotFeeConfig.protocolFeeBps,
                vaultFeeBps: marketConfig.spotFeeConfig.vaultFeeBps
            }),
            comboFeeConfig: ComboFeeConfigView({
                tradeFeeBps: marketConfig.comboFeeConfig.tradeFeeBps,
                makerFeeBps: marketConfig.comboFeeConfig.makerFeeBps,
                creatorFeeBps: marketConfig.comboFeeConfig.creatorFeeBps,
                protocolFeeBps: marketConfig.comboFeeConfig.protocolFeeBps,
                vaultFeeBps: marketConfig.comboFeeConfig.vaultFeeBps
            }),
            parimutuelFeeConfig: ParimutuelFeeConfigView({
                entryFeeBps: marketConfig.parimutuelFeeConfig.entryFeeBps,
                creatorFeeBps: marketConfig.parimutuelFeeConfig.creatorFeeBps,
                protocolFeeBps: marketConfig.parimutuelFeeConfig.protocolFeeBps,
                vaultFeeBps: marketConfig.parimutuelFeeConfig.vaultFeeBps
            }),
            parimutuelMinEntry: marketConfig.parimutuelMinEntry,
            parimutuelCreationSeedAmount: marketConfig.parimutuelCreationSeedAmount,
            marketCreationFee: marketConfig.marketCreationFee,
            spotBookCreationFee: marketConfig.spotBookCreationFee,
            comboMarketCreationFee: marketConfig.comboMarketCreationFee,
            marketCreationBond: marketConfig.marketCreationBond,
            bondToken: marketConfig.bondToken,
            resolutionBondL1: marketConfig.resolutionBondL1,
            resolutionBondL2: marketConfig.resolutionBondL2,
            minMarketDuration: marketConfig.minMarketDuration,
            maxMarketDuration: marketConfig.maxMarketDuration,
            disputeWindow: marketConfig.disputeWindow,
            creatorSettleGrace: marketConfig.creatorSettleGrace,
            openResolutionTimeout: marketConfig.openResolutionTimeout,
            marketCreationBatchCap: marketConfig.marketCreationBatchCap,
            maxEscalation: marketConfig.maxEscalation,
            permissionlessCreationEnabled: marketConfig.permissionlessCreationEnabled,
            delayedOrderProtectionDelayBlocks: marketConfig.delayedOrderProtectionDelayBlocks,
            delayedOrderExecutionGraceBlocks: marketConfig.delayedOrderExecutionGraceBlocks,
            delayedOrderRestingDurationMinutes: marketConfig.delayedOrderRestingDurationMinutes,
            delayedOrderProcessorFeeShareBps: marketConfig.delayedOrderProcessorFeeShareBps,
            delayedOrderProcessingMode: uint8(marketConfig.delayedOrderProcessingMode)
        });
    }

    function getUserMarketPositions(address user, bytes32[] calldata marketIds)
        external
        view
        returns (uint256[] memory yesBalances, uint256[] memory noBalances)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 length = marketIds.length;

        yesBalances = new uint256[](length);
        noBalances = new uint256[](length);

        for (uint256 index = 0; index < length; ++index) {
            LibEveMarket.Market storage market = LibMarketAccess.requireExistingMarket(state, marketIds[index]);
            IERC1155 positionToken = IERC1155(market.positionToken);
            yesBalances[index] = positionToken.balanceOf(user, market.yesPositionId);
            noBalances[index] = positionToken.balanceOf(user, market.noPositionId);
        }
    }

    function getMarketMetadata(bytes32 marketId) external view returns (MarketMetadataView memory metadataView) {
        LibEveMarket.MarketMetadata storage metadata = LibEveMarket.store().marketMetadata[marketId];
        if (!metadata.exists) {
            revert Errors.MarketNotFound(marketId);
        }

        metadataView = LibMarketMetadata.marketMetadataView(metadata);
    }

    function getMarketDisplay(bytes32 marketId) external view returns (MarketDisplayView memory displayView) {
        LibEveMarket.MarketDisplayMetadata storage display = LibEveMarket.store().marketDisplayMetadata[marketId];
        if (!display.exists) {
            revert Errors.MarketNotFound(marketId);
        }

        displayView = MarketDisplayView({
            marketId: display.marketId,
            slug: display.slug,
            title: display.title,
            metadataURI: display.metadataURI,
            metadataHash: display.metadataHash,
            rulesHash: display.rulesHash,
            externalRefHash: display.externalRefHash,
            exists: display.exists
        });
    }

    function getMarketExternalRef(bytes32 marketId)
        external
        view
        returns (MarketExternalRefView memory externalRefView)
    {
        LibEveMarket.ExternalMarketReference storage externalRef = LibEveMarket.store().marketExternalRefs[marketId];
        externalRefView = MarketExternalRefView({
            marketId: externalRef.marketId,
            source: externalRef.source,
            sourceEventIdHash: externalRef.sourceEventIdHash,
            sourceMarketIdHash: externalRef.sourceMarketIdHash,
            sourceSlugHash: externalRef.sourceSlugHash,
            sourceConditionIdHash: externalRef.sourceConditionIdHash,
            snapshotHash: externalRef.snapshotHash,
            exists: externalRef.exists
        });
    }

    function getMarketGroup(bytes32 groupId) external view returns (MarketGroupView memory groupView) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MarketGroupMetadata storage group = state.marketGroups[groupId];
        if (!group.exists) {
            revert Errors.MarketNotFound(groupId);
        }

        groupView = MarketGroupView({
            groupId: group.groupId,
            creator: group.creator,
            slug: group.slug,
            title: group.title,
            archetype: group.archetype,
            createdAt: group.createdAt,
            marketCount: state.marketGroupMarketIds[groupId].length,
            exists: group.exists
        });
    }

    function getMarketGroupMarkets(bytes32 groupId) external view returns (bytes32[] memory marketIds) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        if (!state.marketGroups[groupId].exists) {
            revert Errors.MarketNotFound(groupId);
        }
        marketIds = state.marketGroupMarketIds[groupId];
    }

    function getGroupMarketDisplay(bytes32 groupId, bytes32 marketId)
        external
        view
        returns (GroupMarketDisplayView memory displayView)
    {
        LibEveMarket.GroupMarketDisplay storage display = LibEveMarket.store().groupMarketDisplays[groupId][marketId];
        displayView = GroupMarketDisplayView({
            groupId: display.groupId,
            marketId: display.marketId,
            sortOrder: display.sortOrder,
            groupType: display.groupType,
            lineValueBps: display.lineValueBps,
            displayLabel: display.displayLabel,
            lineLabel: display.lineLabel,
            exists: display.exists
        });
    }

    function getPositionMetadata(address positionToken, uint256 positionId)
        external
        view
        returns (PositionMetadataView memory metadataView)
    {
        LibEveMarket.PositionMetadata storage metadata =
            LibEveMarket.store().positionMetadata[positionToken][positionId];

        metadataView = PositionMetadataView({
            positionToken: positionToken,
            positionId: positionId,
            marketId: metadata.marketId,
            outcome: metadata.outcome,
            outcomeLabel: metadata.exists ? LibMarketMetadata.outcomeLabelFor(metadata.marketId, metadata.outcome) : "",
            exists: metadata.exists
        });
    }

    function positionTokenURI(address positionToken, uint256 positionId) external view returns (string memory uri) {
        uri = LibMarketMetadata.positionTokenURI(positionToken, positionId);
    }

    function computeMarketId(
        string calldata question,
        string calldata category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        address collateralToken,
        LibEveMarket.MarketType marketType,
        LibEveMarket.PositionTokenType positionTokenType
    ) external pure returns (bytes32 marketId) {
        marketId = LibMarketCreation.marketIdFor(
            question, category, tradingStartTime, expiryTime, collateralToken, marketType, positionTokenType
        );
    }

    function computeProfileMarketId(
        string calldata question,
        string calldata category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        address collateralToken,
        uint8 profileId,
        uint128 payoutUnit,
        LibEveMarket.MarketType marketType,
        LibEveMarket.PositionTokenType positionTokenType
    ) external pure returns (bytes32 marketId) {
        marketId = LibMarketCreation.profileMarketIdFor(
            question,
            category,
            tradingStartTime,
            expiryTime,
            collateralToken,
            profileId,
            payoutUnit,
            marketType,
            positionTokenType
        );
    }
}
