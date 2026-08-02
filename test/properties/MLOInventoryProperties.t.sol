// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import {MLOInventoryVault} from "../../src/MLOInventoryVault.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {LibCTF} from "../../src/libraries/LibCTF.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMLOInventory} from "../../src/libraries/LibMLOInventory.sol";
import {LibSeniorCapital} from "../../src/libraries/LibSeniorCapital.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {PlainGnosisCTFMock} from "../helpers/PlainGnosisCTFMock.sol";

contract MLOInventoryInvariantHandler is IERC1155Receiver {
    uint256 internal constant SLOT_COUNT = 6;
    uint256 internal constant MAX_ACTION_AMOUNT = 10e18;

    bytes32 public constant BUCKET_ID = keccak256("inventory-invariant-bucket");
    bytes32 public constant MARKET_ID = keccak256("inventory-invariant-market");
    bytes32 public constant QUESTION_ID = keccak256("inventory-invariant-question");

    struct ReservationSlot {
        bool active;
        uint8 outcomeIndex;
    }

    MockEveToken public immutable asset;
    PlainGnosisCTFMock public immutable conditionalTokens;
    MLOInventoryVault public immutable vault;
    bytes32 public immutable conditionId;
    uint256 public immutable yesPositionId;
    uint256 public immutable noPositionId;

    ReservationSlot[SLOT_COUNT] internal slots;

    constructor(MockEveToken asset_, PlainGnosisCTFMock conditionalTokens_, uint256 initialSeniorAssets) {
        asset = asset_;
        conditionalTokens = conditionalTokens_;
        conditionalTokens_.prepareCondition(address(this), QUESTION_ID, 2);
        conditionId = conditionalTokens_.getConditionId(address(this), QUESTION_ID, 2);
        (yesPositionId, noPositionId) =
            LibCTF.derivePositionIds(address(conditionalTokens_), address(asset_), conditionId);
        vault = new MLOInventoryVault(address(this));
        LibSeniorCapital.Storage storage senior = LibSeniorCapital.s();
        LibSeniorCapital.Epoch storage epoch = LibSeniorCapital.currentEpoch(senior);
        senior.totalPrincipal = initialSeniorAssets;
        senior.totalStored = initialSeniorAssets;
        senior.unreservedPrincipal = initialSeniorAssets;
        epoch.outstandingStored = initialSeniorAssets;
    }

    function deployCompleteSet(uint256 amountSeed) external {
        uint256 amount = 1 + amountSeed % MAX_ACTION_AMOUNT;
        LibSeniorCapital.Storage storage senior = LibSeniorCapital.s();
        if (amount > LibSeniorCapital.availableCapital(senior)) return;

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibSeniorCapital.reserveCapital(senior, BUCKET_ID, amount);
        state.mloBucketMarketSeniorReserved[BUCKET_ID][MARKET_ID] += amount;
        LibSeniorCapital.deployReservedCapital(senior, BUCKET_ID, amount);
        state.mloBucketMarketSeniorReserved[BUCKET_ID][MARKET_ID] -= amount;
        state.mloBucketMarketSeniorDebt[BUCKET_ID][MARKET_ID] += amount;

        asset.approve(address(conditionalTokens), amount);
        LibCTF.splitCollateral(address(conditionalTokens), address(asset), conditionId, amount);
        conditionalTokens.safeTransferFrom(address(this), address(vault), yesPositionId, amount, "");
        conditionalTokens.safeTransferFrom(address(this), address(vault), noPositionId, amount, "");
        state.mloBucketOutcomeInventory[BUCKET_ID][MARKET_ID][0] += amount;
        state.mloBucketOutcomeInventory[BUCKET_ID][MARKET_ID][1] += amount;
    }

    function reserveInventory(uint256 slotSeed, uint256 sideSeed, uint256 capacitySeed) external {
        uint256 slot = slotSeed % SLOT_COUNT;
        if (slots[slot].active) return;
        uint8 outcomeIndex = uint8(sideSeed % 2);
        uint256 capacity = 1 + capacitySeed % MAX_ACTION_AMOUNT;
        LibMLOInventory.reserveForCurve(LibEveMarket.store(), slot + 1, BUCKET_ID, MARKET_ID, outcomeIndex, capacity);
        slots[slot] = ReservationSlot({active: true, outcomeIndex: outcomeIndex});
    }

    function releaseInventory(uint256 slotSeed) external {
        uint256 slot = slotSeed % SLOT_COUNT;
        ReservationSlot memory reservation = slots[slot];
        if (!reservation.active) return;
        LibMLOInventory.releaseCurveInventory(
            LibEveMarket.store(), slot + 1, BUCKET_ID, MARKET_ID, reservation.outcomeIndex
        );
        delete slots[slot];
    }

    function reserveSenior(uint256 amountSeed) external {
        uint256 amount = 1 + amountSeed % MAX_ACTION_AMOUNT;
        LibSeniorCapital.Storage storage senior = LibSeniorCapital.s();
        if (amount > LibSeniorCapital.availableCapital(senior)) return;
        LibSeniorCapital.reserveCapital(senior, BUCKET_ID, amount);
        LibEveMarket.store().mloBucketMarketSeniorReserved[BUCKET_ID][MARKET_ID] += amount;
    }

    function releaseSenior(uint256 amountSeed) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 reserved = state.mloBucketMarketSeniorReserved[BUCKET_ID][MARKET_ID];
        if (reserved == 0) return;
        uint256 amount = 1 + amountSeed % reserved;
        state.mloBucketMarketSeniorReserved[BUCKET_ID][MARKET_ID] -= amount;
        LibSeniorCapital.releaseReservedCapital(LibSeniorCapital.s(), BUCKET_ID, amount);
    }

    function mergeCompleteSet(uint256 amountSeed) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 yesAvailable = LibMLOInventory.availableOutcome(state, BUCKET_ID, MARKET_ID, 0);
        uint256 noAvailable = LibMLOInventory.availableOutcome(state, BUCKET_ID, MARKET_ID, 1);
        uint256 available = yesAvailable < noAvailable ? yesAvailable : noAvailable;
        if (available == 0) return;
        uint256 amount = 1 + amountSeed % available;

        LibMLOInventory.removeCompleteSet(state, BUCKET_ID, MARKET_ID, 2, amount);
        uint256 collateralOut = vault.mergeToController(address(conditionalTokens), address(asset), conditionId, amount);
        if (collateralOut != amount) revert();
        state.mloBucketMarketSeniorDebt[BUCKET_ID][MARKET_ID] -= amount;
        LibSeniorCapital.repayActiveExposure(LibSeniorCapital.s(), BUCKET_ID, amount);
    }

    function accounting()
        external
        view
        returns (
            uint256 yesInventory,
            uint256 noInventory,
            uint256 yesReserved,
            uint256 noReserved,
            uint256 seniorReserved,
            uint256 seniorDebt,
            uint256 curveYesReserved,
            uint256 curveNoReserved
        )
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        yesInventory = state.mloBucketOutcomeInventory[BUCKET_ID][MARKET_ID][0];
        noInventory = state.mloBucketOutcomeInventory[BUCKET_ID][MARKET_ID][1];
        yesReserved = state.mloBucketOutcomeInventoryReserved[BUCKET_ID][MARKET_ID][0];
        noReserved = state.mloBucketOutcomeInventoryReserved[BUCKET_ID][MARKET_ID][1];
        seniorReserved = state.mloBucketMarketSeniorReserved[BUCKET_ID][MARKET_ID];
        seniorDebt = state.mloBucketMarketSeniorDebt[BUCKET_ID][MARKET_ID];
        for (uint256 slot; slot < SLOT_COUNT; ++slot) {
            uint256 curveReserved = state.mloCurveInventoryReserved[slot + 1];
            if (slots[slot].outcomeIndex == 0) curveYesReserved += curveReserved;
            else curveNoReserved += curveReserved;
        }
    }

    function seniorAccounting()
        external
        view
        returns (
            ISeniorCapitalFacet.SeniorCapitalBucket memory bucket,
            uint256 reserved,
            uint256 exposure,
            uint256 principal
        )
    {
        LibSeniorCapital.Storage storage senior = LibSeniorCapital.s();
        LibSeniorCapital.Bucket storage storedBucket = senior.buckets[BUCKET_ID];
        bucket = ISeniorCapitalFacet.SeniorCapitalBucket({
            reservedCapital: storedBucket.reservedCapital,
            activeExposure: storedBucket.activeExposure,
            realizedLosses: storedBucket.realizedLosses,
            fundingRevenue: storedBucket.fundingRevenue,
            riskSnapshotVersion: storedBucket.riskSnapshotVersion,
            riskSnapshotEpoch: storedBucket.riskSnapshotEpoch,
            riskSnapshotStored: storedBucket.riskSnapshotStored,
            riskSnapshotSet: storedBucket.riskSnapshotSet
        });
        reserved = senior.reservedCapital;
        exposure = senior.activeExposure;
        principal = senior.totalPrincipal;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

/// @dev The handler uses real CTF custody and internal Senior value movement while isolating bounded ledger transitions.
contract MLOInventoryProperties is StdInvariant, Test {
    uint256 internal constant INITIAL_POOL_ASSETS = 1_000e18;

    MockEveToken internal asset;
    PlainGnosisCTFMock internal conditionalTokens;
    MLOInventoryInvariantHandler internal handler;

    function setUp() public {
        asset = new MockEveToken();
        conditionalTokens = new PlainGnosisCTFMock();
        handler = new MLOInventoryInvariantHandler(asset, conditionalTokens, INITIAL_POOL_ASSETS);

        asset.mint(address(handler), INITIAL_POOL_ASSETS);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.deployCompleteSet.selector;
        selectors[1] = handler.reserveInventory.selector;
        selectors[2] = handler.releaseInventory.selector;
        selectors[3] = handler.reserveSenior.selector;
        selectors[4] = handler.releaseSenior.selector;
        selectors[5] = handler.mergeCompleteSet.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        excludeContract(address(asset));
        excludeContract(address(conditionalTokens));
        excludeContract(address(handler.vault()));
    }

    function invariant_InventoryCustodyAndReservationsReconcile() public view {
        (
            uint256 yesInventory,
            uint256 noInventory,
            uint256 yesReserved,
            uint256 noReserved,,,
            uint256 curveYesReserved,
            uint256 curveNoReserved
        ) = handler.accounting();
        assertEq(conditionalTokens.balanceOf(address(handler.vault()), handler.yesPositionId()), yesInventory);
        assertEq(conditionalTokens.balanceOf(address(handler.vault()), handler.noPositionId()), noInventory);
        assertLe(yesReserved, yesInventory);
        assertLe(noReserved, noInventory);
        assertEq(curveYesReserved, yesReserved);
        assertEq(curveNoReserved, noReserved);
        assertEq(asset.balanceOf(address(conditionalTokens)), yesInventory);
        assertEq(yesInventory, noInventory);
    }

    function invariant_SeniorPoolReservationsAndDebtReconcile() public view {
        (,,,, uint256 seniorReserved, uint256 seniorDebt,,) = handler.accounting();
        (ISeniorCapitalFacet.SeniorCapitalBucket memory bucket, uint256 reserved, uint256 exposure, uint256 principal) =
            handler.seniorAccounting();
        assertEq(bucket.reservedCapital, seniorReserved);
        assertEq(bucket.activeExposure, seniorDebt);
        assertEq(reserved, seniorReserved);
        assertEq(exposure, seniorDebt);
        assertEq(principal, INITIAL_POOL_ASSETS);
    }
}

/// @dev Storage-library smoke coverage uses a local handler because production MLO transitions require a full Diamond.
/// Real native ASK, BID, merge, and settlement value flows are covered in MLOPredictionAdapter.t.sol.
contract MLONativeInventoryInvariantHandler {
    uint8 internal constant OUTCOME_COUNT = 4;
    uint256 internal constant SLOT_COUNT = 8;
    uint256 internal constant MAX_ACTION_AMOUNT = 10e18;

    bytes32 public constant BUCKET_ID = keccak256("native-inventory-invariant-bucket");
    bytes32 public constant MARKET_ID = keccak256("native-inventory-invariant-market");

    struct ReservationSlot {
        bool active;
        uint8 outcomeIndex;
    }

    EvesPositionManager public immutable positions;
    MLOInventoryVault public immutable vault;
    ReservationSlot[SLOT_COUNT] internal slots;

    constructor() {
        positions = new EvesPositionManager(address(this), "");
        vault = new MLOInventoryVault(address(this));
    }

    function addCompleteSet(uint256 amountSeed) external {
        uint256 amount = 1 + amountSeed % MAX_ACTION_AMOUNT;
        uint256[] memory ids = positionIds();
        uint256[] memory amounts = new uint256[](OUTCOME_COUNT);
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        for (uint8 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            amounts[outcome] = amount;
            LibMLOInventory.addOutcome(state, BUCKET_ID, MARKET_ID, outcome, amount);
        }
        positions.batchMint(address(vault), ids, amounts);
    }

    function reserveInventory(uint256 slotSeed, uint256 outcomeSeed, uint256 capacitySeed) external {
        uint256 slot = slotSeed % SLOT_COUNT;
        if (slots[slot].active) return;
        uint8 outcomeIndex = uint8(outcomeSeed % OUTCOME_COUNT);
        uint256 capacity = 1 + capacitySeed % MAX_ACTION_AMOUNT;
        uint256 reserved = LibMLOInventory.reserveForCurve(
            LibEveMarket.store(), slot + 1, BUCKET_ID, MARKET_ID, outcomeIndex, capacity
        );
        if (reserved != 0) slots[slot] = ReservationSlot({active: true, outcomeIndex: outcomeIndex});
    }

    function releaseInventory(uint256 slotSeed) external {
        uint256 slot = slotSeed % SLOT_COUNT;
        ReservationSlot memory reservation = slots[slot];
        if (!reservation.active) return;
        LibMLOInventory.releaseCurveInventory(
            LibEveMarket.store(), slot + 1, BUCKET_ID, MARKET_ID, reservation.outcomeIndex
        );
        delete slots[slot];
    }

    function removeCompleteSet(uint256 amountSeed) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 available = LibMLOInventory.completeSetAvailable(state, BUCKET_ID, MARKET_ID, OUTCOME_COUNT);
        if (available == 0) return;
        uint256 amount = 1 + amountSeed % available;
        LibMLOInventory.removeCompleteSet(state, BUCKET_ID, MARKET_ID, OUTCOME_COUNT, amount);
        uint256[] memory amounts = new uint256[](OUTCOME_COUNT);
        for (uint8 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            amounts[outcome] = amount;
        }
        positions.batchBurn(address(vault), positionIds(), amounts);
    }

    function accounting()
        external
        view
        returns (uint256[] memory inventory, uint256[] memory reserved, uint256[] memory curveReserved)
    {
        inventory = new uint256[](OUTCOME_COUNT);
        reserved = new uint256[](OUTCOME_COUNT);
        curveReserved = new uint256[](OUTCOME_COUNT);
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        for (uint8 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            inventory[outcome] = state.mloBucketOutcomeInventory[BUCKET_ID][MARKET_ID][outcome];
            reserved[outcome] = state.mloBucketOutcomeInventoryReserved[BUCKET_ID][MARKET_ID][outcome];
        }
        for (uint256 slot; slot < SLOT_COUNT; ++slot) {
            if (slots[slot].active) {
                curveReserved[slots[slot].outcomeIndex] += state.mloCurveInventoryReserved[slot + 1];
            }
        }
    }

    function positionIds() public pure returns (uint256[] memory ids) {
        ids = new uint256[](OUTCOME_COUNT);
        for (uint8 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            ids[outcome] = uint256(keccak256(abi.encode("MLO_NATIVE_INVARIANT", outcome)));
        }
    }
}

contract MLONativeInventoryProperties is StdInvariant, Test {
    MLONativeInventoryInvariantHandler internal handler;

    function setUp() public {
        handler = new MLONativeInventoryInvariantHandler();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.addCompleteSet.selector;
        selectors[1] = handler.reserveInventory.selector;
        selectors[2] = handler.releaseInventory.selector;
        selectors[3] = handler.removeCompleteSet.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        excludeContract(address(handler));
        excludeContract(address(handler.positions()));
        excludeContract(address(handler.vault()));
    }

    function invariant_NativeOutcomeCustodyAndReservationsReconcile() public view {
        (uint256[] memory inventory, uint256[] memory reserved, uint256[] memory curveReserved) = handler.accounting();
        uint256[] memory ids = handler.positionIds();
        for (uint8 outcome; outcome < inventory.length; ++outcome) {
            assertEq(handler.positions().balanceOf(address(handler.vault()), ids[outcome]), inventory[outcome]);
            assertLe(reserved[outcome], inventory[outcome]);
            assertEq(curveReserved[outcome], reserved[outcome]);
        }
    }
}
