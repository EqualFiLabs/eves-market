// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";

import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

interface IMarketFactoryFacet is MarketFactoryTypes {
    function createMarket(MarketCreationParams calldata params) external returns (bytes32 marketId);

    function createMarket(
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint128 initialVolume,
        bool initialDirection
    ) external returns (bytes32 marketId);

    function createMarketWithCollateralProfile(uint8 profileId, MarketCreationParams calldata params)
        external
        returns (bytes32 marketId);

    function createMarketWithCollateralProfile(
        uint8 profileId,
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint128 initialVolume,
        bool initialDirection
    ) external returns (bytes32 marketId);

    function createMarkets(MarketCreationParams[] calldata params) external returns (bytes32[] memory marketIds);

    function createMarketGroup(MarketGroupCreationParams calldata params)
        external
        returns (bytes32 groupId, bytes32[] memory marketIds);

    function createMarketGroup(string calldata title, MarketCreationParams[] calldata params)
        external
        returns (bytes32 groupId, bytes32[] memory marketIds);

    function createMarketGroupFromExisting(ExistingMarketGroupCreationParams calldata params)
        external
        returns (bytes32 groupId);

    function addMarketsToGroup(bytes32 groupId, ExistingGroupMarketParam[] calldata markets) external;

    function getMarketPositions(bytes32 marketId)
        external
        view
        returns (bytes32 conditionId, address collateralToken, uint256 yesPositionId, uint256 noPositionId);

    function getMarketTokenInfo(bytes32 marketId) external view returns (MarketTokenInfo memory tokenInfo);

    function getCollateralProfile(uint8 profileId) external view returns (CollateralProfileView memory profile);

    function getCollateralProfileParimutuelConfig(uint8 profileId)
        external
        view
        returns (uint128 creationSeedAmount, uint128 minEntry);

    function getCollateralProfileParlayUnderwritingFee(uint8 profileId) external view returns (uint128 underwritingFee);

    function getMarketInfo(bytes32 marketId) external view returns (MarketInfo memory marketInfo);

    function getMarketSummaries(address user, bytes32[] calldata marketIds)
        external
        view
        returns (MarketSummary[] memory summaries);

    function getMarketMetadata(bytes32 marketId) external view returns (MarketMetadataView memory metadata);

    function getMarketDisplay(bytes32 marketId) external view returns (MarketDisplayView memory metadata);

    function getMarketExternalRef(bytes32 marketId) external view returns (MarketExternalRefView memory externalRef);

    function getMarketGroup(bytes32 groupId) external view returns (MarketGroupView memory group);

    function getMarketGroupMarkets(bytes32 groupId) external view returns (bytes32[] memory marketIds);

    function getGroupMarketDisplay(bytes32 groupId, bytes32 marketId)
        external
        view
        returns (GroupMarketDisplayView memory display);

    function getPositionMetadata(address positionToken, uint256 positionId)
        external
        view
        returns (PositionMetadataView memory metadata);

    function positionTokenURI(address positionToken, uint256 positionId) external view returns (string memory uri);

    function getMarketConfig() external view returns (MarketConfigView memory config);

    function getUserMarketPositions(address user, bytes32[] calldata marketIds)
        external
        view
        returns (uint256[] memory yesBalances, uint256[] memory noBalances);

    function computeMarketId(
        string calldata question,
        string calldata category,
        uint64 tradingStartTime,
        uint64 expiryTime,
        address collateralToken,
        LibEveMarket.MarketType marketType,
        LibEveMarket.PositionTokenType positionTokenType
    ) external pure returns (bytes32 marketId);

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
    ) external pure returns (bytes32 marketId);
}
