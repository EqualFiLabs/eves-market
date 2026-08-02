// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IFeeRouterFacet} from "../../src/interfaces/IFeeRouterFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";

import {ResolutionHarnessFacet, SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract MarketViewsTest is SettlementFeeFixture {
    function test_GetMarketInfoConfigAndComputedIdReflectProtocolState() public {
        string memory question = "view-info";
        string memory category = "views";
        uint64 expiryTime;
        bytes32 marketId;
        ExpectedMarketData memory expected;

        (marketId, expected, expiryTime,,,) =
            _createFilledMarket(question, category, 7 days, 10_000, 500_000_000, 500, 4_200e6);

        assertEq(
            IMarketFactoryFacet(address(diamond))
                .computeMarketId(
                    question,
                    category,
                    uint64(block.timestamp),
                    expiryTime,
                    address(collateralToken),
                    LibEveMarket.MarketType.CLOB,
                    LibEveMarket.PositionTokenType.CTF
                ),
            marketId
        );

        _assertMarketInfoCore(marketId, expected);
        _assertMarketInfoAccounting(marketId);
        _assertMarketConfig();
    }

    function test_GetUserMarketPositionsReturnsBalancesAcrossMarkets() public {
        (bytes32 marketOne,,) = _createTradingMarket("positions-one", "views", 7 days);
        (bytes32 marketTwo,,) = _createTradingMarket("positions-two", "views", 8 days);

        _splitFrom(maker, marketOne, 125);
        _splitFrom(maker, marketTwo, 42);

        bytes32[] memory marketIds = new bytes32[](2);
        marketIds[0] = marketOne;
        marketIds[1] = marketTwo;

        (uint256[] memory yesBalances, uint256[] memory noBalances) =
            IMarketFactoryFacet(address(diamond)).getUserMarketPositions(maker, marketIds);

        assertEq(yesBalances.length, 2);
        assertEq(noBalances.length, 2);
        assertEq(yesBalances[0], 125);
        assertEq(noBalances[0], 125);
        assertEq(yesBalances[1], 42);
        assertEq(noBalances[1], 42);
    }

    function test_PositionViewsReadStoredPositionToken() public {
        (bytes32 marketId,,) = _createTradingMarket("typed-position-token", "views", 7 days);
        MockConditionalTokens alternatePositionToken = new MockConditionalTokens();

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        alternatePositionToken.mintPosition(maker, yesPositionId, 321);
        alternatePositionToken.mintPosition(maker, noPositionId, 123);
        ResolutionHarnessFacet(address(diamond)).setMarketPositionToken(marketId, address(alternatePositionToken));

        bytes32[] memory marketIds = new bytes32[](1);
        marketIds[0] = marketId;

        (uint256[] memory yesBalances, uint256[] memory noBalances) =
            IMarketFactoryFacet(address(diamond)).getUserMarketPositions(maker, marketIds);
        MarketFactoryTypes.MarketSummary[] memory summaries =
            IMarketFactoryFacet(address(diamond)).getMarketSummaries(maker, marketIds);

        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), 0);
        assertEq(yesBalances[0], 321);
        assertEq(noBalances[0], 123);
        assertEq(summaries[0].yesBalance, 321);
        assertEq(summaries[0].noBalance, 123);
    }

    function test_GetMarketTokenInfoReturnsGenericPositionTokenData() public {
        (bytes32 marketId, ExpectedMarketData memory expected,) = _createTradingMarket("token-info", "views", 7 days);

        MarketFactoryTypes.MarketTokenInfo memory tokenInfo =
            IMarketFactoryFacet(address(diamond)).getMarketTokenInfo(marketId);

        assertEq(tokenInfo.positionTokenType, uint8(LibEveMarket.PositionTokenType.CTF));
        assertEq(tokenInfo.positionToken, address(conditionalTokens));
        assertEq(tokenInfo.collateralToken, address(collateralToken));
        assertEq(tokenInfo.resolutionId, expected.resolutionId);
        assertEq(tokenInfo.conditionId, expected.conditionId);
        assertEq(tokenInfo.yesPositionId, expected.yesPositionId);
        assertEq(tokenInfo.noPositionId, expected.noPositionId);
    }

    function test_GetMarketSummariesHydratesMarketStateDeadlineAndBalances() public {
        string memory tradingQuestion = "summary-trading";
        string memory pendingQuestion = "summary-pending";
        (bytes32 tradingMarketId, ExpectedMarketData memory tradingExpected,) =
            _createTradingMarket(tradingQuestion, "views", 7 days);
        uint64 pendingStartTime = uint64(block.timestamp);
        (bytes32 pendingMarketId, uint64 pendingExpiryTime) = _createPendingMarket(pendingQuestion, "views", 8 days);
        bytes32 pendingQuestionId =
            LibMarketCreation.questionIdFor(pendingQuestion, "views", pendingStartTime, pendingExpiryTime);

        _splitFrom(maker, tradingMarketId, 75);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(pendingMarketId, 1);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(pendingMarketId);

        bytes32[] memory marketIds = new bytes32[](2);
        marketIds[0] = tradingMarketId;
        marketIds[1] = pendingMarketId;

        MarketFactoryTypes.MarketSummary[] memory summaries =
            IMarketFactoryFacet(address(diamond)).getMarketSummaries(maker, marketIds);

        assertEq(summaries.length, 2);

        assertEq(summaries[0].marketInfo.marketId, tradingMarketId);
        assertEq(summaries[0].marketInfo.questionId, tradingExpected.questionId);
        assertEq(summaries[0].disputeDeadline, 0);
        assertEq(summaries[0].yesBalance, 75);
        assertEq(summaries[0].noBalance, 75);

        assertEq(summaries[1].marketInfo.marketId, pendingMarketId);
        assertEq(summaries[1].marketInfo.questionId, pendingQuestionId);
        assertEq(summaries[1].disputeDeadline, disputeDeadline);
        assertEq(summaries[1].yesBalance, 0);
        assertEq(summaries[1].noBalance, 0);
    }

    function test_GetCurveInfoReturnsCurrentCurveState() public {
        (bytes32 marketId,,) = _createTradingMarket("curve-info", "views", 7 days);

        _splitFrom(maker, marketId, 250);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, false, 250, 400_000_000, 600_000_000, 240, 3);

        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);

        assertEq(info.curveId, curveId);
        assertEq(info.marketId, marketId);
        assertEq(info.maker, maker);
        assertFalse(info.isYesSide);
        assertTrue(info.active);
        assertEq(info.currentPrice, uint128(400_000_000));
        assertEq(info.remainingVolume, 250);
        assertEq(info.startPrice, uint72(400_000_000));
        assertEq(info.endPrice, uint72(600_000_000));
        assertEq(info.durationMinutes, uint24(240));
        assertEq(info.profileId, 3);
        assertEq(info.createdAt, uint64(block.timestamp));
        assertEq(info.expiresAt, uint64(block.timestamp + 240 minutes));
        assertEq(info.generation, 1);
    }

    function test_PreviewRedemptionReturnsClaimableOutcomeAmounts() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("redeem-preview", "views", 7 days);

        _splitFrom(maker, marketId, 80);
        _finalizeCreatorResolution(marketId, expiryTime, 3);

        (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewRedemption(marketId, maker);

        assertEq(yesBalance, 80);
        assertEq(noBalance, 80);
        assertEq(outcome, 3);
        assertEq(claimableAmount, 80);
    }

    function test_GetMakerMarketAccountingMatchesAccrualState() public {
        (bytes32 marketId,,) =
            _createFilledMarketWithFee("maker-accounting", "views", 7 days, 10_000, 500_000_000, 500, 4_200e6);

        (uint128 quoteVolume, uint128 accrued, uint128 claimed, uint128 claimable) =
            IFeeRouterFacet(address(diamond)).getMakerMarketAccounting(marketId, maker);
        (uint128 previewAccrued, uint128 previewClaimed, uint128 previewClaimable) =
            IFeeRouterFacet(address(diamond)).previewMakerFees(marketId, maker);
        (uint128 storedQuoteVolume, uint128 storedAccrued, uint128 storedClaimed) =
            StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);

        assertEq(quoteVolume, storedQuoteVolume);
        assertEq(accrued, storedAccrued);
        assertEq(claimed, storedClaimed);
        assertEq(claimable, storedAccrued - storedClaimed);
        assertEq(accrued, previewAccrued);
        assertEq(claimed, previewClaimed);
        assertEq(claimable, previewClaimable);
    }

    function test_GetResolutionHistoryReturnsRecordedProposalsAndCurrentDisputeState() public {
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket("resolution-history", "views", 7 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 2);

        (
            IOBRResolutionFacet.ResolutionInfo[] memory history,
            uint8 currentEscalationLevel,
            uint64 disputeDeadline,
            bool isActive
        ) = IOBRResolutionFacet(address(diamond)).getResolutionHistory(marketId);
        (,, uint8 storedEscalationLevel,,,, uint64 storedDisputeDeadline,) =
            StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        assertEq(history.length, 2);
        assertEq(currentEscalationLevel, storedEscalationLevel);
        assertEq(disputeDeadline, storedDisputeDeadline);
        assertTrue(isActive);

        _assertResolutionInfo(history[0], marketId, 0);
        _assertResolutionInfo(history[1], marketId, 1);

        expiryTime;
    }

    function _assertResolutionInfo(IOBRResolutionFacet.ResolutionInfo memory info, bytes32 marketId, uint256 index)
        internal
        view
    {
        (
            address proposer,
            uint8 proposedOutcome,
            uint8 escalationLevel,
            bool disputed,
            uint128 bondAmount,
            uint64 proposedAt,
            uint64 disputeDeadline,
            uint64 snapshotBlock
        ) = StateProbeFacet(address(diamond)).getResolutionHistoryEntry(marketId, index);

        assertEq(info.proposer, proposer);
        assertEq(info.proposedOutcome, proposedOutcome);
        assertEq(info.escalationLevel, escalationLevel);
        assertEq(info.disputed, disputed);
        assertEq(info.bondAmount, bondAmount);
        assertEq(info.proposedAt, proposedAt);
        assertEq(info.disputeDeadline, disputeDeadline);
        assertEq(info.snapshotBlock, snapshotBlock);
    }

    function _assertMarketInfoCore(bytes32 marketId, ExpectedMarketData memory expected) internal view {
        MarketFactoryTypes.MarketInfo memory info = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketId);
        (
            address storedCollateralToken,
            address storedCreator,
            bytes32 storedQuestionId,
            bytes32 storedConditionId,
            uint256 storedYesPositionId,
            uint256 storedNoPositionId
        ) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        (, uint64 createdAt, uint64 storedExpiryTime,,, uint8 outcome, uint8 state, uint256 curveCount) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(info.marketId, marketId);
        assertEq(info.marketType, uint8(LibEveMarket.MarketType.CLOB));
        assertEq(info.positionTokenType, uint8(LibEveMarket.PositionTokenType.CTF));
        assertEq(info.positionToken, address(conditionalTokens));
        assertEq(info.creator, storedCreator);
        assertEq(info.collateralToken, storedCollateralToken);
        assertEq(info.questionId, storedQuestionId);
        assertEq(info.resolutionId, expected.resolutionId);
        assertEq(info.conditionId, storedConditionId);
        assertEq(info.yesPositionId, storedYesPositionId);
        assertEq(info.noPositionId, storedNoPositionId);
        assertEq(info.questionId, expected.questionId);
        assertEq(info.conditionId, expected.conditionId);
        assertEq(info.yesPositionId, expected.yesPositionId);
        assertEq(info.noPositionId, expected.noPositionId);
        assertEq(info.createdAt, createdAt);
        assertEq(info.expiryTime, storedExpiryTime);
        assertEq(info.resolutionTime, 0);
        assertEq(info.state, state);
        assertEq(info.outcome, outcome);
        assertEq(info.creationFeePaid, StateProbeFacet(address(diamond)).marketCreationFee());
        assertEq(info.totalCurveCount, curveCount);
        assertEq(info.orderbookMakerFeeBps, 8_500);
        assertEq(info.orderbookCreatorFeeBps, 500);
        assertEq(info.orderbookProtocolFeeBps, 1_000);
        assertEq(info.orderbookVaultFeeBps, 0);
        _assertMarketInfoCreationBond(info, marketId);
    }

    function _assertMarketInfoAccounting(bytes32 marketId) internal view {
        MarketFactoryTypes.MarketInfo memory info = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketId);
        (,,, uint96 lastTradePrice,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (,, uint128 totalQuoteVolume) = StateProbeFacet(address(diamond)).getStoredMarketTrading(marketId);

        assertEq(info.totalQuoteVolume, totalQuoteVolume);
        assertEq(info.creatorFeesEscrowed, creatorFeesEscrowed);
        assertEq(info.protocolFeesAccrued, protocolFeesAccrued);
        assertEq(info.lastTradePrice, uint128(lastTradePrice));
        _assertMarketInfoCreatorStatus(info, marketId);
    }

    function _assertMarketConfig() internal view {
        MarketFactoryTypes.MarketConfigView memory config = IMarketFactoryFacet(address(diamond)).getMarketConfig();

        assertEq(config.defaultConditionalTokens, address(conditionalTokens));
        assertEq(config.collateralToken, address(collateralToken));
        assertEq(config.eveToken, address(eveToken));
        assertEq(config.eveTreasury, treasury);
        assertEq(config.stakingVault, address(0));
        assertEq(config.orderbookFeeConfig.entryFeeBps, StateProbeFacet(address(diamond)).orderbookEntryFeeBps());
        assertEq(config.orderbookFeeConfig.vaultFeeBps, 0);
        assertEq(config.marketCreationFee, StateProbeFacet(address(diamond)).marketCreationFee());
        assertEq(config.marketCreationBond, StateProbeFacet(address(diamond)).marketCreationBond());
        assertEq(config.bondToken, address(eveToken));
        assertEq(config.resolutionBondL1, uint128(0.1 ether));
        assertEq(config.resolutionBondL2, uint128(0.5 ether));
        assertEq(config.minMarketDuration, StateProbeFacet(address(diamond)).minMarketDuration());
        assertEq(config.maxMarketDuration, StateProbeFacet(address(diamond)).maxMarketDuration());
        assertEq(
            config.permissionlessCreationEnabled, StateProbeFacet(address(diamond)).permissionlessCreationEnabled()
        );
        assertEq(config.disputeWindow, 2 hours);
        assertEq(config.creatorSettleGrace, 24 hours);
        assertEq(config.openResolutionTimeout, 24 hours);
        assertEq(config.maxEscalation, 2);
    }

    function _assertMarketInfoCreationBond(MarketFactoryTypes.MarketInfo memory info, bytes32 marketId) internal view {
        (uint128 creationBond, bool creationBondReleased) =
            StateProbeFacet(address(diamond)).getStoredCreationBond(marketId);

        assertEq(info.creationBond, creationBond);
        assertEq(info.creationBondReleased, creationBondReleased);
    }

    function _assertMarketInfoCreatorStatus(MarketFactoryTypes.MarketInfo memory info, bytes32 marketId) internal view {
        (bool creatorSettledHonestly, bool creatorFeeEligible, bool creationBondReturnable) =
            StateProbeFacet(address(diamond)).getStoredCreatorStatus(marketId);

        assertEq(info.creatorSettledHonestly, creatorSettledHonestly);
        assertEq(info.creatorFeeEligible, creatorFeeEligible);
        assertEq(info.creationBondReturnable, creationBondReturnable);
    }
}
