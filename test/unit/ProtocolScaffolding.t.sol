// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IBondManagerFacet} from "../../src/interfaces/IBondManagerFacet.sol";
import {IBondTokenGateFacet} from "../../src/interfaces/IBondTokenGateFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {ICurveProfile} from "../../src/interfaces/ICurveProfile.sol";
import {IFeeRouterFacet} from "../../src/interfaces/IFeeRouterFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IVotes} from "../../src/interfaces/IVotes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";

import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

contract ProtocolScaffoldingTest is TestBase {
    function test_InterfaceSelectorsMatchSpec() public pure {
        assertEq(
            bytes4(
                keccak256(
                    "createMarket((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            ),
            bytes4(
                keccak256(
                    "createMarket((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            )
        );
        assertEq(
            bytes4(keccak256("createMarket(string,string,string,uint64,uint64,uint128,bool)")),
            bytes4(keccak256("createMarket(string,string,string,uint64,uint64,uint128,bool)"))
        );
        assertEq(
            bytes4(
                keccak256(
                    "createMarketGroup(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)),(string,string,int32,uint8))[]))"
                )
            ),
            bytes4(
                keccak256(
                    "createMarketGroup(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)),(string,string,int32,uint8))[]))"
                )
            )
        );
        assertEq(
            IMarketFactoryFacet.computeMarketId.selector,
            bytes4(keccak256("computeMarketId(string,string,uint64,uint64,address,uint8,uint8)"))
        );
        assertEq(
            IMarketFactoryFacet.computeProfileMarketId.selector,
            bytes4(keccak256("computeProfileMarketId(string,string,uint64,uint64,address,uint8,uint128,uint8,uint8)"))
        );
        assertEq(
            bytes4(
                keccak256(
                    "createMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            ),
            bytes4(
                keccak256(
                    "createMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            )
        );
        assertEq(
            bytes4(
                keccak256("createMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint128,bool)")
            ),
            bytes4(
                    keccak256(
                        "createMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint128,bool)"
                    )
                )
        );
        assertEq(
            IMarketFactoryFacet.createMarketGroupFromExisting.selector,
            bytes4(
                keccak256(
                    "createMarketGroupFromExisting(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),(bytes32,(string,string,int32,uint8))[]))"
                )
            )
        );
        assertEq(
            IMarketFactoryFacet.addMarketsToGroup.selector,
            bytes4(keccak256("addMarketsToGroup(bytes32,(bytes32,(string,string,int32,uint8))[])"))
        );
        assertEq(IMarketFactoryFacet.getMarketTokenInfo.selector, bytes4(keccak256("getMarketTokenInfo(bytes32)")));
        assertEq(IMarketFactoryFacet.getCollateralProfile.selector, bytes4(keccak256("getCollateralProfile(uint8)")));
        assertEq(
            IMarketFactoryFacet.getCollateralProfileParimutuelConfig.selector,
            bytes4(keccak256("getCollateralProfileParimutuelConfig(uint8)"))
        );
        assertEq(
            IMarketFactoryFacet.getCollateralProfileParlayUnderwritingFee.selector,
            bytes4(keccak256("getCollateralProfileParlayUnderwritingFee(uint8)"))
        );
        assertEq(IMarketFactoryFacet.getMarketMetadata.selector, bytes4(keccak256("getMarketMetadata(bytes32)")));
        assertEq(
            IMarketFactoryFacet.getPositionMetadata.selector, bytes4(keccak256("getPositionMetadata(address,uint256)"))
        );
        assertEq(IMarketFactoryFacet.positionTokenURI.selector, bytes4(keccak256("positionTokenURI(address,uint256)")));
        assertEq(
            ICurveLifecycleFacet.postCurve.selector,
            bytes4(keccak256("postCurve(bytes32,bool,uint128,uint72,uint72,uint24,uint8,uint8)"))
        );
        assertEq(
            ICurveLifecycleFacet.postCurvesMultiMarket.selector,
            bytes4(
                keccak256("postCurvesMultiMarket((bytes32,uint8,(bool,uint128,uint72,uint72,uint24,uint8,uint8)[])[])")
            )
        );
        assertEq(
            ICurveLifecycleFacet.postBidCurvesMultiMarket.selector,
            bytes4(
                keccak256(
                    "postBidCurvesMultiMarket((bytes32,uint8,(bool,uint128,uint72,uint72,uint24,uint8,uint8)[])[])"
                )
            )
        );
        assertEq(
            ICurveTradeFacet.fillBest.selector,
            bytes4(
                keccak256(
                    "fillBest((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))"
                )
            )
        );
        assertEq(
            ICurveLifecycleFacet.updateCurveFromNow.selector,
            bytes4(keccak256("updateCurveFromNow(uint256,uint256,uint32)"))
        );
        assertEq(
            ICurveLifecycleFacet.updateCurvesFromNowBatch.selector,
            bytes4(keccak256("updateCurvesFromNowBatch((uint256,uint256,uint32)[])"))
        );
        assertEq(IOBRResolutionFacet.settleMarket.selector, bytes4(keccak256("settleMarket(bytes32,uint8)")));
        assertEq(IOBRResolutionFacet.settleMarketEarly.selector, bytes4(keccak256("settleMarketEarly(bytes32,uint8)")));
        assertEq(IOBRResolutionFacet.openResolution.selector, bytes4(keccak256("openResolution(bytes32,uint8)")));
        assertEq(IOBRResolutionFacet.disputeResolution.selector, bytes4(keccak256("disputeResolution(bytes32,uint8)")));
        assertEq(
            IMarketSettlementFacet.getCTFRedemptionParams.selector, bytes4(keccak256("getCTFRedemptionParams(bytes32)"))
        );
        assertEq(
            IMarketSettlementFacet.previewCTFRedemption.selector,
            bytes4(keccak256("previewCTFRedemption(bytes32,address)"))
        );
        assertEq(
            IMarketSettlementFacet.previewParimutuelPayout.selector,
            bytes4(keccak256("previewParimutuelPayout(bytes32,address)"))
        );
        assertEq(IFeeRouterFacet.previewMakerFees.selector, bytes4(keccak256("previewMakerFees(bytes32,address)")));
        assertEq(
            IFeeRouterFacet.configureMarketMakerRewards.selector,
            bytes4(keccak256("configureMarketMakerRewards(bytes32,uint16)"))
        );
        assertEq(
            IFeeRouterFacet.fundMarketMakerRewards.selector,
            bytes4(keccak256("fundMarketMakerRewards(bytes32,uint128)"))
        );
        assertEq(
            IFeeRouterFacet.claimMarketMakerRewards.selector, bytes4(keccak256("claimMarketMakerRewards(bytes32)"))
        );
        assertEq(
            IFeeRouterFacet.previewMarketMakerRewards.selector,
            bytes4(keccak256("previewMarketMakerRewards(bytes32,address)"))
        );
        assertEq(IBondManagerFacet.returnBond.selector, bytes4(keccak256("returnBond(bytes32,uint256)")));
        assertEq(IBondManagerFacet.routeBond.selector, bytes4(keccak256("routeBond(address,uint128)")));
        assertEq(
            IBondTokenGateFacet.lockResolutionBond.selector, bytes4(keccak256("lockResolutionBond(address,uint8)"))
        );
        assertEq(
            ICurveProfile.computePrice.selector,
            bytes4(keccak256("computePrice(uint128,uint128,uint64,uint64,uint64,bytes32)"))
        );
        assertEq(IVotes.getPastVotes.selector, bytes4(keccak256("getPastVotes(address,uint256)")));
    }

    function test_ErrorSelectorsRemainStable() public pure {
        bytes4[] memory selectors = new bytes4[](37);
        selectors[0] = Errors.InsufficientCreationFeeOrReserve.selector;
        selectors[1] = Errors.InsufficientCreationBond.selector;
        selectors[2] = Errors.InsufficientInitialLiquidityCollateral.selector;
        selectors[3] = Errors.ExpiryTooSoon.selector;
        selectors[4] = Errors.ExpiryTooLate.selector;
        selectors[5] = Errors.MarketAlreadyExists.selector;
        selectors[6] = Errors.CTFConditionPreparationFailed.selector;
        selectors[7] = Errors.PermissionlessCreationDisabled.selector;
        selectors[8] = Errors.MarketNotTrading.selector;
        selectors[9] = Errors.InsufficientMakerEscrow.selector;
        selectors[10] = Errors.GenerationMismatch.selector;
        selectors[11] = Errors.CommitmentMismatch.selector;
        selectors[12] = Errors.SlippageExceeded.selector;
        selectors[13] = Errors.NotCurveOwner.selector;
        selectors[14] = Errors.CurveNotActive.selector;
        selectors[15] = Errors.CurveExpired.selector;
        selectors[16] = Errors.InvalidProfileId.selector;
        selectors[17] = Errors.InsufficientVolume.selector;
        selectors[18] = Errors.PositionIdMismatch.selector;
        selectors[19] = Errors.MarketNotPending.selector;
        selectors[20] = Errors.NotMarketCreator.selector;
        selectors[21] = Errors.InvalidOutcome.selector;
        selectors[22] = Errors.MarketNotExpired.selector;
        selectors[23] = Errors.MarketAlreadyResolved.selector;
        selectors[24] = Errors.DisputeWindowClosed.selector;
        selectors[25] = Errors.SameOutcome.selector;
        selectors[26] = Errors.InsufficientDisputeBond.selector;
        selectors[27] = Errors.InsufficientEveBond.selector;
        selectors[28] = Errors.ResolutionNotReady.selector;
        selectors[29] = Errors.CreatorGraceActive.selector;
        selectors[30] = Errors.MarketNotResolved.selector;
        selectors[31] = Errors.PayoutsAlreadyReported.selector;
        selectors[32] = Errors.InvalidRedemptionParams.selector;
        selectors[33] = Errors.CreatorNotEligible.selector;
        selectors[34] = Errors.AlreadyClaimed.selector;
        selectors[35] = Errors.MetadataFieldTooLong.selector;
        selectors[36] = Errors.InvalidContractInterface.selector;

        assertEq(selectors.length, 37);
        assertEq(
            Errors.InsufficientInitialLiquidityCollateral.selector,
            bytes4(keccak256("InsufficientInitialLiquidityCollateral()"))
        );
        assertEq(Errors.InsufficientCreationBond.selector, bytes4(keccak256("InsufficientCreationBond()")));
        assertEq(
            Errors.CTFConditionPreparationFailed.selector, bytes4(keccak256("CTFConditionPreparationFailed(bytes32)"))
        );
        assertEq(
            Errors.PermissionlessCreationDisabled.selector, bytes4(keccak256("PermissionlessCreationDisabled(address)"))
        );
        assertEq(Errors.PositionIdMismatch.selector, bytes4(keccak256("PositionIdMismatch(uint256,uint256)")));
        assertEq(Errors.PayoutsAlreadyReported.selector, bytes4(keccak256("PayoutsAlreadyReported(bytes32)")));
        assertEq(
            Errors.MetadataFieldTooLong.selector, bytes4(keccak256("MetadataFieldTooLong(string,uint256,uint256)"))
        );
    }

    function test_MockConditionalTokensSupportsSplitMergeAndRedeem() public {
        bytes32 questionId = keccak256("fixture-market");
        uint256[] memory partition = new uint256[](2);
        uint256[] memory payouts = new uint256[](2);
        uint256[] memory redemptionSets = new uint256[](1);

        partition[0] = 1;
        partition[1] = 2;
        payouts[0] = 1;
        payouts[1] = 0;
        redemptionSets[0] = 1;

        conditionalTokens.prepareCondition(address(this), questionId, 2);

        bytes32 conditionId = conditionalTokens.getConditionId(address(this), questionId, 2);
        bytes32 yesCollectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, 1);
        bytes32 noCollectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, 2);
        uint256 yesPositionId = conditionalTokens.getPositionId(IERC20(address(usdc)), yesCollectionId);
        uint256 noPositionId = conditionalTokens.getPositionId(IERC20(address(usdc)), noCollectionId);

        usdc.mint(address(this), 200e6);
        usdc.approve(address(conditionalTokens), type(uint256).max);

        conditionalTokens.splitPosition(IERC20(address(usdc)), bytes32(0), conditionId, partition, 75e6);

        assertEq(conditionalTokens.balanceOf(address(this), yesPositionId), 75e6);
        assertEq(conditionalTokens.balanceOf(address(this), noPositionId), 75e6);
        assertEq(usdc.balanceOf(address(conditionalTokens)), 75e6);

        conditionalTokens.mergePositions(IERC20(address(usdc)), bytes32(0), conditionId, partition, 25e6);

        assertEq(conditionalTokens.balanceOf(address(this), yesPositionId), 50e6);
        assertEq(conditionalTokens.balanceOf(address(this), noPositionId), 50e6);
        assertEq(usdc.balanceOf(address(this)), 150e6);

        conditionalTokens.reportPayouts(questionId, payouts);

        uint256 beforeBalance = usdc.balanceOf(address(this));
        conditionalTokens.redeemPositions(IERC20(address(usdc)), bytes32(0), conditionId, redemptionSets);

        assertEq(usdc.balanceOf(address(this)) - beforeBalance, 50e6);
        assertEq(conditionalTokens.balanceOf(address(this), yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(address(this), noPositionId), 50e6);
    }

    function test_MockTokensAndProfileExposeExpectedBehavior() public {
        address alice = makeAddr("alice");

        assertEq(usdc.decimals(), 6);

        eveToken.mint(alice, 10e18);
        assertEq(eveToken.balanceOf(alice), 10e18);

        curveProfile.setFixedPrice(777);
        assertEq(curveProfile.computePrice(100, 900, 10, 90, 55, bytes32(0)), 777);

        curveProfile.clearFixedPrice();
        assertEq(curveProfile.computePrice(100, 900, 10, 80, 50, bytes32(0)), 500);
    }

    function test_TestBaseWiresMockDiamondAndFixtures() public {
        (address configuredConditionalTokens, address collateralToken, address eve, address eveTreasury) =
            ITestStateFacet(address(diamond)).getConfigAddresses();

        assertEq(configuredConditionalTokens, address(conditionalTokens));
        assertEq(collateralToken, address(usdc));
        assertEq(eve, address(eveToken));
        assertEq(eveTreasury, treasury);
        assertEq(diamond.facetForSelector(ITestStateFacet.createMarketFixture.selector), address(stateFacet));

        string memory question = "Will ETH close above 3k?";
        uint64 expiryTime = uint64(block.timestamp + 2 days);
        bytes32 expectedMarketId = _marketIdFor(question, expiryTime);
        bytes32 expectedQuestionId =
            LibMarketCreation.questionIdFor(question, DEFAULT_CATEGORY, uint64(block.timestamp), expiryTime);
        bytes32 expectedResolutionId = LibMarketCreation.resolutionIdFor(expectedMarketId);
        bytes32 expectedConditionId = conditionalTokens.getConditionId(address(diamond), expectedResolutionId, 2);
        bytes32 yesCollectionId = conditionalTokens.getCollectionId(bytes32(0), expectedConditionId, 1);
        bytes32 noCollectionId = conditionalTokens.getCollectionId(bytes32(0), expectedConditionId, 2);
        uint256 expectedYesPositionId = conditionalTokens.getPositionId(IERC20(address(usdc)), yesCollectionId);
        uint256 expectedNoPositionId = conditionalTokens.getPositionId(IERC20(address(usdc)), noCollectionId);

        (bytes32 marketId, bytes32 conditionId) = _createMarketFixture(question, expiryTime);
        assertEq(marketId, expectedMarketId);
        assertEq(conditionId, expectedConditionId);

        (address oracle, bytes32 storedQuestionId,,,,) = conditionalTokens.getConditionDetails(conditionId);
        assertEq(oracle, address(diamond));
        assertEq(storedQuestionId, expectedResolutionId);

        uint256 curveId = _postCurveFixture(marketId, true, 100e6, 400_000_000, 600_000_000, 180, 0);
        _fillCurveFixture(curveId, 40e6, 25e6, 2e6);
        _resolveMarketFixture(marketId, 1);

        _assertStoredMarketCore(marketId, expectedQuestionId, conditionId, expectedYesPositionId, expectedNoPositionId);
        _assertStoredMarketAccounting(marketId, 2e6, 40e6, 1, uint8(LibEveMarket.MarketState.Resolved));
        _assertStoredCurve(curveId, marketId, 75e6, 1, true, true, maker);

        uint256[] memory reportedPayouts = conditionalTokens.getPayoutNumerators(conditionId);
        assertEq(reportedPayouts[0], 1);
        assertEq(reportedPayouts[1], 0);
    }

    function test_TestBaseWiresParimutuelFixtures() public {
        (address configuredShareToken, uint16 entryFeeBps, uint128 minEntry) =
            ITestStateFacet(address(diamond)).getParimutuelConfigFixture();
        assertEq(configuredShareToken, address(parimutuelShareToken));
        assertEq(entryFeeBps, DEFAULT_PARIMUTUEL_ENTRY_FEE_BPS);
        assertEq(minEntry, DEFAULT_PARIMUTUEL_MIN_ENTRY);

        string memory question = "Will parimutuel fixtures work?";
        uint64 expiryTime = uint64(block.timestamp + 2 days);
        bytes32 expectedMarketId = _parimutuelMarketIdFor(question, expiryTime);
        bytes32 expectedConditionId = bytes32(0);
        uint256 expectedYesPositionId = LibMarketCreation.parimutuelPositionId(address(diamond), expectedMarketId, 1);
        uint256 expectedNoPositionId = LibMarketCreation.parimutuelPositionId(address(diamond), expectedMarketId, 2);

        (bytes32 marketId, bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) =
            _createParimutuelMarketFixture(question, expiryTime);

        assertEq(marketId, expectedMarketId);
        assertEq(conditionId, expectedConditionId);
        assertEq(yesPositionId, expectedYesPositionId);
        assertEq(noPositionId, expectedNoPositionId);

        (uint8 marketType, address positionToken) =
            ITestStateFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);
        assertEq(marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(positionToken, address(parimutuelShareToken));

        _assertParimutuelFixtureLifecycle(marketId, conditionId, yesPositionId);
    }

    function _assertParimutuelFixtureLifecycle(bytes32 marketId, bytes32 conditionId, uint256 yesPositionId) internal {
        uint128 sharesMinted = _buySharesFixture(taker, marketId, true, 1_000e6);
        assertEq(sharesMinted, 975e6);
        assertEq(parimutuelShareToken.balanceOf(taker, yesPositionId), sharesMinted);

        (
            uint128 totalYesShares,
            uint128 totalNoShares,
            uint128 payoutPool,
            uint128 claimedPayout,
            uint128 claimedClaimableShares,
            bool dustSwept
        ) = ITestStateFacet(address(diamond)).getStoredParimutuelPoolFixture(marketId);
        assertEq(totalYesShares, sharesMinted);
        assertEq(totalNoShares, 0);
        assertEq(payoutPool, sharesMinted);
        assertEq(claimedPayout, 0);
        assertEq(claimedClaimableShares, 0);
        assertFalse(dustSwept);

        assertEq(conditionId, bytes32(0));

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.ResolutionFinalized(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        _resolveParimutuelMarketFixture(marketId, uint8(LibEveMarket.MarketOutcome.Yes));

        assertEq(conditionId, bytes32(0));
        _assertStoredMarketAccounting(marketId, 25e6, 1_000e6, 1, uint8(LibEveMarket.MarketState.Resolved));
    }

    function _assertConditionUnreported(bytes32 conditionId) internal view {
        (,,, bool prepared, bool reported, uint256 payoutDenominator) =
            conditionalTokens.getConditionDetails(conditionId);
        assertTrue(prepared);
        assertFalse(reported);
        assertEq(payoutDenominator, 0);
    }

    function test_EventFixturesEmitResolutionAndRoutingEvents() public {
        bytes32 marketId = keccak256("event-fixtures");

        vm.expectEmit(true, true, false, true, address(diamond));
        emit Events.TradeRouted(marketId, taker, true, 100e6, 40e6, 500_000_000, 2);
        ITestStateFacet(address(diamond)).routeTradeFixture(marketId, taker, true, 100e6, 40e6, 500_000_000, 2);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit Events.OpenResolutionStarted(marketId, disputer, 2);
        ITestStateFacet(address(diamond)).openResolutionFixture(marketId, disputer, 2);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.PayoutReported(marketId, 3, keccak256(abi.encode(_invalidPayoutVector())));
        ITestStateFacet(address(diamond))
            .payoutReportedFixture(marketId, 3, keccak256(abi.encode(_invalidPayoutVector())));
    }

    function _invalidPayoutVector() internal pure returns (uint256[] memory payouts) {
        payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 1;
    }

    function _assertStoredMarketCore(
        bytes32 marketId,
        bytes32 expectedQuestionId,
        bytes32 expectedConditionId,
        uint256 expectedYesPositionId,
        uint256 expectedNoPositionId
    ) internal view {
        (
            address storedCollateralToken,
            address storedCreator,
            bytes32 questionId,
            bytes32 storedConditionId,
            uint256 yesPositionId,
            uint256 noPositionId
        ) = ITestStateFacet(address(diamond)).getStoredMarketCore(marketId);

        assertEq(storedCollateralToken, address(usdc));
        assertEq(storedCreator, creator);
        assertEq(questionId, expectedQuestionId);
        assertEq(storedConditionId, expectedConditionId);
        assertEq(yesPositionId, expectedYesPositionId);
        assertEq(noPositionId, expectedNoPositionId);
    }

    function _assertStoredMarketAccounting(
        bytes32 marketId,
        uint128 expectedTotalFeePool,
        uint128 expectedTotalQuoteVolume,
        uint8 expectedOutcome,
        uint8 expectedState
    ) internal view {
        (uint128 totalFeePool, uint128 totalQuoteVolume, uint8 outcome, uint8 state) =
            ITestStateFacet(address(diamond)).getStoredMarketAccounting(marketId);

        assertEq(totalFeePool, expectedTotalFeePool);
        assertEq(totalQuoteVolume, expectedTotalQuoteVolume);
        assertEq(outcome, expectedOutcome);
        assertEq(state, expectedState);
    }

    function _assertStoredCurve(
        uint256 curveId,
        bytes32 expectedMarketId,
        uint128 expectedRemainingVolume,
        uint32 expectedGeneration,
        bool expectedActive,
        bool expectedIsYesSide,
        address expectedMaker
    ) internal view {
        (
            uint128 remainingVolume,
            uint32 generation,
            bool active,
            bool isYesSide,
            address storedMaker,
            bytes32 parentMarketId
        ) = ITestStateFacet(address(diamond)).getStoredCurveState(curveId);

        uint256 packed = ITestStateFacet(address(diamond)).getStoredCurvePacked(curveId);

        assertEq(remainingVolume, expectedRemainingVolume);
        assertEq(generation, expectedGeneration);
        assertEq(active, expectedActive);
        assertEq(isYesSide, expectedIsYesSide);
        assertEq(storedMaker, expectedMaker);
        assertEq(parentMarketId, expectedMarketId);
        assertTrue(packed != 0);
    }
}
