// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {ProductAdapterTypes} from "./ProductAdapterTypes.sol";

abstract contract CurveCLOBTypes {
    struct FillBestParams {
        bytes32 marketId;
        bool isYesSide;
        uint128 maxCollateralIn;
        uint128 minSharesOut;
        uint128 maxAveragePrice;
        uint256[] curveIds;
        uint32[] expectedGenerations;
        bytes32[] expectedCommitments;
        address payer;
        address receiver;
    }

    struct FillBookParams {
        bytes32 bookId;
        uint128 maxQuoteIn;
        uint128 minBaseOut;
        uint128 maxAveragePrice;
        uint256[] curveIds;
        uint32[] expectedGenerations;
        bytes32[] expectedCommitments;
        address payer;
        address receiver;
    }

    struct FillBestResult {
        uint128 sharesOut;
        uint128 collateralUsed;
        uint128 feePaid;
        uint128 averagePrice;
        uint128 unfilledCollateral;
    }

    struct SellBookParams {
        bytes32 bookId;
        uint128 maxBaseIn;
        uint128 minQuoteOut;
        uint256[] curveIds;
        uint32[] expectedGenerations;
        bytes32[] expectedCommitments;
        address receiver;
    }

    struct SellExecutionContext {
        address source;
        address seller;
        address receiver;
        bool useEscrowedBase;
    }

    struct SellBookResult {
        uint128 baseSold;
        uint128 quoteOut;
        uint128 feePaid;
        uint128 averagePrice;
        uint128 unfilledBase;
    }

    struct CurveCreationParams {
        bool isYesSide;
        uint128 volume;
        uint72 startPrice;
        uint72 endPrice;
        uint24 durationMinutes;
        uint8 profileId;
        uint8 tickPresetId;
    }

    struct CurveUpdateParams {
        uint256 curveId;
        uint256 newPacked;
        uint32 expectedGeneration;
    }

    struct CurveTopUpParams {
        uint256 curveId;
        uint128 addedVolume;
    }

    struct MarketCurveTopUpParams {
        bytes32 marketId;
        CurveTopUpParams[] params;
    }

    struct MarketCurvePostParams {
        bytes32 marketId;
        LibEveMarket.PositionTokenType positionTokenType;
        CurveCreationParams[] params;
    }

    struct CurveInfo {
        uint256 curveId;
        bytes32 bookId;
        bytes32 marketId;
        address maker;
        bool isYesSide;
        LibEveMarket.CurveSide curveSide;
        LibEveMarket.BookAssetType assetType;
        address baseToken;
        uint256 baseTokenId;
        address quoteToken;
        bool active;
        uint128 currentPrice;
        uint128 remainingVolume;
        uint128 quoteEscrowRemaining;
        uint72 startPrice;
        uint72 endPrice;
        uint24 durationMinutes;
        uint8 profileId;
        uint8 tickPresetId;
        uint256 packed;
        uint64 createdAt;
        uint64 expiresAt;
        uint32 generation;
        ProductAdapterTypes.CurveBackingKind backingKind;
        ProductAdapterTypes.ProductAdapterKind adapterKind;
        bytes32 adapterBucketId;
        bytes32 adapterRiskDomainId;
        bytes32 adapterDataKey;
        bool adapterActive;
    }

    struct BookInfo {
        bytes32 bookId;
        bytes32 marketId;
        bool isYesSide;
        LibEveMarket.BookAssetType assetType;
        LibEveMarket.BaseTransferMode baseTransferMode;
        address baseToken;
        uint256 baseTokenId;
        address quoteToken;
        address creator;
        bool active;
        uint64 createdAt;
        uint64 expiryTime;
        uint128 lastTradePrice;
        uint256 totalCurveCount;
        uint128 totalFeePool;
        uint128 totalQuoteVolume;
        uint128 creatorFeesEscrowed;
        uint128 protocolFeesAccrued;
        uint16 entryFeeBps;
        uint16 makerFeeBps;
        uint16 creatorFeeBps;
        uint16 protocolFeeBps;
        uint16 seniorPoolFeeBps;
        uint16 resolverFeeBps;
        uint8 pricingMode;
        uint8 lifecycle;
        uint8 tickPresetId;
        uint64 decommissionRequestedAt;
        uint64 decommissionAvailableAt;
        uint128 tickSize;
        uint128 priceDenominator;
        uint128 minTick;
        uint128 maxTick;
        bool delayedExecutionEnabled;
    }
}
