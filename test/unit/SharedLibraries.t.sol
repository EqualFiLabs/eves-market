// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {LibCTF} from "src/libraries/LibCTF.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibParimutuel} from "src/libraries/LibParimutuel.sol";

contract SharedLibrariesTest is Test {
    LibEveMarketHarness internal eveMarketHarness;
    LibParimutuelHarness internal parimutuelHarness;
    LibCTFHarness internal ctfHarness;
    EventsHarness internal eventsHarness;
    MockConditionalTokens internal mockConditionalTokens;

    function setUp() public {
        eveMarketHarness = new LibEveMarketHarness();
        parimutuelHarness = new LibParimutuelHarness();
        ctfHarness = new LibCTFHarness();
        eventsHarness = new EventsHarness();
        mockConditionalTokens = new MockConditionalTokens();
    }

    function test_LibEveMarketStoreUsesExpectedStorageSlot() public {
        address conditionalTokens = address(0xCA11);
        address parimutuelShareToken = address(0x1155);

        eveMarketHarness.setConfig(conditionalTokens);
        eveMarketHarness.setParimutuelConfig(parimutuelShareToken, 250, 1e6);

        bytes32 slot = bytes32(uint256(keccak256("eve.prediction.market.storage")) - 1);

        assertEq(address(uint160(uint256(vm.load(address(eveMarketHarness), slot)))), conditionalTokens);
        assertEq(
            address(uint160(uint256(vm.load(address(eveMarketHarness), bytes32(uint256(slot) + 2))))),
            parimutuelShareToken
        );
    }

    function test_LibEveMarketDefinesMarketTypes() public pure {
        assertEq(uint8(LibEveMarket.MarketType.CLOB), 0);
        assertEq(uint8(LibEveMarket.MarketType.PARIMUTUEL), 1);
    }

    function test_LibEveMarketStoresParimutuelConfig() public {
        address shareToken = address(0x1155);

        eveMarketHarness.setParimutuelConfig(shareToken, 250, 1e6);

        (address storedShareToken, uint16 entryFeeBps, uint128 minEntry) = eveMarketHarness.getParimutuelConfig();

        assertEq(storedShareToken, shareToken);
        assertEq(entryFeeBps, 250);
        assertEq(minEntry, 1e6);
    }

    function test_LibEveMarketStoresMarketMetadata() public {
        bytes32 marketId = keccak256("market");
        bytes32 questionId = keccak256("question");
        bytes32 conditionId = keccak256("condition");
        address positionToken = address(0x1155);

        eveMarketHarness.setMarket(
            marketId,
            LibEveMarket.MarketType.PARIMUTUEL,
            positionToken,
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            questionId,
            conditionId,
            111,
            222,
            LibEveMarket.MarketState.Disputed
        );

        (
            uint8 marketType,
            address storedPositionToken,
            address collateralToken,
            bytes32 storedQuestionId,
            bytes32 storedConditionId,
            uint256 yesPositionId,
            uint256 noPositionId,
            uint8 state
        ) = eveMarketHarness.getMarket(marketId);

        assertEq(marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(storedPositionToken, positionToken);
        assertEq(collateralToken, address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
        assertEq(storedQuestionId, questionId);
        assertEq(storedConditionId, conditionId);
        assertEq(yesPositionId, 111);
        assertEq(noPositionId, 222);
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
    }

    function test_LibParimutuelStoreUsesExpectedStorageSlot() public {
        bytes32 marketId = keccak256("parimutuel-pool");

        parimutuelHarness.setPool(marketId, 11, 22, 33, 44, 55, true);

        bytes32 slot = bytes32(uint256(keccak256("eve.prediction.parimutuel.storage")) - 1);
        bytes32 poolSlot = keccak256(abi.encode(marketId, slot));

        assertEq(uint256(vm.load(address(parimutuelHarness), poolSlot)), (uint256(22) << 128) | uint256(11));
        assertEq(
            uint256(vm.load(address(parimutuelHarness), bytes32(uint256(poolSlot) + 1))),
            (uint256(44) << 128) | uint256(33)
        );
        assertEq(
            uint256(vm.load(address(parimutuelHarness), bytes32(uint256(poolSlot) + 2))),
            uint256(55)
        );
    }

    function test_LibParimutuelStoresPoolState() public {
        bytes32 marketId = keccak256("parimutuel-pool-state");

        parimutuelHarness.setPool(marketId, 1_000, 2_000, 2_850, 1_200, 1_500, true);

        (
            uint128 totalYesShares,
            uint128 totalNoShares,
            uint128 payoutPool,
            uint128 claimedPayout,
            uint128 claimedClaimableShares,
            bool dustSwept
        ) = parimutuelHarness.getPool(marketId);

        assertEq(totalYesShares, 1_000);
        assertEq(totalNoShares, 2_000);
        assertEq(payoutPool, 2_850);
        assertEq(claimedPayout, 1_200);
        assertEq(claimedClaimableShares, 1_500);
        assertTrue(dustSwept);
    }

    function test_LibParimutuelDerivesEffectivePayoutOutcome() public {
        bytes32 marketId = keccak256("parimutuel-effective-outcome");

        parimutuelHarness.setPool(marketId, 0, 2_000, 2_000, 0, 0, false);

        assertEq(
            parimutuelHarness.effectivePayoutOutcome(marketId, uint8(LibEveMarket.MarketOutcome.Yes)),
            uint8(LibEveMarket.MarketOutcome.Invalid)
        );
        assertEq(
            parimutuelHarness.effectivePayoutOutcome(marketId, uint8(LibEveMarket.MarketOutcome.No)),
            uint8(LibEveMarket.MarketOutcome.No)
        );

        parimutuelHarness.setPool(marketId, 1_000, 0, 1_000, 0, 0, false);

        assertEq(
            parimutuelHarness.effectivePayoutOutcome(marketId, uint8(LibEveMarket.MarketOutcome.Yes)),
            uint8(LibEveMarket.MarketOutcome.Yes)
        );
        assertEq(
            parimutuelHarness.effectivePayoutOutcome(marketId, uint8(LibEveMarket.MarketOutcome.No)),
            uint8(LibEveMarket.MarketOutcome.Invalid)
        );
        assertEq(
            parimutuelHarness.effectivePayoutOutcome(marketId, uint8(LibEveMarket.MarketOutcome.Invalid)),
            uint8(LibEveMarket.MarketOutcome.Invalid)
        );
    }

    function test_ParimutuelErrorSelectors() public pure {
        assertEq(Errors.NotParimutuelMarket.selector, bytes4(keccak256("NotParimutuelMarket(bytes32)")));
        assertEq(
            Errors.PositionTokenTypeMismatch.selector,
            bytes4(keccak256("PositionTokenTypeMismatch(bytes32,uint8,uint8)"))
        );
        assertEq(Errors.NoWinningShares.selector, bytes4(keccak256("NoWinningShares(bytes32,address)")));
        assertEq(
            Errors.ParimutuelPoolNotFinalized.selector, bytes4(keccak256("ParimutuelPoolNotFinalized(bytes32)"))
        );
        assertEq(Errors.FeeExceedsAmount.selector, bytes4(keccak256("FeeExceedsAmount(uint128,uint128)")));
        assertEq(Errors.ClaimableSharesRemain.selector, bytes4(keccak256("ClaimableSharesRemain(bytes32,uint256)")));
        assertEq(
            Errors.FeeSplitExceedsDenominator.selector, bytes4(keccak256("FeeSplitExceedsDenominator(uint16,uint16)"))
        );
    }

    function test_ParimutuelEventsEmitExpectedTopicsAndData() public {
        bytes32 marketId = keccak256("parimutuel-market");
        address creator = address(0xC0FFEE);
        address positionToken = address(0x1155);
        address buyer = address(0xB0B);
        address receiver = address(0xA11CE);
        uint256 yesPositionId = 111;
        uint256 noPositionId = 222;
        uint64 expiryTime = 123_456;

        vm.expectEmit(true, true, true, true, address(eventsHarness));
        emit Events.ParimutuelMarketCreated(
            marketId, creator, positionToken, yesPositionId, noPositionId, expiryTime, 7 days
        );
        eventsHarness.emitParimutuelMarketCreated(
            marketId, creator, positionToken, yesPositionId, noPositionId, expiryTime, 7 days
        );

        vm.expectEmit(true, true, true, true, address(eventsHarness));
        emit Events.ParimutuelSharesBought(marketId, buyer, receiver, true, 1_000e6, 975e6, 25e6);
        eventsHarness.emitParimutuelSharesBought(marketId, buyer, receiver, true, 1_000e6, 975e6, 25e6);

        vm.expectEmit(true, true, true, true, address(eventsHarness));
        emit Events.ParimutuelPayoutClaimed(marketId, receiver, yesPositionId, 975e6, 1_250e6);
        eventsHarness.emitParimutuelPayoutClaimed(marketId, receiver, yesPositionId, 975e6, 1_250e6);

        vm.expectEmit(true, true, false, true, address(eventsHarness));
        emit Events.ParimutuelDustSwept(marketId, creator, 3);
        eventsHarness.emitParimutuelDustSwept(marketId, creator, 3);

        vm.expectEmit(true, false, false, true, address(eventsHarness));
        emit Events.ParimutuelFinalized(marketId, 1, 3, 2_000e6, 2_000e6);
        eventsHarness.emitParimutuelFinalized(marketId, 1, 3, 2_000e6, 2_000e6);
    }

    function test_LibCTFPrepareMarketConditionUsesCallingContractAsOracle() public {
        bytes32 questionId = keccak256("binary-question");

        bytes32 conditionId = ctfHarness.prepareMarketCondition(address(mockConditionalTokens), questionId);

        assertEq(mockConditionalTokens.lastOracle(), address(ctfHarness));
        assertEq(mockConditionalTokens.lastQuestionId(), questionId);
        assertEq(mockConditionalTokens.lastOutcomeSlotCount(), 2);
        assertEq(conditionId, keccak256(abi.encodePacked(address(ctfHarness), questionId, uint256(2))));
    }

    function test_LibCTFDerivePositionIdsBuildsBinaryCollections() public view {
        bytes32 conditionId = keccak256("condition");
        address collateralToken = address(0x1234);

        (uint256 yesPositionId, uint256 noPositionId) =
            ctfHarness.derivePositionIds(address(mockConditionalTokens), collateralToken, conditionId);

        bytes32 yesCollectionId = keccak256(abi.encodePacked(bytes32(0), conditionId, uint256(1)));
        bytes32 noCollectionId = keccak256(abi.encodePacked(bytes32(0), conditionId, uint256(2)));

        assertEq(yesPositionId, uint256(keccak256(abi.encodePacked(IERC20(collateralToken), yesCollectionId))));
        assertEq(noPositionId, uint256(keccak256(abi.encodePacked(IERC20(collateralToken), noCollectionId))));
    }

    function test_LibCTFSplitAndMergeUseBinaryPartition() public {
        bytes32 conditionId = keccak256("condition");
        address collateralToken = address(0x1234);

        ctfHarness.splitCollateral(address(mockConditionalTokens), collateralToken, conditionId, 25);

        assertEq(address(mockConditionalTokens.lastCollateralToken()), collateralToken);
        assertEq(mockConditionalTokens.lastParentCollectionId(), bytes32(0));
        assertEq(mockConditionalTokens.lastConditionId(), conditionId);
        assertEq(mockConditionalTokens.lastAmount(), 25);
        assertEq(mockConditionalTokens.lastPartitionLength(), 2);
        assertEq(mockConditionalTokens.lastPartitionAt(0), 1);
        assertEq(mockConditionalTokens.lastPartitionAt(1), 2);

        ctfHarness.mergeCollateral(address(mockConditionalTokens), collateralToken, conditionId, 40);

        assertEq(address(mockConditionalTokens.lastCollateralToken()), collateralToken);
        assertEq(mockConditionalTokens.lastConditionId(), conditionId);
        assertEq(mockConditionalTokens.lastAmount(), 40);
        assertEq(mockConditionalTokens.lastPartitionAt(0), 1);
        assertEq(mockConditionalTokens.lastPartitionAt(1), 2);
    }

    function test_LibCTFReportOutcomeForwardsQuestionAndPayouts() public {
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        ctfHarness.reportOutcome(address(mockConditionalTokens), keccak256("settlement"), payouts);

        assertEq(mockConditionalTokens.lastReportedQuestionId(), keccak256("settlement"));
        assertEq(mockConditionalTokens.lastReportedPayoutLength(), 2);
        assertEq(mockConditionalTokens.lastReportedPayoutAt(0), 1);
        assertEq(mockConditionalTokens.lastReportedPayoutAt(1), 0);
    }
}

contract LibParimutuelHarness {
    error ValueTooLarge();

    function setPool(
        bytes32 marketId,
        uint256 totalYesShares,
        uint256 totalNoShares,
        uint256 payoutPool,
        uint256 claimedPayout,
        uint256 claimedClaimableShares,
        bool dustSwept
    ) external {
        if (
            totalYesShares > type(uint128).max || totalNoShares > type(uint128).max || payoutPool > type(uint128).max
                || claimedPayout > type(uint128).max || claimedClaimableShares > type(uint128).max
        ) {
            revert ValueTooLarge();
        }

        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        pool.totalYesShares = uint128(totalYesShares);
        pool.totalNoShares = uint128(totalNoShares);
        pool.payoutPool = uint128(payoutPool);
        pool.claimedPayout = uint128(claimedPayout);
        pool.claimedClaimableShares = uint128(claimedClaimableShares);
        pool.dustSwept = dustSwept;
    }

    function getPool(bytes32 marketId)
        external
        view
        returns (
            uint128 totalYesShares,
            uint128 totalNoShares,
            uint128 payoutPool,
            uint128 claimedPayout,
            uint128 claimedClaimableShares,
            bool dustSwept
        )
    {
        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        totalYesShares = pool.totalYesShares;
        totalNoShares = pool.totalNoShares;
        payoutPool = pool.payoutPool;
        claimedPayout = pool.claimedPayout;
        claimedClaimableShares = pool.claimedClaimableShares;
        dustSwept = pool.dustSwept;
    }

    function effectivePayoutOutcome(bytes32 marketId, uint256 resolvedOutcome) external view returns (uint8) {
        if (resolvedOutcome > uint256(uint8(LibEveMarket.MarketOutcome.Invalid))) {
            revert ValueTooLarge();
        }

        return uint8(
            LibParimutuel.effectivePayoutOutcome(
                LibParimutuel.store().pools[marketId], LibEveMarket.MarketOutcome(resolvedOutcome)
            )
        );
    }
}

contract EventsHarness {
    function emitParimutuelMarketCreated(
        bytes32 marketId,
        address creator,
        address positionToken,
        uint256 yesPositionId,
        uint256 noPositionId,
        uint64 expiryTime,
        uint64 epochWindow
    ) external {
        emit Events.ParimutuelMarketCreated(
            marketId, creator, positionToken, yesPositionId, noPositionId, expiryTime, epochWindow
        );
    }

    function emitParimutuelSharesBought(
        bytes32 marketId,
        address buyer,
        address receiver,
        bool isYes,
        uint128 amountIn,
        uint128 sharesMinted,
        uint128 feePaid
    ) external {
        emit Events.ParimutuelSharesBought(marketId, buyer, receiver, isYes, amountIn, sharesMinted, feePaid);
    }

    function emitParimutuelPayoutClaimed(
        bytes32 marketId,
        address claimer,
        uint256 positionId,
        uint128 sharesBurned,
        uint128 payout
    ) external {
        emit Events.ParimutuelPayoutClaimed(marketId, claimer, positionId, sharesBurned, payout);
    }

    function emitParimutuelDustSwept(bytes32 marketId, address recipient, uint128 amount) external {
        emit Events.ParimutuelDustSwept(marketId, recipient, amount);
    }

    function emitParimutuelFinalized(
        bytes32 marketId,
        uint8 rawOutcome,
        uint8 effectiveOutcome,
        uint128 payoutPool,
        uint128 totalClaimableShares
    ) external {
        emit Events.ParimutuelFinalized(marketId, rawOutcome, effectiveOutcome, payoutPool, totalClaimableShares);
    }
}

contract LibEveMarketHarness {
    error ValueTooLarge();

    function setConfig(address conditionalTokens) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.config.defaultConditionalTokens = conditionalTokens;
    }

    function setParimutuelConfig(address parimutuelShareToken, uint256 entryFeeBps, uint256 minEntry) external {
        if (entryFeeBps > type(uint16).max || minEntry > type(uint128).max) {
            revert ValueTooLarge();
        }

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.parimutuelShareToken = parimutuelShareToken;
        config.parimutuelFeeConfig.entryFeeBps = uint16(entryFeeBps);
        config.parimutuelMinEntry = uint128(minEntry);
    }

    function getParimutuelConfig()
        external
        view
        returns (address parimutuelShareToken, uint16 entryFeeBps, uint128 minEntry)
    {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        parimutuelShareToken = config.parimutuelShareToken;
        entryFeeBps = config.parimutuelFeeConfig.entryFeeBps;
        minEntry = config.parimutuelMinEntry;
    }

    function setMarket(
        bytes32 marketId,
        LibEveMarket.MarketType marketType,
        address positionToken,
        address collateralToken,
        bytes32 questionId,
        bytes32 conditionId,
        uint256 yesPositionId,
        uint256 noPositionId,
        LibEveMarket.MarketState stateValue
    ) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = marketType;
        market.positionToken = positionToken;
        market.collateralToken = collateralToken;
        market.questionId = questionId;
        market.conditionId = conditionId;
        market.yesPositionId = yesPositionId;
        market.noPositionId = noPositionId;
        market.state = stateValue;
    }

    function getMarket(bytes32 marketId)
        external
        view
        returns (
            uint8 marketType,
            address positionToken,
            address collateralToken,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId,
            uint8 state
        )
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        marketType = uint8(market.marketType);
        positionToken = market.positionToken;
        collateralToken = market.collateralToken;
        questionId = market.questionId;
        conditionId = market.conditionId;
        yesPositionId = market.yesPositionId;
        noPositionId = market.noPositionId;
        state = uint8(market.state);
    }
}

