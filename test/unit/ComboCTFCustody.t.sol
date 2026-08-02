// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

import {ComboCoreFacet} from "../../src/facets/native/ComboCoreFacet.sol";
import {ComboSettlementFacet} from "../../src/facets/native/ComboSettlementFacet.sol";
import {ComboMarketFacet} from "../../src/facets/native/ComboMarketFacet.sol";
import {IComboCoreFacet} from "../../src/interfaces/IComboCoreFacet.sol";
import {IComboSettlementFacet} from "../../src/interfaces/IComboSettlementFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {EvesCTFSettlementAdapter} from "../../src/EvesCTFSettlementAdapter.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketMetadata} from "../../src/libraries/LibMarketMetadata.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {PlainGnosisCTFMock} from "../helpers/PlainGnosisCTFMock.sol";
import {DiamondFixture} from "../helpers/DiamondFixtures.sol";

contract ComboCTFCustodyStateFacet {
    function configure(address collateralToken, address positionManager, address conditionalTokens, address adapter)
        external
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.config.collateralToken = collateralToken;
        state.config.evesPositionManager = positionManager;
        state.config.defaultConditionalTokens = conditionalTokens;
        state.ctfSettlementAdapter = adapter;
    }

    function seedCTFMarket(bytes32 marketId, bytes32 questionId)
        external
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        PlainGnosisCTFMock ctf = PlainGnosisCTFMock(state.config.defaultConditionalTokens);
        ctf.prepareCondition(address(this), questionId, 2);
        conditionId = ctf.getConditionId(address(this), questionId, 2);
        yesPositionId =
            ctf.getPositionId(IERC20(state.config.collateralToken), ctf.getCollectionId(bytes32(0), conditionId, 1));
        noPositionId =
            ctf.getPositionId(IERC20(state.config.collateralToken), ctf.getCollectionId(bytes32(0), conditionId, 2));

        LibEveMarket.Market storage market = state.markets[marketId];
        market.marketId = marketId;
        market.creator = address(this);
        market.collateralToken = state.config.collateralToken;
        market.questionId = questionId;
        market.conditionId = conditionId;
        market.yesPositionId = yesPositionId;
        market.noPositionId = noPositionId;
        market.tradingStartTime = uint64(block.timestamp);
        market.expiryTime = uint64(block.timestamp + 30 days);
        market.state = LibEveMarket.MarketState.Trading;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.positionTokenType = LibEveMarket.PositionTokenType.CTF;
        market.positionToken = address(ctf);
        market.payoutUnit = 1e6;
        LibMarketMetadata.registerMarketMetadata(market, "question", "test", "test");
    }

    function reportPayouts(bytes32 questionId, uint256 yesPayout, uint256 noPayout) external {
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = yesPayout;
        payouts[1] = noPayout;
        PlainGnosisCTFMock(LibEveMarket.store().config.defaultConditionalTokens).reportPayouts(questionId, payouts);
    }

    function escrowed(uint256 positionId) external view returns (uint256) {
        return LibEveMarket.store().ctfComboEscrow[positionId];
    }
}

