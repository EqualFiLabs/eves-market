// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

interface IParimutuelFacet {
    struct CreateParimutuelMarketParams {
        string question;
        string category;
        string resolutionSource;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint64 epochWindow;
        MarketFactoryTypes.MarketDisplayInput display;
        MarketFactoryTypes.ExternalMarketRefInput externalRef;
    }

    struct PoolView {
        uint128 totalYesShares;
        uint128 totalNoShares;
        uint128 payoutPool;
        uint128 claimedPayout;
        uint128 claimedClaimableShares;
        uint8 rawResolvedOutcome;
        uint8 effectivePayoutOutcome;
        uint128 payoutPoolAtResolution;
        uint128 totalClaimableSharesAtResolution;
        bool dustSwept;
        bool finalized;
        uint128 impliedYesProbability;
        uint128 impliedNoProbability;
    }

    struct EntryPreview {
        uint128 amountIn;
        uint128 totalFee;
        uint128 creatorFee;
        uint128 protocolFee;
        uint128 seniorPoolFee;
        uint128 resolverFee;
        uint128 netCollateral;
        uint128 sharesMinted;
        uint256 multiplierBps;
        uint256 epoch;
        uint256 effectiveBasisWad;
        uint128 totalYesSharesAfter;
        uint128 totalNoSharesAfter;
        uint128 payoutPoolAfter;
    }

    function createParimutuelMarket(CreateParimutuelMarketParams calldata params) external returns (bytes32 marketId);

    function createParimutuelMarket(
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint64 epochWindow
    ) external returns (bytes32 marketId);

    function createParimutuelMarketWithCollateralProfile(uint8 profileId, CreateParimutuelMarketParams calldata params)
        external
        returns (bytes32 marketId);

    function createParimutuelMarketWithCollateralProfile(
        uint8 profileId,
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint64 epochWindow
    ) external returns (bytes32 marketId);

    function buyShares(bytes32 marketId, bool isYes, uint128 amount, address receiver, uint128 minSharesOut)
        external
        returns (uint128 sharesMinted);

    function buySharesBatch(
        bytes32[] calldata marketIds,
        bool[] calldata isYes,
        uint128[] calldata amounts,
        uint128[] calldata minSharesOut,
        address receiver
    ) external returns (uint128[] memory sharesMinted);

    function claimPayout(bytes32 marketId) external returns (uint128 payout);

    function sweepParimutuelDust(bytes32 marketId) external returns (uint128 swept);

    function previewPayout(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 userWinningShares, uint256 totalWinningShares, uint256 payoutPool);

    function previewEntryFee(bytes32 marketId, uint128 amount)
        external
        view
        returns (
            uint128 totalFee,
            uint128 creatorFee,
            uint128 protocolFee,
            uint128 seniorPoolFee,
            uint128 resolverFee,
            uint128 netShares
        );

    function previewParimutuelEntry(bytes32 marketId, bool isYes, uint128 amount)
        external
        view
        returns (EntryPreview memory preview);

    function getParimutuelPool(bytes32 marketId) external view returns (PoolView memory pool);

    function getParimutuelBalances(bytes32 marketId, address user)
        external
        view
        returns (uint256 yesShares, uint256 noShares);

    function isParimutuelMarket(bytes32 marketId) external view returns (bool);

    function getParimutuelEpochWindow(bytes32 marketId) external view returns (uint64 epochWindow);

    function getEpochMultiplier(bytes32 marketId) external view returns (uint256 multiplierBps, uint256 epoch);

    function getParimutuelEpochMultipliers() external view returns (uint16[8] memory multipliersBps);
}