contract LibCTFHarness {
    function prepareMarketCondition(address conditionalTokens, bytes32 questionId) external returns (bytes32) {
        return LibCTF.prepareMarketCondition(conditionalTokens, questionId);
    }

    function derivePositionIds(address conditionalTokens, address collateralToken, bytes32 conditionId)
        external
        view
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        return LibCTF.derivePositionIds(conditionalTokens, collateralToken, conditionId);
    }

    function splitCollateral(address conditionalTokens, address collateralToken, bytes32 conditionId, uint256 amount)
        external
    {
        LibCTF.splitCollateral(conditionalTokens, collateralToken, conditionId, amount);
    }

    function mergeCollateral(address conditionalTokens, address collateralToken, bytes32 conditionId, uint256 amount)
        external
    {
        LibCTF.mergeCollateral(conditionalTokens, collateralToken, conditionId, amount);
    }

    function reportOutcome(address conditionalTokens, bytes32 questionId, uint256[] memory payouts) external {
        LibCTF.reportOutcome(conditionalTokens, questionId, payouts);
    }
}

contract MockConditionalTokens is IConditionalTokens {
    address internal _lastOracle;
    bytes32 internal _lastQuestionId;
    uint256 internal _lastOutcomeSlotCount;

    mapping(address account => mapping(uint256 positionId => uint256 balance)) internal _balances;
    mapping(address account => mapping(address operator => bool approved)) internal _operatorApprovals;

    IERC20 internal _lastCollateralToken;
    bytes32 internal _lastParentCollectionId;
    bytes32 internal _lastConditionId;
    uint256 internal _lastAmount;
    uint256[] internal _lastPartition;

    bytes32 internal _lastReportedQuestionId;
    uint256[] internal _lastReportedPayouts;
    uint256 internal _lastReportedPayoutDenominator;

    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external {
        _lastOracle = oracle;
        _lastQuestionId = questionId;
        _lastOutcomeSlotCount = outcomeSlotCount;
    }

    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external {
        _recordPositionAction(collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external {
        _recordPositionAction(collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function redeemPositions(IERC20, bytes32, bytes32, uint256[] calldata) external {}

    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external {
        delete _lastReportedPayouts;
        _lastReportedQuestionId = questionId;
        _lastReportedPayoutDenominator = 0;

        for (uint256 index = 0; index < payouts.length; ++index) {
            _lastReportedPayouts.push(payouts[index]);
            _lastReportedPayoutDenominator += payouts[index];
        }
    }

    function payoutDenominator(bytes32) external view returns (uint256 denominator) {
        return _lastReportedPayoutDenominator;
    }

    function payoutNumerators(bytes32, uint256 slot) external view returns (uint256 numerator) {
        if (slot < _lastReportedPayouts.length) {
            return _lastReportedPayouts[slot];
        }
    }

    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256 outcomeSlotCount) {
        bytes32 recordedConditionId = keccak256(abi.encodePacked(_lastOracle, _lastQuestionId, _lastOutcomeSlotCount));
        if (conditionId == recordedConditionId) {
            return _lastOutcomeSlotCount;
        }
    }

    function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint256 positionId) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        external
        pure
        returns (bytes32 collectionId)
    {
        return keccak256(abi.encodePacked(parentCollectionId, conditionId, indexSet));
    }

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32 conditionId)
    {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    function getConditionDetails(bytes32 conditionId)
        external
        view
        returns (
            address oracle,
            bytes32 questionId,
            uint256 outcomeSlotCount,
            bool prepared,
            bool reported,
            uint256 reportedPayoutDenominator
        )
    {
        bytes32 recordedConditionId = keccak256(abi.encodePacked(_lastOracle, _lastQuestionId, _lastOutcomeSlotCount));
        prepared = conditionId == recordedConditionId && _lastOutcomeSlotCount != 0;
        if (prepared) {
            oracle = _lastOracle;
            questionId = _lastQuestionId;
            outcomeSlotCount = _lastOutcomeSlotCount;
        }
        reported = _lastReportedPayoutDenominator != 0;
        reportedPayoutDenominator = _lastReportedPayoutDenominator;
    }

    function balanceOf(address account, uint256 positionId) external view returns (uint256 balance) {
        return _balances[account][positionId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address account, address operator) external view returns (bool approved) {
        return _operatorApprovals[account][operator];
    }

    function safeTransferFrom(address from, address to, uint256 positionId, uint256 amount, bytes calldata) external {
        require(msg.sender == from || _operatorApprovals[from][msg.sender], "not approved");

        uint256 balance = _balances[from][positionId];
        require(balance >= amount, "insufficient position balance");

        _balances[from][positionId] = balance - amount;
        _balances[to][positionId] += amount;
    }

    function lastOracle() external view returns (address) {
        return _lastOracle;
    }

    function lastQuestionId() external view returns (bytes32) {
        return _lastQuestionId;
    }

    function lastOutcomeSlotCount() external view returns (uint256) {
        return _lastOutcomeSlotCount;
    }

    function lastCollateralToken() external view returns (IERC20) {
        return _lastCollateralToken;
    }

    function lastParentCollectionId() external view returns (bytes32) {
        return _lastParentCollectionId;
    }

    function lastConditionId() external view returns (bytes32) {
        return _lastConditionId;
    }

    function lastAmount() external view returns (uint256) {
        return _lastAmount;
    }

    function lastPartitionLength() external view returns (uint256) {
        return _lastPartition.length;
    }

    function lastPartitionAt(uint256 index) external view returns (uint256) {
        return _lastPartition[index];
    }

    function lastReportedQuestionId() external view returns (bytes32) {
        return _lastReportedQuestionId;
    }

    function lastReportedPayoutLength() external view returns (uint256) {
        return _lastReportedPayouts.length;
    }

    function lastReportedPayoutAt(uint256 index) external view returns (uint256) {
        return _lastReportedPayouts[index];
    }

    function _recordPositionAction(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) internal {
        delete _lastPartition;

        _lastCollateralToken = collateralToken;
        _lastParentCollectionId = parentCollectionId;
        _lastConditionId = conditionId;
        _lastAmount = amount;

        for (uint256 index = 0; index < partition.length; ++index) {
            _lastPartition.push(partition[index]);
        }
    }
}