contract ComboCTFCustodyHandler is IERC1155Receiver {
    MockUSDG internal immutable collateral;
    EvesPositionManager internal immutable positions;
    IComboCoreFacet internal immutable combo;
    bytes32 internal immutable conditionId;
    uint256 internal immutable comboYes;
    uint256 internal immutable comboNo;

    constructor(
        MockUSDG collateral_,
        EvesPositionManager positions_,
        address diamond_,
        bytes32 conditionId_,
        uint256 comboYes_,
        uint256 comboNo_
    ) {
        collateral = collateral_;
        positions = positions_;
        combo = IComboCoreFacet(diamond_);
        conditionId = conditionId_;
        comboYes = comboYes_;
        comboNo = comboNo_;
        collateral.approve(diamond_, type(uint256).max);
    }

    function split(uint256 seed) external {
        uint256 balance = collateral.balanceOf(address(this));
        if (balance == 0) return;
        uint128 amount = uint128((seed % balance) + 1);
        combo.splitCombo(conditionId, amount, address(this), address(this));
    }

    function merge(uint256 seed) external {
        uint256 yesBalance = positions.balanceOf(address(this), comboYes);
        uint256 noBalance = positions.balanceOf(address(this), comboNo);
        uint256 available = yesBalance < noBalance ? yesBalance : noBalance;
        if (available == 0) return;
        uint128 amount = uint128((seed % available) + 1);
        combo.mergeCombo(conditionId, amount, address(this));
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
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

contract ComboCTFCustodyTest is DiamondFixture {
    uint128 internal constant AMOUNT = 100e6;

    MockUSDG internal collateral;
    PlainGnosisCTFMock internal ctf;
    EvesCTFSettlementAdapter internal adapter;
    ComboCTFCustodyStateFacet internal custodyStateFacet;
    EvesPositionManager internal positions;
    address internal alice = makeAddr("alice");

    bytes32 internal questionA = keccak256("market-a");
    bytes32 internal questionB = keccak256("market-b");
    bytes32 internal marketA = keccak256("A");
    bytes32 internal marketB = keccak256("B");
    uint256 internal aYes;
    uint256 internal aNo;
    uint256 internal bYes;
    ComboCTFCustodyHandler internal handler;

    function setUp() public override {
        super.setUp();
        collateral = new MockUSDG();
        ctf = new PlainGnosisCTFMock();
        adapter = new EvesCTFSettlementAdapter(address(ctf), address(collateral));
        custodyStateFacet = new ComboCTFCustodyStateFacet();
        _addFacet(address(new ComboCoreFacet()), _comboCoreSelectors());
        _addFacet(address(new ComboSettlementFacet()), _comboSettlementSelectors());
        _addFacet(address(new ComboMarketFacet()), _comboMarketSelectors());
        _addFacet(address(custodyStateFacet), _custodyStateSelectors());
        positions = new EvesPositionManager(address(diamond), "");
        ComboCTFCustodyStateFacet(address(diamond))
            .configure(address(collateral), address(positions), address(ctf), address(adapter));
        (, aYes, aNo) = ComboCTFCustodyStateFacet(address(diamond)).seedCTFMarket(marketA, questionA);
        (, bYes,) = ComboCTFCustodyStateFacet(address(diamond)).seedCTFMarket(marketB, questionB);
        collateral.mint(alice, 1_000e6);
        uint256[] memory invariantLegs = _single(aYes);
        (bytes32 invariantCondition, uint256 invariantYes, uint256 invariantNo) =
            IComboCoreFacet(address(diamond)).prepareComboCondition(invariantLegs);
        handler = new ComboCTFCustodyHandler(
            collateral, positions, address(diamond), invariantCondition, invariantYes, invariantNo
        );
        collateral.mint(address(handler), 1_000e6);
        targetContract(address(handler));
    }

    function invariant_CTFEscrowMatchesDiamondInventory() public view {
        assertEq(ctf.balanceOf(address(diamond), aYes), ComboCTFCustodyStateFacet(address(diamond)).escrowed(aYes));
        assertEq(ctf.balanceOf(address(diamond), aNo), ComboCTFCustodyStateFacet(address(diamond)).escrowed(aNo));
    }

    function invariant_CollateralRemainsAccountedFor() public view {
        uint256 accounted = collateral.balanceOf(alice) + collateral.balanceOf(address(handler))
            + collateral.balanceOf(address(diamond)) + collateral.balanceOf(address(adapter))
            + collateral.balanceOf(address(ctf));
        assertEq(accounted, collateral.totalSupply());
    }

    function test_WrapAndUnwrapTransfersCanonicalCTFBacking() public {
        _splitUnderlying(questionA, AMOUNT);
        uint256[] memory legs = _single(aYes);
        (, uint256 comboYes,) = IComboCoreFacet(address(diamond)).prepareComboCondition(legs);

        vm.startPrank(alice);
        ctf.setApprovalForAll(address(diamond), true);
        IComboCoreFacet(address(diamond)).wrapCombo(aYes, AMOUNT, alice);
        assertEq(ctf.balanceOf(address(diamond), aYes), AMOUNT);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aYes), AMOUNT);
        IComboCoreFacet(address(diamond)).unwrapCombo(comboYes, AMOUNT, alice);
        vm.stopPrank();

        assertEq(ctf.balanceOf(alice, aYes), AMOUNT);
        assertEq(ctf.balanceOf(address(diamond), aYes), 0);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aYes), 0);
    }

    function test_SingleLegSplitAndMergeRoundTripUsesCTFEscrow() public {
        uint256[] memory legs = _single(aYes);
        (bytes32 conditionId, uint256 comboYes, uint256 comboNo) =
            IComboCoreFacet(address(diamond)).prepareComboCondition(legs);
        uint256 beforeBalance = collateral.balanceOf(alice);

        vm.startPrank(alice);
        collateral.approve(address(diamond), AMOUNT);
        IComboCoreFacet(address(diamond)).splitCombo(conditionId, AMOUNT, alice, alice);
        assertEq(positions.balanceOf(alice, comboYes), AMOUNT);
        assertEq(positions.balanceOf(alice, comboNo), AMOUNT);
        assertEq(ctf.balanceOf(address(diamond), aYes), AMOUNT);
        assertEq(ctf.balanceOf(address(diamond), aNo), AMOUNT);
        IComboCoreFacet(address(diamond)).mergeCombo(conditionId, AMOUNT, alice);
        vm.stopPrank();

        assertEq(collateral.balanceOf(alice), beforeBalance);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aYes), 0);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aNo), 0);
    }

    function test_PartialSingleLegRedemptionConsumesOnlyRequestedCTFBacking() public {
        uint256[] memory legs = _single(aYes);
        (bytes32 conditionId, uint256 comboYes,) = IComboCoreFacet(address(diamond)).prepareComboCondition(legs);
        vm.startPrank(alice);
        collateral.approve(address(diamond), AMOUNT);
        IComboCoreFacet(address(diamond)).splitCombo(conditionId, AMOUNT, alice, alice);
        vm.stopPrank();
        ComboCTFCustodyStateFacet(address(diamond)).reportPayouts(questionA, 1, 0);

        uint128 redeemAmount = 10e6;
        uint256 beforeBalance = collateral.balanceOf(alice);
        vm.prank(alice);
        uint128 payout = IComboSettlementFacet(address(diamond)).redeemCombo(comboYes, redeemAmount, alice);

        assertEq(payout, redeemAmount);
        assertEq(collateral.balanceOf(alice) - beforeBalance, redeemAmount);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aYes), AMOUNT - redeemAmount);
        assertEq(ctf.balanceOf(address(diamond), aYes), AMOUNT - redeemAmount);
        assertEq(positions.balanceOf(alice, comboYes), AMOUNT - redeemAmount);
    }

    function test_MultiLegConjunctionRedeemsFromDiamondCollateralBacking() public {
        uint256[] memory legs = aYes < bYes ? _pair(aYes, bYes) : _pair(bYes, aYes);
        (bytes32 conditionId, uint256 comboYes,) = IComboCoreFacet(address(diamond)).prepareComboCondition(legs);
        vm.startPrank(alice);
        collateral.approve(address(diamond), AMOUNT);
        IComboCoreFacet(address(diamond)).splitCombo(conditionId, AMOUNT, alice, alice);
        vm.stopPrank();
        ComboCTFCustodyStateFacet(address(diamond)).reportPayouts(questionA, 1, 0);
        ComboCTFCustodyStateFacet(address(diamond)).reportPayouts(questionB, 1, 0);

        uint256 beforeBalance = collateral.balanceOf(alice);
        vm.prank(alice);
        uint128 payout = IComboSettlementFacet(address(diamond)).redeemCombo(comboYes, AMOUNT, alice);

        assertEq(payout, AMOUNT);
        assertEq(collateral.balanceOf(alice) - beforeBalance, AMOUNT);
    }

    function test_ComboMarketBuildsBooksFromCanonicalCTFMarketPositions() public {
        bytes32[] memory marketIds = new bytes32[](2);
        marketIds[0] = marketA;
        marketIds[1] = marketB;
        bool[] memory yesLegs = new bool[](2);
        yesLegs[0] = true;
        yesLegs[1] = true;

        vm.prank(alice);
        IComboMarketFacet.ComboMarketPreparation memory preparation =
            IComboMarketFacet(address(diamond)).createComboMarket(marketIds, yesLegs);
        assertTrue(preparation.conditionId != bytes32(0));
        assertTrue(preparation.yesBookId != bytes32(0));
        assertTrue(preparation.noBookId != bytes32(0));
        assertEq(
            IComboMarketFacet(address(diamond)).getComboBook(address(positions), preparation.yesPositionId),
            preparation.yesBookId
        );
    }

    function testFuzz_SingleLegSplitMergePreservesCollateral(uint96 rawAmount) public {
        uint128 amount = uint128(bound(rawAmount, 1, 1_000e6));
        uint256[] memory legs = _single(aYes);
        (bytes32 conditionId,,) = IComboCoreFacet(address(diamond)).prepareComboCondition(legs);
        uint256 beforeBalance = collateral.balanceOf(alice);

        vm.startPrank(alice);
        collateral.approve(address(diamond), amount);
        IComboCoreFacet(address(diamond)).splitCombo(conditionId, amount, alice, alice);
        IComboCoreFacet(address(diamond)).mergeCombo(conditionId, amount, alice);
        vm.stopPrank();

        assertEq(collateral.balanceOf(alice), beforeBalance);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aYes), 0);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aNo), 0);
    }

    function testFuzz_PartialRedemptionPreservesUnredeemedEscrow(uint96 rawRedeemAmount) public {
        uint128 redeemAmount = uint128(bound(rawRedeemAmount, 1, AMOUNT));
        uint256[] memory legs = _single(aYes);
        (bytes32 conditionId, uint256 comboYes,) = IComboCoreFacet(address(diamond)).prepareComboCondition(legs);
        vm.startPrank(alice);
        collateral.approve(address(diamond), AMOUNT);
        IComboCoreFacet(address(diamond)).splitCombo(conditionId, AMOUNT, alice, alice);
        vm.stopPrank();
        ComboCTFCustodyStateFacet(address(diamond)).reportPayouts(questionA, 1, 0);

        vm.prank(alice);
        uint128 payout = IComboSettlementFacet(address(diamond)).redeemCombo(comboYes, redeemAmount, alice);

        assertEq(payout, redeemAmount);
        assertEq(ComboCTFCustodyStateFacet(address(diamond)).escrowed(aYes), AMOUNT - redeemAmount);
        assertEq(ctf.balanceOf(address(diamond), aYes), AMOUNT - redeemAmount);
    }

    function _splitUnderlying(bytes32, uint128 amount) internal {
        vm.startPrank(alice);
        collateral.approve(address(adapter), amount);
        adapter.splitPosition(ctf.getConditionId(address(diamond), questionA, 2), amount);
        vm.stopPrank();
    }

    function _single(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }

    function _pair(uint256 first, uint256 second) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = first;
        values[1] = second;
    }

    function _comboCoreSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IComboCoreFacet.prepareComboCondition.selector;
        selectors[1] = IComboCoreFacet.splitCombo.selector;
        selectors[2] = IComboCoreFacet.mergeCombo.selector;
        selectors[3] = IComboCoreFacet.wrapCombo.selector;
        selectors[4] = IComboCoreFacet.unwrapCombo.selector;
        selectors[5] = IComboCoreFacet.getComboCondition.selector;
        selectors[6] = IComboCoreFacet.getComboLegs.selector;
    }

    function _comboSettlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IComboSettlementFacet.redeemCombo.selector;
        selectors[1] = IComboSettlementFacet.getComboPayout.selector;
    }

    function _comboMarketSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.createComboMarketFromLegs.selector;
        selectors[2] = IComboMarketFacet.computeComboBookId.selector;
        selectors[3] = IComboMarketFacet.getComboMarket.selector;
        selectors[4] = IComboMarketFacet.getComboBook.selector;
    }

    function _custodyStateSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ComboCTFCustodyStateFacet.configure.selector;
        selectors[1] = ComboCTFCustodyStateFacet.seedCTFMarket.selector;
        selectors[2] = ComboCTFCustodyStateFacet.reportPayouts.selector;
        selectors[3] = ComboCTFCustodyStateFacet.escrowed.selector;
    }
}
