// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ParlayTypes} from "../types/ParlayTypes.sol";

interface IParlayFacet {
    function setParlayConfig(
        address ticketToken,
        address feeRecipient,
        uint128 underwritingFee,
        uint16 vaultFeeBps,
        uint16 feeRecipientBps
    ) external;

    function getParlayConfig() external view returns (ParlayTypes.ParlayConfigView memory configView);

    function postParlayOffer(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy,
        string calldata metadataHint,
        uint128 premiumPerUnit,
        uint128 maxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) external returns (uint256 offerId);

    function postParlayOfferWithCollateralProfile(uint8 collateralProfileId, ParlayTypes.QuoteOfferPost calldata post)
        external
        returns (uint256 offerId);

    function postParlayOfferFromBudget(uint256 budgetId, ParlayTypes.BudgetOfferPost calldata post)
        external
        returns (uint256 offerId);

    function postParlayOfferFromBudgetWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetOfferPost calldata post
    ) external returns (uint256 offerId);

    function postParlayOffersFromBudgetBatch(uint256 budgetId, ParlayTypes.BudgetOfferPost[] calldata posts)
        external
        returns (uint256[] memory offerIds);

    function postParlayOffersFromBudgetBatchWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetOfferPost[] calldata posts
    ) external returns (uint256[] memory offerIds);

    function fillParlayOffer(uint256 offerId, uint128 units, address receiver) external returns (uint256 ticketId);

    function postParlayRequest(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy,
        string calldata metadataHint,
        uint128 premiumPerUnit,
        uint128 desiredMaxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) external returns (uint256 requestId);

    function postParlayRequestWithCollateralProfile(
        uint8 collateralProfileId,
        ParlayTypes.QuoteRequestPost calldata post
    ) external returns (uint256 requestId);

    function postParlayRequestFromBudget(uint256 budgetId, ParlayTypes.BudgetRequestPost calldata post)
        external
        returns (uint256 requestId);

    function postParlayRequestFromBudgetWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetRequestPost calldata post
    ) external returns (uint256 requestId);

    function postParlayRequestsFromBudgetBatch(uint256 budgetId, ParlayTypes.BudgetRequestPost[] calldata posts)
        external
        returns (uint256[] memory requestIds);

    function postParlayRequestsFromBudgetBatchWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetRequestPost[] calldata posts
    ) external returns (uint256[] memory requestIds);

    function fillParlayRequest(uint256 requestId, uint128 units, address ticketReceiver)
        external
        returns (uint256 ticketId);

    function cancelParlayOffer(uint256 offerId) external returns (uint256 escrowReturned);

    function cancelParlayRequest(uint256 requestId) external returns (uint256 premiumReturned, uint256 feeReturned);

    function createParlayBudget(ParlayTypes.BudgetMode mode, uint256 amount) external returns (uint256 budgetId);

    function createParlayBudgetWithCollateralProfile(
        uint8 collateralProfileId,
        ParlayTypes.BudgetMode mode,
        uint256 amount
    ) external returns (uint256 budgetId);

    function fundParlayBudget(uint256 budgetId, uint256 amount) external;

    function cancelParlayBudget(uint256 budgetId) external returns (uint256 refunded);

    function getParlayBudget(uint256 budgetId) external view returns (ParlayTypes.SharedBudgetView memory budgetView);

    function finalizeParlayTicketBucket(uint256 ticketId) external returns (uint128 payoutPerUnit);

    function claimParlayTicket(uint256 ticketId, uint128 units, address receiver) external returns (uint256 payout);

    function createParlayTicketBook(uint256 ticketId, uint8 tickPresetId, bytes32 salt)
        external
        returns (bytes32 bookId);

    function emitStrategyCreated(
        bytes32 strategyId,
        bytes32[] calldata directMarketIds,
        uint8[] calldata directOutcomes,
        uint256[] calldata parlayTemplateIds,
        string calldata metadataHint
    ) external;

    function computeParlayTemplateId(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy
    ) external view returns (uint256 templateId);

    function computeParlayTicketId(
        uint256 templateId,
        ParlayTypes.SourceType sourceType,
        uint256 sourceId,
        address underwriter,
        uint128 maxPayoutPerUnit
    ) external pure returns (uint256 ticketId);

    function getParlayTemplate(uint256 templateId)
        external
        view
        returns (ParlayTypes.ParlayTemplateView memory templateView);

    function getParlayTemplateLeg(uint256 templateId, uint256 index)
        external
        view
        returns (ParlayTypes.ParlayLeg memory leg);

    function getParlayTemplatePayoutTier(uint256 templateId, uint256 index)
        external
        view
        returns (ParlayTypes.PayoutTier memory tier);

    function getParlayOffer(uint256 offerId) external view returns (ParlayTypes.ParlayOfferView memory offerView);

    function getParlayRequest(uint256 requestId)
        external
        view
        returns (ParlayTypes.ParlayRequestView memory requestView);

    function getParlayTicketBucket(uint256 ticketId)
        external
        view
        returns (ParlayTypes.ParlayTicketBucketView memory bucketView);

    function parlayTicketURI(address ticketToken, uint256 ticketId) external view returns (string memory uri);

    function multicall(bytes[] calldata calls) external returns (bytes[] memory results);
}
