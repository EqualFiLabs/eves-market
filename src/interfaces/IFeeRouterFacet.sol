// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IFeeRouterFacet {
    function claimCreatorFees(bytes32 marketId) external;

    function claimMakerFees(bytes32 marketId) external;

    function configureMarketMakerRewards(bytes32 marketId, uint16 rewardRateBps) external;

    function fundMarketMakerRewards(bytes32 marketId, uint128 amount) external;

    function claimMarketMakerRewards(bytes32 marketId) external;

    function claimBookCreatorFees(bytes32 bookId) external;

    function claimBookMakerFees(bytes32 bookId) external;

    function previewMakerFees(bytes32 marketId, address maker)
        external
        view
        returns (uint128 accrued, uint128 claimed, uint128 claimable);

    function getMakerMarketAccounting(bytes32 marketId, address maker)
        external
        view
        returns (uint128 quoteVolume, uint128 accrued, uint128 claimed, uint128 claimable);

    function previewMarketMakerRewards(bytes32 marketId, address maker)
        external
        view
        returns (address rewardToken, uint16 rewardRateBps, uint128 rewardsRemaining, uint128 claimable);

    function previewBookMakerFees(bytes32 bookId, address maker)
        external
        view
        returns (uint128 accrued, uint128 claimed, uint128 claimable);

    function getMakerBookAccounting(bytes32 bookId, address maker)
        external
        view
        returns (uint128 quoteVolume, uint128 accrued, uint128 claimed, uint128 claimable);
}
