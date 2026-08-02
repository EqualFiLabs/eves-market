// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {MultiOutcomeOrderbookFacet} from "../../src/facets/MultiOutcomeOrderbookFacet.sol";
import {MultiOutcomeOrderbookViewFacet} from "../../src/facets/MultiOutcomeOrderbookViewFacet.sol";
import {IMultiOutcomeOrderbookFacet} from "../../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {LibMultiOutcome} from "../../src/libraries/LibMultiOutcome.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";

import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract MultiOutcomeHarness is MultiOutcomeOrderbookFacet {
    function configure(address collateralToken, address eveToken, address positionManager) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.collateralToken = collateralToken;
        config.eveToken = eveToken;
        config.bondToken = eveToken;
        config.eveTreasury = address(0xBEEF);
        config.evesPositionManager = positionManager;
        config.permissionlessCreationEnabled = true;
        config.minMarketDuration = 1;
        config.maxMarketDuration = 365 days;
        config.disputeWindow = 1 hours;
        config.creatorSettleGrace = 1 hours;
        config.openResolutionTimeout = 1 hours;
        config.marketCreationBatchCap = 30;
        config.orderbookFeeConfig.makerFeeBps = 4_000;
        config.orderbookFeeConfig.creatorFeeBps = 500;
        config.orderbookFeeConfig.protocolFeeBps = 3_000;
        config.orderbookFeeConfig.vaultFeeBps = 2_500;
    }

    function configureCollateralProfile(
        uint256 profileId,
        address collateralToken,
        address wrapperToken,
        uint256 payoutUnit,
        uint256 marketCreationFee,
        bool enabled
    ) external {
        if (profileId > type(uint8).max) revert Errors.InvalidAmount(profileId);
        if (payoutUnit == 0 || payoutUnit > type(uint128).max) revert Errors.InvalidAmount(payoutUnit);
        if (marketCreationFee > type(uint128).max) revert Errors.InvalidAmount(marketCreationFee);

        LibEveMarket.CollateralProfile storage profile = LibEveMarket.store().collateralProfiles[uint8(profileId)];
        profile.collateralToken = collateralToken;
        profile.wrapperToken = wrapperToken;
        profile.payoutUnit = uint128(payoutUnit);
        profile.marketCreationFee = uint128(marketCreationFee);
        profile.enabled = enabled;
    }

    function configureCreationCosts(uint256 marketCreationFee, uint256 marketCreationBond) external {
        if (marketCreationFee > type(uint128).max) revert Errors.InvalidAmount(marketCreationFee);
        if (marketCreationBond > type(uint128).max) revert Errors.InvalidAmount(marketCreationBond);

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.marketCreationFee = uint128(marketCreationFee);
        config.marketCreationBond = uint128(marketCreationBond);
    }

    function metadataFor(bytes32 marketId)
        external
        view
        returns (
            address collateralToken,
            uint8 collateralProfileId,
            uint128 payoutUnit,
            uint8 marketType,
            uint8 positionTokenType
        )
    {
        LibEveMarket.MarketMetadata storage metadata = LibEveMarket.store().marketMetadata[marketId];
        collateralToken = metadata.collateralToken;
        collateralProfileId = metadata.collateralProfileId;
        payoutUnit = metadata.payoutUnit;
        marketType = uint8(metadata.marketType);
        positionTokenType = uint8(metadata.positionTokenType);
    }

    function creationAmounts(bytes32 marketId) external view returns (uint128 creationFeePaid, uint128 creationBond) {
        LibEveMarket.Market storage core = LibEveMarket.store().markets[marketId];
        creationFeePaid = core.creationFeePaid;
        creationBond = core.creationBond;
    }

    function getMultiOutcomeMarket(bytes32 marketId)
        external
        view
        returns (IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView memory marketView)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibEveMarket.Market storage core = state.markets[marketId];
        marketView = IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView({
            marketId: multi.marketId,
            conditionId: multi.conditionId,
            outcomesHash: multi.outcomesHash,
            positionToken: core.positionToken,
            collateralToken: core.collateralToken,
            marketType: uint8(core.marketType),
            positionTokenType: uint8(core.positionTokenType),
            collateralProfileId: core.collateralProfileId,
            outcomeCount: multi.outcomeCount,
            payoutUnit: core.payoutUnit,
            resolvedOutcome: multi.resolvedOutcome,
            payoutDenominator: multi.payoutDenominator,
            invalid: multi.invalid,
            resolved: multi.resolved
        });
    }

    function getMultiOutcomeOutcomes(bytes32 marketId) external view returns (string[] memory outcomes) {
        LibMultiOutcome.requireMultiOutcome(LibEveMarket.store(), marketId);
        outcomes = LibEveMarket.store().multiOutcomeLabels[marketId];
    }

    function getOutcomePositionId(bytes32 marketId, uint8 outcome) external view returns (uint256 positionId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibMultiOutcome.requireOutcome(multi, outcome);
        positionId = state.multiOutcomePositionIds[marketId][outcome];
    }

    function getMultiOutcomeBooks(bytes32 marketId) external view returns (bytes32[] memory bookIds) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        bookIds = new bytes32[](multi.outcomeCount);
        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            bookIds[outcome] = state.multiOutcomeBookIds[marketId][outcome];
        }
    }

    function resolveFixture(bytes32 marketId, uint8 outcome) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage core = state.markets[marketId];
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
        if (!multi.exists || !LibMultiOutcome.isValidResolution(outcome, multi.outcomeCount)) {
            revert Errors.InvalidOutcome(outcome);
        }

        core.state = LibEveMarket.MarketState.Resolved;
        core.resolutionTime = uint64(block.timestamp);
        core.outcome = outcome == LibMultiOutcome.OUTCOME_INVALID
            ? LibEveMarket.MarketOutcome.Invalid
            : LibEveMarket.MarketOutcome.Unresolved;
        multi.resolved = true;
        multi.invalid = outcome == LibMultiOutcome.OUTCOME_INVALID;
        multi.resolvedOutcome = outcome;
        multi.payoutDenominator = multi.invalid ? multi.outcomeCount : 1;

        emit Events.MultiOutcomeResolved(marketId, outcome, multi.invalid, multi.payoutDenominator);
    }
}

