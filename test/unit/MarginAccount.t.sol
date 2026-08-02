// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EveUSDC} from "../../src/EveUSDC.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {MarkOracleFacet} from "../../src/facets/MarkOracleFacet.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarkOracleFacet} from "../../src/interfaces/IMarkOracleFacet.sol";
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MarkOracleTypes} from "../../src/types/MarkOracleTypes.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {TestBase} from "../helpers/TestBase.sol";

contract MarginAccountTest is TestBase {
    uint72 internal constant TWO_USDC = 2e18;
    bytes32 internal constant SPOT_SALT = keccak256("margin-spot-book");

    EveUSDC internal eveUSDC;
    MockUSDC internal spotToken;
    address internal riskManager;

    function setUp() public override {
        super.setUp();

        riskManager = makeAddr("riskManager");
        eveUSDC = new EveUSDC(address(usdc), makeAddr("onramp"), makeAddr("offramp"));
        spotToken = new MockUSDC();
        spotToken.mint(maker, 1_000_000e6);
        spotToken.mint(taker, 1_000_000e6);

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(eveUSDC));
        IMarginAccountFacet(address(diamond)).setMarginRiskManager(riskManager);
        vm.stopPrank();
    }

    function test_DepositWithdrawAllocateAndReleaseMargin() public {
        _wrapEveUSDC(maker, 100e6);

        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), 100e18);
        uint256 credited = IMarginAccountFacet(address(diamond)).depositMargin(100e18, maker);
        IMarginAccountFacet(address(diamond)).withdrawMargin(20e18, taker);
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);
        bytes32 bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomainId, 50e18);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 10e18);
        vm.stopPrank();

        MarginTypes.MarginAccount memory account = IMarginAccountFacet(address(diamond)).getMarginAccount(maker);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);

        assertEq(credited, 100e18);
        assertEq(account.depositedMargin, 100e18);
        assertEq(account.withdrawnMargin, 20e18);
        assertEq(account.freeMargin, 40e18);
        assertEq(account.allocatedMargin, 40e18);
        assertEq(bucket.operator, maker);
        assertEq(bucket.riskDomainId, riskDomainId);
        assertEq(uint8(bucket.kind), uint8(MarginTypes.BucketKind.MLO));
        assertEq(bucket.marginAllocated, 40e18);
        assertEq(eveUSDC.balanceOf(taker), 20e18);
        assertEq(eveUSDC.balanceOf(address(diamond)), 80e18);
    }

    function test_ExplicitBucketKindAndGenericRiskSummary() public {
        _wrapEveUSDC(maker, 100e6);

        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(keccak256("prediction-margin"));
        bytes32 bucketId;
        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), 100e18);
        IMarginAccountFacet(address(diamond)).depositMargin(100e18, maker);
        bucketId = IMarginAccountFacet(address(diamond))
            .allocateBucketMarginWithKind(riskDomainId, 100e18, MarginTypes.BucketKind.PredictionTrader);
        vm.stopPrank();

        vm.startPrank(riskManager);
        IMarginAccountFacet(address(diamond)).increaseOpenOrderRisk(bucketId, 20e18);
        IMarginAccountFacet(address(diamond)).moveOpenOrderToPositionRisk(bucketId, 15e18);
        IMarginAccountFacet(address(diamond)).recordBucketDebt(bucketId, 10e18);
        IMarginAccountFacet(address(diamond)).accrueBucketFunding(bucketId, 3e18);
        IMarginAccountFacet(address(diamond)).recordBucketUnrealizedPnl(bucketId, 50e18, 2e18);
        IMarginAccountFacet(address(diamond)).recordBucketRecoveryPnl(bucketId, 7e18, 4e18);
        IMarginAccountFacet(address(diamond)).recordBucketBadDebt(bucketId, 1e18);
        vm.stopPrank();

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        MarginTypes.BucketRisk memory risk = IMarginAccountFacet(address(diamond)).getBucketRisk(bucketId);

        assertEq(uint8(bucket.kind), uint8(MarginTypes.BucketKind.PredictionTrader));
        assertEq(bucket.openOrderRisk, 5e18);
        assertEq(bucket.positionRisk, 15e18);
        assertEq(bucket.reservedRisk, bucket.openOrderRisk);
        assertEq(bucket.activeRisk, bucket.positionRisk);
        assertEq(risk.openOrderRisk, 5e18);
        assertEq(risk.positionRisk, 15e18);
        assertEq(risk.vaultDebt, 10e18);
        assertEq(risk.fundingLiability, 3e18);
        assertEq(risk.unrealizedProfits, 50e18);
        assertEq(risk.unrealizedLosses, 2e18);
        assertEq(risk.recoveryProfits, 7e18);
        assertEq(risk.recoveryLosses, 4e18);
        assertEq(risk.badDebt, 1e18);
        assertEq(risk.lockedRisk, 40e18);
        assertEq(IMarginAccountFacet(address(diamond)).bucketLockedRisk(bucketId), 40e18);
    }

    function test_ReleaseIsBlockedByReservedAndActiveRisk() public {
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.startPrank(riskManager);
        IMarginAccountFacet(address(diamond)).reserveBucketRisk(bucketId, 60e18);
        IMarginAccountFacet(address(diamond)).activateReservedBucketRisk(bucketId, 40e18);
        vm.stopPrank();

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(IMarginAccountFacet.BucketBelowInitialMargin.selector, bucketId, 59e18, 60e18)
        );
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 41e18);

        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 40e18);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.marginAllocated, 60e18);
        assertEq(bucket.reservedRisk, 20e18);
        assertEq(bucket.activeRisk, 40e18);
        assertEq(bucket.openOrderRisk, 20e18);
        assertEq(bucket.positionRisk, 40e18);
    }

    function test_GenericLiabilitiesBlockReleaseButUnrealizedProfitDoesNotUnlockMargin() public {
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.startPrank(riskManager);
        IMarginAccountFacet(address(diamond)).recordBucketDebt(bucketId, 30e18);
        IMarginAccountFacet(address(diamond)).accrueBucketFunding(bucketId, 10e18);
        IMarginAccountFacet(address(diamond)).recordBucketUnrealizedPnl(bucketId, 1_000e18, 20e18);
        IMarginAccountFacet(address(diamond)).recordBucketRecoveryPnl(bucketId, 1_000e18, 5e18);
        IMarginAccountFacet(address(diamond)).recordBucketBadDebt(bucketId, 5e18);
        vm.stopPrank();

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(IMarginAccountFacet.BucketBelowInitialMargin.selector, bucketId, 29e18, 30e18)
        );
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 31e18);

        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 30e18);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.marginAllocated, 70e18);
        assertEq(IMarginAccountFacet(address(diamond)).bucketLockedRisk(bucketId), 70e18);
    }

    function test_RiskParamsAllowLeverageAndHealthReportsMarginStatus() public {
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.prank(owner);
        IMarginAccountFacet(address(diamond)).setRiskDomainRiskParams(riskDomainId, 2_000, 1_000);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).increaseOpenOrderRisk(bucketId, 500e18);

        MarginTypes.BucketHealth memory health = IMarginAccountFacet(address(diamond)).bucketHealth(bucketId);
        MarginTypes.RiskParams memory params = IMarginAccountFacet(address(diamond)).riskParamsForBucket(bucketId);

        assertEq(params.initialMarginBps, 2_000);
        assertEq(params.maintenanceMarginBps, 1_000);
        assertEq(health.marginEquity, 100e18);
        assertEq(health.exposure, 500e18);
        assertEq(health.initialRequirement, 100e18);
        assertEq(health.maintenanceRequirement, 50e18);
        assertEq(uint8(health.status), uint8(MarginTypes.BucketHealthStatus.Healthy));

        vm.prank(riskManager);
        vm.expectRevert(
            abi.encodeWithSelector(IMarginAccountFacet.BucketBelowInitialMargin.selector, bucketId, 100e18, 101e18)
        );
        IMarginAccountFacet(address(diamond)).increaseOpenOrderRisk(bucketId, 5e18);
    }

    function test_LiabilitiesCanPushBucketBelowMaintenanceWithoutUnlockingProfit() public {
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.prank(owner);
        IMarginAccountFacet(address(diamond)).setRiskDomainRiskParams(riskDomainId, 2_000, 1_000);

        vm.startPrank(riskManager);
        IMarginAccountFacet(address(diamond)).increaseOpenOrderRisk(bucketId, 500e18);
        IMarginAccountFacet(address(diamond)).recordBucketUnrealizedPnl(bucketId, 1_000e18, 60e18);
        vm.stopPrank();

        MarginTypes.BucketHealth memory health = IMarginAccountFacet(address(diamond)).bucketHealth(bucketId);
        assertEq(health.marginEquity, 40e18);
        assertEq(health.initialRequirement, 100e18);
        assertEq(health.maintenanceRequirement, 50e18);
        assertEq(uint8(health.status), uint8(MarginTypes.BucketHealthStatus.BelowMaintenance));
        assertFalse(IMarginAccountFacet(address(diamond)).canBucketIncreaseRisk(bucketId));

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(IMarginAccountFacet.BucketBelowInitialMargin.selector, bucketId, 39e18, 100e18)
        );
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 1e18);
    }

    function test_DefaultRiskParamsCanBeSetAndDomainOverrideCanBeCleared() public {
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.startPrank(owner);
        IMarginAccountFacet(address(diamond)).setDefaultRiskParams(MarginTypes.BucketKind.MLO, 3_000, 2_000);
        IMarginAccountFacet(address(diamond)).setRiskDomainRiskParams(riskDomainId, 2_500, 1_500);
        vm.stopPrank();

        MarginTypes.RiskParams memory params = IMarginAccountFacet(address(diamond)).riskParamsForBucket(bucketId);
        assertEq(params.initialMarginBps, 2_500);
        assertEq(params.maintenanceMarginBps, 1_500);

        vm.prank(owner);
        IMarginAccountFacet(address(diamond)).clearRiskDomainRiskParams(riskDomainId);

        params = IMarginAccountFacet(address(diamond)).riskParamsForBucket(bucketId);
        assertEq(params.initialMarginBps, 3_000);
        assertEq(params.maintenanceMarginBps, 2_000);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarginAccountFacet.InvalidMarginRiskParams.selector, 1_000, 2_000));
        IMarginAccountFacet(address(diamond)).setDefaultRiskParams(MarginTypes.BucketKind.MLO, 1_000, 2_000);
    }

    function test_RiskDomainMarkConfigExposesConservativeDomainMark() public {
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);

        vm.startPrank(owner);
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new BookViewFacet()), _bookViewSelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveCLOBFacet()), _curveTradeSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        diamond.registerFacet(address(new MarkOracleFacet()), _markOracleSelectors());
        IMarginAccountFacet(address(diamond))
            .setRiskDomainOracleConfig(riskDomainId, MarginTypes.RiskDomainOracleKind.BookMark, _bookIdForSalt());
        IMarginAccountFacet(address(diamond)).setRiskDomainMarkConfig(riskDomainId, 0, 1_000, 2_000);
        vm.stopPrank();

        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);
        _fillSpotAsk(curveId, 200e6, 100e6);

        MarkOracleTypes.RiskMarkConfig memory config =
            IMarginAccountFacet(address(diamond)).riskDomainMarkConfig(riskDomainId);
        MarkOracleTypes.RiskMark memory mark = IMarginAccountFacet(address(diamond)).riskDomainRiskMark(riskDomainId);

        assertEq(config.assetHaircutBps, 1_000);
        assertEq(config.liabilityPremiumBps, 2_000);
        assertEq(mark.displayPrice, TWO_USDC);
        assertEq(mark.assetRiskPrice, 1.8e18);
        assertEq(mark.liabilityRiskPrice, 2.4e18);
    }

    function test_LazyFundingAccruesPermissionlesslyAndBlocksRelease() public {
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomainId, MarginTypes.FundingMode.BorrowRate, 1e15);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).recordBucketDebt(bucketId, 40e18);

        vm.warp(block.timestamp + 10);
        assertEq(IMarginAccountFacet(address(diamond)).bucketHealth(bucketId).marginEquity, 99.6e18);

        vm.prank(taker);
        uint256 accrued = IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(bucketId);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        MarginTypes.BucketHealth memory health = IMarginAccountFacet(address(diamond)).bucketHealth(bucketId);

        assertEq(accrued, 0.4e18);
        assertEq(bucket.fundingLiability, 0.4e18);
        assertEq(health.marginEquity, 99.6e18);

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(IMarginAccountFacet.BucketBelowInitialMargin.selector, bucketId, 39.6e18, 40e18)
        );
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 60e18);
    }

    function test_FundingConfigDoesNotBackChargeBeforeConfiguration() public {
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).recordBucketDebt(bucketId, 40e18);

        vm.warp(block.timestamp + 100);

        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomainId, MarginTypes.FundingMode.BorrowRate, 1e15);

        assertEq(IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(bucketId), 0);

        vm.warp(block.timestamp + 10);
        assertEq(IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(bucketId), 0.4e18);
    }

    function test_RevertWhen_InvalidFundingConfig() public {
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarginAccountFacet.InvalidFundingConfig.selector, MarginTypes.FundingMode.None, uint128(1)
            )
        );
        IMarginAccountFacet(address(diamond)).setRiskDomainFundingConfig(riskDomainId, MarginTypes.FundingMode.None, 1);
    }

    function test_RiskHooksRequireManagerAndRespectBucketState() public {
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(IMarginAccountFacet.NotMarginRiskManager.selector, taker));
        IMarginAccountFacet(address(diamond)).reserveBucketRisk(bucketId, 10e18);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.Warning);

        assertFalse(IMarginAccountFacet(address(diamond)).canBucketIncreaseRisk(bucketId));

        vm.prank(riskManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarginAccountFacet.BucketCannotIncreaseRisk.selector, bucketId, MarginTypes.BucketState.Warning
            )
        );
        IMarginAccountFacet(address(diamond)).reserveBucketRisk(bucketId, 10e18);

        vm.prank(owner);
        IMarginAccountFacet(address(diamond)).setWarningRiskIncreaseAllowed(true);
        assertTrue(IMarginAccountFacet(address(diamond)).canBucketIncreaseRisk(bucketId));

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).reserveBucketRisk(bucketId, 10e18);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.ReduceOnly);
        assertFalse(IMarginAccountFacet(address(diamond)).canBucketIncreaseRisk(bucketId));
    }

    function test_AdminAccessAndAssetSwitchingGuard() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, taker));
        IMarginAccountFacet(address(diamond)).setMarginRiskManager(taker);

        _wrapEveUSDC(maker, 1e6);

        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), 1e18);
        IMarginAccountFacet(address(diamond)).depositMargin(1e18, maker);
        vm.stopPrank();

        EveUSDC otherAsset = new EveUSDC(address(usdc), makeAddr("otherOnramp"), makeAddr("otherOfframp"));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarginAccountFacet.MarginAssetInUse.selector, 1e18));
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(otherAsset));
    }

    function test_RecordProfitIsBackedAndLossReducesClaims() public {
        bytes32 bucketId = _depositAndAllocate(maker, 100e18);
        _wrapEveUSDC(riskManager, 20e6);

        vm.startPrank(riskManager);
        eveUSDC.approve(address(diamond), 20e18);
        IMarginAccountFacet(address(diamond)).recordBucketProfit(bucketId, 20e18);
        IMarginAccountFacet(address(diamond)).recordBucketLoss(bucketId, 30e18);
        vm.stopPrank();

        MarginTypes.MarginAccount memory account = IMarginAccountFacet(address(diamond)).getMarginAccount(maker);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);

        assertEq(account.allocatedMargin, 90e18);
        assertEq(account.realizedProfits, 20e18);
        assertEq(account.realizedLosses, 30e18);
        assertEq(bucket.marginAllocated, 90e18);
        assertEq(bucket.realizedProfits, 20e18);
        assertEq(bucket.realizedLosses, 30e18);
        assertEq(eveUSDC.balanceOf(address(diamond)), 120e18);
    }

    function test_MarginFacetDoesNotChangeEscrowBackedBookFlow() public {
        bytes32 bucketId = _depositAndAllocate(maker, 25e18);
        assertTrue(IMarginAccountFacet(address(diamond)).canBucketIncreaseRisk(bucketId));

        vm.startPrank(owner);
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new BookViewFacet()), _bookViewSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveCLOBFacet()), _curveTradeSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        vm.stopPrank();

        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 200e6);
        uint128 baseOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 200e6, 100e6, generation, commitment);
        vm.stopPrank();

        assertEq(baseOut, 100e6);
        assertEq(spotToken.balanceOf(taker), 1_000_100e6);
        assertEq(usdc.balanceOf(maker), 1_000_200e6);
        assertEq(eveUSDC.balanceOf(address(diamond)), 25e18);
    }

    function _depositAndAllocate(address operator, uint256 assets) internal returns (bytes32 bucketId) {
        _wrapEveUSDC(operator, assets / 1e12);

        vm.startPrank(operator);
        eveUSDC.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).depositMargin(assets, operator);
        bytes32 riskDomainId = IMarginAccountFacet(address(diamond)).riskDomainForBook(SPOT_SALT);
        bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomainId, assets);
        vm.stopPrank();
    }

    function _wrapEveUSDC(address account, uint256 usdcAmount) internal {
        usdc.mint(account, usdcAmount);

        vm.startPrank(account);
        usdc.approve(address(eveUSDC), usdcAmount);
        eveUSDC.wrap(usdcAmount, account);
        vm.stopPrank();
    }

    function _createSpotBook() internal returns (bytes32 bookId) {
        vm.prank(maker);
        bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                SPOT_SALT
            );
    }

    function _postSpotAsk(bytes32 bookId, uint128 volume, uint72 price) internal returns (uint256 curveId) {
        vm.startPrank(maker);
        spotToken.approve(address(diamond), volume);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, volume, price, price, 120, 0, type(uint8).max);
        vm.stopPrank();
    }

    function _fillSpotAsk(uint256 curveId, uint128 quoteIn, uint128 minBaseOut) internal {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        usdc.approve(address(diamond), quoteIn);
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, quoteIn, minBaseOut, generation, commitment);
        vm.stopPrank();
    }

    function _bookIdForSalt() internal view returns (bytes32 bookId) {
        bookId = IBookAdminFacet(address(diamond))
            .computeBookId(
                maker,
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                SPOT_SALT
            );
    }

    function _marginSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](51);
        selectors[0] = IMarginAccountFacet.marginConfig.selector;
        selectors[1] = IMarginAccountFacet.depositMargin.selector;
        selectors[2] = IMarginAccountFacet.withdrawMargin.selector;
        selectors[3] = IMarginAccountFacet.allocateBucketMargin.selector;
        selectors[4] = IMarginAccountFacet.releaseBucketMargin.selector;
        selectors[5] = IMarginAccountFacet.getMarginAccount.selector;
        selectors[6] = IMarginAccountFacet.getMarginBucket.selector;
        selectors[7] = IMarginAccountFacet.bucketIdFor.selector;
        selectors[8] = IMarginAccountFacet.riskDomainForBook.selector;
        selectors[9] = IMarginAccountFacet.riskDomainForMarketBook.selector;
        selectors[10] = IMarginAccountFacet.canBucketIncreaseRisk.selector;
        selectors[11] = IMarginAccountFacet.setMarginAsset.selector;
        selectors[12] = IMarginAccountFacet.setMarginRiskManager.selector;
        selectors[13] = IMarginAccountFacet.setWarningRiskIncreaseAllowed.selector;
        selectors[14] = IMarginAccountFacet.reserveBucketRisk.selector;
        selectors[15] = IMarginAccountFacet.releaseReservedBucketRisk.selector;
        selectors[16] = IMarginAccountFacet.activateReservedBucketRisk.selector;
        selectors[17] = IMarginAccountFacet.releaseActiveBucketRisk.selector;
        selectors[18] = IMarginAccountFacet.recordBucketProfit.selector;
        selectors[19] = IMarginAccountFacet.recordBucketLoss.selector;
        selectors[20] = IMarginAccountFacet.setBucketState.selector;
        selectors[21] = IMarginAccountFacet.allocateBucketMarginWithKind.selector;
        selectors[22] = IMarginAccountFacet.getBucketRisk.selector;
        selectors[23] = IMarginAccountFacet.bucketLockedRisk.selector;
        selectors[24] = IMarginAccountFacet.canBucketIncreaseRiskForBook.selector;
        selectors[25] = IMarginAccountFacet.riskDomainOracleConfig.selector;
        selectors[26] = IMarginAccountFacet.setRiskDomainOracleConfig.selector;
        selectors[27] = IMarginAccountFacet.increaseOpenOrderRisk.selector;
        selectors[28] = IMarginAccountFacet.releaseOpenOrderRisk.selector;
        selectors[29] = IMarginAccountFacet.moveOpenOrderToPositionRisk.selector;
        selectors[30] = IMarginAccountFacet.releasePositionRisk.selector;
        selectors[31] = IMarginAccountFacet.recordBucketDebt.selector;
        selectors[32] = IMarginAccountFacet.repayBucketDebt.selector;
        selectors[33] = IMarginAccountFacet.accrueBucketFunding.selector;
        selectors[34] = IMarginAccountFacet.settleBucketFunding.selector;
        selectors[35] = IMarginAccountFacet.recordBucketUnrealizedPnl.selector;
        selectors[36] = IMarginAccountFacet.recordBucketRecoveryPnl.selector;
        selectors[37] = IMarginAccountFacet.recordBucketBadDebt.selector;
        selectors[38] = IMarginAccountFacet.bucketHealth.selector;
        selectors[39] = IMarginAccountFacet.riskParamsForBucket.selector;
        selectors[40] = IMarginAccountFacet.defaultRiskParams.selector;
        selectors[41] = IMarginAccountFacet.riskDomainRiskParams.selector;
        selectors[42] = IMarginAccountFacet.setDefaultRiskParams.selector;
        selectors[43] = IMarginAccountFacet.setRiskDomainRiskParams.selector;
        selectors[44] = IMarginAccountFacet.clearRiskDomainRiskParams.selector;
        selectors[45] = IMarginAccountFacet.riskDomainMarkConfig.selector;
        selectors[46] = IMarginAccountFacet.riskDomainRiskMark.selector;
        selectors[47] = IMarginAccountFacet.riskDomainFundingConfig.selector;
        selectors[48] = IMarginAccountFacet.setRiskDomainMarkConfig.selector;
        selectors[49] = IMarginAccountFacet.setRiskDomainFundingConfig.selector;
        selectors[50] = IMarginAccountFacet.accrueBucketFundingNow.selector;
    }

    function _markOracleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IMarkOracleFacet.getMarkOracle.selector;
        selectors[1] = IMarkOracleFacet.getMarkObservation.selector;
        selectors[2] = IMarkOracleFacet.consultTwap.selector;
        selectors[3] = IMarkOracleFacet.consultVwap.selector;
        selectors[4] = IMarkOracleFacet.oracleState.selector;
        selectors[5] = IMarkOracleFacet.markOracleConfig.selector;
        selectors[6] = IMarkOracleFacet.setMarkOracleThresholds.selector;
        selectors[7] = IMarkOracleFacet.clearMarkOracleManualState.selector;
        selectors[8] = IMarkOracleFacet.setMarkOracleManualState.selector;
        selectors[9] = IMarkOracleFacet.riskMarkForBook.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.computeBookId.selector;
        selectors[2] = IBookAdminFacet.getBookInfo.selector;
        selectors[3] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[4] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.reactivateBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBest.selector;
    }

    function _bookViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookTopOfBook.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[2] = ICurveLifecycleFacet.updateCurve.selector;
        selectors[3] = ICurveLifecycleFacet.updateCurvesBatch.selector;
        selectors[4] = ICurveLifecycleFacet.updateCurveFromNow.selector;
        selectors[5] = ICurveLifecycleFacet.updateCurvesFromNowBatch.selector;
    }

    function _curveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[1] = ICurveViewFacet.getCurveInfo.selector;
    }
}