contract MultiOutcomeOrderbookTest is Test {
    uint256 internal constant EIP170_MAX_CODE_SIZE = 24_576;

    MultiOutcomeHarness internal market;
    EvesPositionManager internal positions;
    MockUSDC internal collateral;
    MockEveToken internal eve;
    MockEveToken internal eveETH;

    address internal creator = makeAddr("creator");
    address internal trader = makeAddr("trader");
    address internal treasury = address(0xBEEF);

    uint8 internal constant EVE_ETH_PROFILE_ID = 1;
    uint128 internal constant DEFAULT_EVEUSDC_PAYOUT_UNIT = 1 ether;
    uint128 internal constant EVE_ETH_PAYOUT_UNIT = 0.0005 ether;
    uint128 internal constant EVE_ETH_CREATION_FEE = 0.002 ether;
    uint128 internal constant EVE_BOND = 10 ether;

    function setUp() public {
        market = new MultiOutcomeHarness();
        positions = new EvesPositionManager(address(market), "");
        collateral = new MockUSDC();
        eve = new MockEveToken();
        eveETH = new MockEveToken();

        market.configure(address(collateral), address(eve), address(positions));

        collateral.mint(creator, 1_000_000e6);
        collateral.mint(trader, 1_000_000e6);
        eve.mint(creator, 1_000_000e18);
        eve.mint(trader, 1_000_000e18);
        eveETH.mint(creator, 1_000_000e18);
        eveETH.mint(trader, 1_000_000e18);

        vm.prank(creator);
        collateral.approve(address(market), type(uint256).max);
        vm.prank(trader);
        collateral.approve(address(market), type(uint256).max);
        vm.prank(creator);
        eveETH.approve(address(market), type(uint256).max);
        vm.prank(trader);
        eveETH.approve(address(market), type(uint256).max);
        vm.prank(creator);
        eve.approve(address(market), type(uint256).max);
    }

    function test_CreateStoresOutcomesAndPositions() public {
        bytes32 marketId = _createMarket();

        IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView memory view_ = market.getMultiOutcomeMarket(marketId);
        assertEq(view_.outcomeCount, 4);
        assertEq(view_.positionToken, address(positions));
        assertEq(view_.collateralToken, address(collateral));
        assertEq(view_.marketType, uint8(LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK));
        assertEq(view_.positionTokenType, uint8(LibEveMarket.PositionTokenType.EVES_POSITION));
        assertEq(view_.collateralProfileId, 0);
        assertEq(view_.payoutUnit, DEFAULT_EVEUSDC_PAYOUT_UNIT);
        assertFalse(view_.resolved);

        string[] memory outcomes = market.getMultiOutcomeOutcomes(marketId);
        assertEq(outcomes.length, 4);
        assertEq(outcomes[0], "A");
        assertEq(outcomes[3], "D");

        for (uint8 outcome; outcome < 4; ++outcome) {
            uint256 expectedPositionId = LibMultiOutcome.positionIdFor(view_.conditionId, outcome);
            assertEq(market.getOutcomePositionId(marketId, outcome), expectedPositionId);
        }

        bytes32[] memory bookIds = market.getMultiOutcomeBooks(marketId);
        assertEq(bookIds.length, 4);
        assertTrue(bookIds[0] != bytes32(0));
    }

    function test_FacetsStayUnderEIP170DeployLimit() public {
        assertLe(address(new MultiOutcomeOrderbookFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new MultiOutcomeOrderbookViewFacet()).code.length, EIP170_MAX_CODE_SIZE);
    }

    function test_ProfileCreationUsesEveETHAndStoresMetadata() public {
        _configureEveETHProfile(true);
        market.configureCreationCosts(0, EVE_BOND);

        string[] memory outcomes = _outcomes("A", "B", "C", "D");
        bytes32 outcomesHash = LibMultiOutcome.outcomesHash(outcomes);
        uint64 tradingStartTime = uint64(block.timestamp);
        uint64 expiryTime = uint64(block.timestamp + 1 days);
        bytes32 expectedMarketId = LibMarketCreation.multiOutcomeMarketIdFor(
            "Who wins?",
            "Politics",
            tradingStartTime,
            expiryTime,
            address(eveETH),
            EVE_ETH_PROFILE_ID,
            EVE_ETH_PAYOUT_UNIT,
            uint8(outcomes.length),
            outcomesHash,
            LibEveMarket.PositionTokenType.EVES_POSITION
        );

        vm.prank(creator);
        bytes32 marketId = market.createMultiOutcomeMarketWithCollateralProfile(
            EVE_ETH_PROFILE_ID,
            IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                question: "Who wins?",
                category: "Politics",
                resolutionSource: "Source",
                tradingStartTime: tradingStartTime,
                expiryTime: expiryTime,
                outcomes: outcomes,
                display: _emptyMultiOutcomeDisplay(),
                externalRef: _emptyMultiOutcomeExternalRef(),
                outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
            })
        );

        assertEq(marketId, expectedMarketId);
        assertEq(eveETH.balanceOf(treasury), EVE_ETH_CREATION_FEE);
        assertEq(eve.balanceOf(address(market)), EVE_BOND);

        IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView memory view_ = market.getMultiOutcomeMarket(marketId);
        assertEq(view_.collateralToken, address(eveETH));
        assertEq(view_.collateralProfileId, EVE_ETH_PROFILE_ID);
        assertEq(view_.payoutUnit, EVE_ETH_PAYOUT_UNIT);
        assertEq(view_.marketType, uint8(LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK));
        assertEq(view_.positionTokenType, uint8(LibEveMarket.PositionTokenType.EVES_POSITION));
        assertEq(view_.outcomeCount, 4);
        assertEq(view_.outcomesHash, outcomesHash);

        (
            address metadataCollateralToken,
            uint8 metadataProfileId,
            uint128 metadataPayoutUnit,
            uint8 metadataMarketType,
            uint8 metadataPositionTokenType
        ) = market.metadataFor(marketId);
        assertEq(metadataCollateralToken, address(eveETH));
        assertEq(metadataProfileId, EVE_ETH_PROFILE_ID);
        assertEq(metadataPayoutUnit, EVE_ETH_PAYOUT_UNIT);
        assertEq(metadataMarketType, uint8(LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK));
        assertEq(metadataPositionTokenType, uint8(LibEveMarket.PositionTokenType.EVES_POSITION));

        (uint128 creationFeePaid, uint128 creationBond) = market.creationAmounts(marketId);
        assertEq(creationFeePaid, EVE_ETH_CREATION_FEE);
        assertEq(creationBond, EVE_BOND);
    }

    function test_ProfileMarketIdSeparatesCollateralPayoutAndOutcomes() public {
        _configureEveETHProfile(true);

        uint64 tradingStartTime = uint64(block.timestamp);
        uint64 expiryTime = uint64(block.timestamp + 1 days);
        string[] memory firstOutcomes = _outcomes("A", "B", "C", "D");
        string[] memory secondOutcomes = _outcomes("A", "B", "C", "E");

        vm.prank(creator);
        bytes32 profileMarketId = market.createMultiOutcomeMarketWithCollateralProfile(
            EVE_ETH_PROFILE_ID, _params("Who wins?", "Politics", "Source", tradingStartTime, expiryTime, firstOutcomes)
        );

        vm.prank(creator);
        bytes32 defaultMarketId = market.createMultiOutcomeMarket(
            _params("Who wins?", "Politics", "Source", tradingStartTime, expiryTime, firstOutcomes)
        );

        vm.prank(creator);
        bytes32 otherOutcomeMarketId = market.createMultiOutcomeMarketWithCollateralProfile(
            EVE_ETH_PROFILE_ID, _params("Who wins?", "Politics", "Source", tradingStartTime, expiryTime, secondOutcomes)
        );

        bytes32 otherPayoutUnitId = LibMarketCreation.multiOutcomeMarketIdFor(
            "Who wins?",
            "Politics",
            tradingStartTime,
            expiryTime,
            address(eveETH),
            EVE_ETH_PROFILE_ID,
            EVE_ETH_PAYOUT_UNIT * 2,
            uint8(firstOutcomes.length),
            LibMultiOutcome.outcomesHash(firstOutcomes),
            LibEveMarket.PositionTokenType.EVES_POSITION
        );

        assertTrue(profileMarketId != defaultMarketId);
        assertTrue(profileMarketId != otherOutcomeMarketId);
        assertTrue(profileMarketId != otherPayoutUnitId);
    }

    function test_RevertWhen_ProfileDisabled() public {
        _configureEveETHProfile(false);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileDisabled.selector, EVE_ETH_PROFILE_ID));
        market.createMultiOutcomeMarketWithCollateralProfile(
            EVE_ETH_PROFILE_ID,
            _params(
                "Who wins?",
                "Politics",
                "Source",
                uint64(block.timestamp),
                uint64(block.timestamp + 1 days),
                _outcomes("A", "B", "C", "D")
            )
        );
    }

    function test_SplitAndMergeCompleteOutcomeSetIsCollateralNeutral() public {
        bytes32 marketId = _createMarket();
        uint128 amount = 100e6;
        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        uint256[] memory positionIds = market.splitOutcomeSet(marketId, amount, trader);

        assertEq(collateral.balanceOf(trader), balanceBefore - amount);
        for (uint256 index; index < positionIds.length; ++index) {
            assertEq(positions.balanceOf(trader, positionIds[index]), amount);
        }

        vm.prank(trader);
        uint128 collateralOut = market.mergeOutcomeSet(marketId, amount, trader);

        assertEq(collateralOut, amount);
        assertEq(collateral.balanceOf(trader), balanceBefore);
        for (uint256 index; index < positionIds.length; ++index) {
            assertEq(positions.balanceOf(trader, positionIds[index]), 0);
        }
    }

    function test_RevertWhen_MergeMissingOutcomeInventory() public {
        bytes32 marketId = _createMarket();
        vm.prank(trader);
        uint256[] memory positionIds = market.splitOutcomeSet(marketId, 100e6, trader);

        vm.prank(trader);
        positions.safeTransferFrom(trader, creator, positionIds[2], 1, "");

        vm.prank(trader);
        vm.expectRevert();
        market.mergeOutcomeSet(marketId, 100e6, trader);
    }

    function test_ResolveWinnerAndRedeemOnlyWinningOutcome() public {
        bytes32 marketId = _createMarket();
        vm.prank(trader);
        market.splitOutcomeSet(marketId, 100e6, trader);

        _resolve(marketId, 2);

        uint256 winnerPositionId = market.getOutcomePositionId(marketId, 2);
        uint256 loserPositionId = market.getOutcomePositionId(marketId, 1);
        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        uint128 loserOut = market.redeemOutcome(marketId, 1, 100e6, trader);
        assertEq(loserOut, 0);
        assertEq(positions.balanceOf(trader, loserPositionId), 0);

        vm.prank(trader);
        uint128 winnerOut = market.redeemOutcome(marketId, 2, 100e6, trader);
        assertEq(winnerOut, 100e6);
        assertEq(positions.balanceOf(trader, winnerPositionId), 0);
        assertEq(collateral.balanceOf(trader), balanceBefore + 100e6);
    }

    function test_InvalidPaysEqualSharePerOutcome() public {
        bytes32 marketId = _createMarket();
        vm.prank(trader);
        market.splitOutcomeSet(marketId, 100e6, trader);

        _resolve(marketId, LibMultiOutcome.OUTCOME_INVALID);

        uint256 balanceBefore = collateral.balanceOf(trader);
        vm.prank(trader);
        uint128 collateralOut = market.redeemOutcome(marketId, 0, 100e6, trader);

        assertEq(collateralOut, 25e6);
        assertEq(collateral.balanceOf(trader), balanceBefore + 25e6);
    }

    function test_RevertWhen_DuplicateOutcomeLabels() public {
        string[] memory outcomes = new string[](3);
        outcomes[0] = "A";
        outcomes[1] = "B";
        outcomes[2] = "A";

        vm.prank(creator);
        vm.expectRevert();
        market.createMultiOutcomeMarket(
            IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                question: "Who wins?",
                category: "Politics",
                resolutionSource: "Source",
                tradingStartTime: uint64(block.timestamp),
                expiryTime: uint64(block.timestamp + 1 days),
                outcomes: outcomes,
                display: _emptyMultiOutcomeDisplay(),
                externalRef: _emptyMultiOutcomeExternalRef(),
                outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
            })
        );
    }

    function _createMarket() internal returns (bytes32 marketId) {
        string[] memory outcomes = _outcomes("A", "B", "C", "D");

        vm.prank(creator);
        marketId = market.createMultiOutcomeMarket(
            _params(
                "Who wins?", "Politics", "Source", uint64(block.timestamp), uint64(block.timestamp + 1 days), outcomes
            )
        );
    }

    function _resolve(bytes32 marketId, uint8 outcome) internal {
        market.resolveFixture(marketId, outcome);
    }

    function _configureEveETHProfile(bool enabled) internal {
        market.configureCollateralProfile(
            EVE_ETH_PROFILE_ID, address(eveETH), address(0), EVE_ETH_PAYOUT_UNIT, EVE_ETH_CREATION_FEE, enabled
        );
    }

    function _outcomes(string memory a, string memory b, string memory c, string memory d)
        internal
        pure
        returns (string[] memory outcomes)
    {
        outcomes = new string[](4);
        outcomes[0] = a;
        outcomes[1] = b;
        outcomes[2] = c;
        outcomes[3] = d;
    }

    function _params(
        string memory question,
        string memory category,
        string memory resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        string[] memory outcomes
    ) internal pure returns (IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams memory params) {
        params = IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
            question: question,
            category: category,
            resolutionSource: resolutionSource,
            tradingStartTime: tradingStartTime,
            expiryTime: expiryTime,
            outcomes: outcomes,
            display: _emptyMultiOutcomeDisplay(),
            externalRef: _emptyMultiOutcomeExternalRef(),
            outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
        });
    }

    function _emptyMultiOutcomeDisplay() internal pure returns (MarketFactoryTypes.MarketDisplayInput memory display) {}

    function _emptyMultiOutcomeExternalRef()
        internal
        pure
        returns (MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
    {}
}
