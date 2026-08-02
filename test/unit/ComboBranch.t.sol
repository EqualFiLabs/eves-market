// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {ComboBranchFacet} from "../../src/facets/native/ComboBranchFacet.sol";
import {IEvesPositionManager} from "../../src/interfaces/IEvesPositionManager.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../src/libraries/LibNativePosition.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";

import {MockUSDC} from "../helpers/MockUSDC.sol";

contract ComboBranchHarness is ComboBranchFacet {
    function configure(address collateralToken, address positionManager) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.collateralToken = collateralToken;
        config.evesPositionManager = positionManager;
    }

    function seedBinaryLegs(bytes32 marketId, address collateralToken)
        external
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId)
    {
        return this.seedBinaryLegsWithWindow(marketId, collateralToken, block.timestamp, block.timestamp + 30 days);
    }

    function seedBinaryLegsWithWindow(
        bytes32 marketId,
        address collateralToken,
        uint256 tradingStartTime,
        uint256 expiryTime
    ) external returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) {
        require(tradingStartTime <= type(uint64).max);
        require(expiryTime <= type(uint64).max);
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.collateralToken = collateralToken;
        market.state = LibEveMarket.MarketState.Trading;
        market.tradingStartTime = uint64(tradingStartTime);
        market.expiryTime = uint64(expiryTime);

        conditionId = LibNativePosition.binaryConditionIdFor(marketId);
        yesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_BINARY, conditionId, LibNativePosition.OUTCOME_YES
        );
        noPositionId =
            LibNativePosition.positionIdFor(LibNativePosition.MODULE_BINARY, conditionId, LibNativePosition.OUTCOME_NO);

        LibEveMarket.store().nativePositionMetadata[yesPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_BINARY,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_YES,
            marketId: marketId,
            exists: true
        });
        LibEveMarket.store().nativePositionMetadata[noPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_BINARY,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_NO,
            marketId: marketId,
            exists: true
        });
    }

    function seedCombo(uint256[] calldata legs) external returns (bytes32 conditionId, uint256 yesId, uint256 noId) {
        uint256[] memory memoryLegs = new uint256[](legs.length);
        for (uint256 index; index < legs.length; ++index) {
            memoryLegs[index] = legs[index];
        }
        conditionId = LibNativePosition.comboConditionIdFor(memoryLegs);
        yesId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
        );
        noId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
        );

        LibEveMarket.ComboCondition storage condition = LibEveMarket.store().comboConditions[conditionId];
        condition.conditionId = conditionId;
        condition.legsHash = keccak256(abi.encode(memoryLegs));
        condition.legCount = uint16(legs.length);
        condition.preparedAt = uint64(block.timestamp);
        condition.exists = true;
        for (uint256 index; index < legs.length; ++index) {
            LibEveMarket.store().comboConditionLegs[conditionId].push(legs[index]);
        }

        LibEveMarket.store().nativePositionMetadata[yesId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_COMBINATORIAL,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_YES,
            marketId: bytes32(0),
            exists: true
        });
        LibEveMarket.store().nativePositionMetadata[noId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_COMBINATORIAL,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_NO,
            marketId: bytes32(0),
            exists: true
        });
    }

    function comboLegCount(bytes32 conditionId) external view returns (uint256) {
        return LibEveMarket.store().comboConditionLegs[conditionId].length;
    }

    function mintPosition(address to, uint256 positionId, uint128 amount) external {
        IEvesPositionManager(LibEveMarket.store().config.evesPositionManager).mint(to, positionId, amount);
    }
}

contract ComboBranchTest is Test {
    ComboBranchHarness internal branch;
    EvesPositionManager internal positions;
    MockUSDC internal collateral;

    address internal trader = makeAddr("trader");
    address internal receiver = makeAddr("receiver");

    bytes32 internal constant MARKET_A = bytes32(uint256(0xA));
    bytes32 internal constant MARKET_B = bytes32(uint256(0xB));
    bytes32 internal constant MARKET_C = bytes32(uint256(0xC));
    uint128 internal constant AMOUNT = 100e6;

    bytes32 internal conditionA;
    bytes32 internal conditionC;
    uint256 internal aYes;
    uint256 internal aNo;
    uint256 internal bYes;
    uint256 internal bNo;
    uint256 internal cYes;
    uint256 internal cNo;
    uint256 internal parentYes;
    uint256 internal parentNo;

    function setUp() public {
        branch = new ComboBranchHarness();
        positions = new EvesPositionManager(address(branch), "");
        collateral = new MockUSDC();
        branch.configure(address(collateral), address(positions));

        (conditionA, aYes, aNo) = branch.seedBinaryLegs(MARKET_A, address(collateral));
        (, bYes, bNo) = branch.seedBinaryLegs(MARKET_B, address(collateral));
        (conditionC, cYes, cNo) = branch.seedBinaryLegs(MARKET_C, address(collateral));

        uint256[] memory parentLegs = _sorted(aYes, bYes);
        (, parentYes, parentNo) = branch.seedCombo(parentLegs);
    }

    function test_SplitComboOnConditionBurnsParentAndMintsChildBranches() public {
        branch.mintPosition(trader, parentYes, AMOUNT);

        (uint256 expectedChildYes, uint256 expectedChildNo) = _expectedChildPositions(conditionC);

        vm.prank(trader);
        (uint256 childYes, uint256 childNo) =
            branch.splitComboOnCondition(parentYes, conditionC, AMOUNT, trader, receiver);

        assertEq(childYes, expectedChildYes);
        assertEq(childNo, expectedChildNo);
        assertEq(positions.balanceOf(trader, parentYes), 0);
        assertEq(positions.balanceOf(trader, childYes), AMOUNT);
        assertEq(positions.balanceOf(receiver, childNo), AMOUNT);
        assertEq(branch.comboLegCount(_conditionForChild(cYes)), 3);
        assertEq(branch.comboLegCount(_conditionForChild(cNo)), 3);
    }

    function test_MergeComboOnConditionBurnsChildBranchesAndMintsParent() public {
        branch.mintPosition(trader, parentYes, AMOUNT);

        vm.prank(trader);
        (uint256 childYes, uint256 childNo) =
            branch.splitComboOnCondition(parentYes, conditionC, AMOUNT, trader, trader);

        vm.prank(trader);
        uint256 parentOut = branch.mergeComboOnCondition(parentYes, conditionC, AMOUNT, receiver);

        assertEq(parentOut, parentYes);
        assertEq(positions.balanceOf(trader, childYes), 0);
        assertEq(positions.balanceOf(trader, childNo), 0);
        assertEq(positions.balanceOf(receiver, parentYes), AMOUNT);
    }

    function test_RevertWhen_ParentIsComboNo() public {
        branch.mintPosition(trader, parentNo, AMOUNT);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboParentYesRequired.selector, parentNo));
        branch.splitComboOnCondition(parentNo, conditionC, AMOUNT, trader, trader);
    }

    function test_RevertWhen_ConditionAlreadyPresent() public {
        branch.mintPosition(trader, parentYes, AMOUNT);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboConditionAlreadyPresent.selector, conditionA));
        branch.splitComboOnCondition(parentYes, conditionA, AMOUNT, trader, trader);
    }

    function test_RevertWhen_SplitOnConditionBeforeNewLegStarts() public {
        bytes32 futureMarket = bytes32(uint256(0xD));
        (bytes32 futureCondition,,) = branch.seedBinaryLegsWithWindow(
            futureMarket, address(collateral), block.timestamp + 1 days, block.timestamp + 2 days
        );
        branch.mintPosition(trader, parentYes, AMOUNT);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboLegMarketNotStarted.selector, futureMarket));
        branch.splitComboOnCondition(parentYes, futureCondition, AMOUNT, trader, trader);
    }

    function test_RevertWhen_SplitOnConditionWithDifferentCollateral() public {
        MockUSDC otherCollateral = new MockUSDC();
        bytes32 otherMarket = bytes32(uint256(0xE));
        (bytes32 otherCondition,,) = branch.seedBinaryLegs(otherMarket, address(otherCollateral));
        branch.mintPosition(trader, parentYes, AMOUNT);

        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ComboCollateralMismatch.selector, address(collateral), address(otherCollateral)
            )
        );
        branch.splitComboOnCondition(parentYes, otherCondition, AMOUNT, trader, trader);
    }

    function test_MergeComboOnConditionAfterNewLegExpiryStillRebundles() public {
        bytes32 shortMarket = bytes32(uint256(0xF));
        (bytes32 shortCondition,,) =
            branch.seedBinaryLegsWithWindow(shortMarket, address(collateral), block.timestamp, block.timestamp + 1 days);
        branch.mintPosition(trader, parentYes, AMOUNT);

        vm.prank(trader);
        (uint256 childYes, uint256 childNo) =
            branch.splitComboOnCondition(parentYes, shortCondition, AMOUNT, trader, trader);

        vm.warp(block.timestamp + 1 days);

        vm.prank(trader);
        uint256 parentOut = branch.mergeComboOnCondition(parentYes, shortCondition, AMOUNT, receiver);

        assertEq(parentOut, parentYes);
        assertEq(positions.balanceOf(trader, childYes), 0);
        assertEq(positions.balanceOf(trader, childNo), 0);
        assertEq(positions.balanceOf(receiver, parentYes), AMOUNT);
    }

    function test_ExtractComboNoLegMintsReducedNoAndResidualYes() public {
        branch.mintPosition(trader, parentNo, AMOUNT);

        uint256[] memory parentLegs = _sorted(aYes, bYes);
        uint256 extractedLeg = parentLegs[0];
        (uint256 reducedNo, uint256 residualYes) = _expectedExtractionPositions(0);

        vm.prank(trader);
        (uint256 reducedOut, uint256 residualOut) = branch.extractComboNoLeg(parentNo, 0, AMOUNT, trader, receiver);

        assertEq(reducedOut, reducedNo);
        assertEq(residualOut, residualYes);
        assertEq(positions.balanceOf(trader, parentNo), 0);
        assertEq(positions.balanceOf(trader, reducedNo), AMOUNT);
        assertEq(positions.balanceOf(receiver, residualYes), AMOUNT);
        assertTrue(extractedLeg == aYes || extractedLeg == bYes);
    }

    function test_InjectComboNoLegMergesReducedNoAndResidualYesBackToFullNo() public {
        branch.mintPosition(trader, parentNo, AMOUNT);

        vm.prank(trader);
        (uint256 reducedNo, uint256 residualYes) = branch.extractComboNoLeg(parentNo, 0, AMOUNT, trader, trader);

        vm.prank(trader);
        uint256 fullNoOut = branch.injectComboNoLeg(parentNo, 0, AMOUNT, receiver);

        assertEq(fullNoOut, parentNo);
        assertEq(positions.balanceOf(trader, reducedNo), 0);
        assertEq(positions.balanceOf(trader, residualYes), 0);
        assertEq(positions.balanceOf(receiver, parentNo), AMOUNT);
    }

    function test_ConvertComboNoToYesBasketMintsCanonicalBasket() public {
        branch.mintPosition(trader, parentNo, AMOUNT);

        uint256[] memory expectedBasket = _expectedYesBasketPositions();
        address[] memory receivers = new address[](2);
        receivers[0] = trader;
        receivers[1] = receiver;

        vm.prank(trader);
        uint256[] memory basket = branch.convertComboNoToYesBasket(parentNo, AMOUNT, receivers);

        assertEq(basket.length, expectedBasket.length);
        assertEq(basket[0], expectedBasket[0]);
        assertEq(basket[1], expectedBasket[1]);
        assertEq(positions.balanceOf(trader, parentNo), 0);
        assertEq(positions.balanceOf(trader, expectedBasket[0]), AMOUNT);
        assertEq(positions.balanceOf(receiver, expectedBasket[1]), AMOUNT);
    }

    function test_ThreeLegComboNoBasketRoundTripsCanonicalBranches() public {
        uint256[] memory fullLegs = _sorted(aYes, bYes, cYes);
        (, uint256 fullYes, uint256 fullNo) = branch.seedCombo(fullLegs);
        branch.mintPosition(trader, fullNo, AMOUNT);

        uint256[] memory expectedBasket = _expectedYesBasketPositions(fullLegs);
        address[] memory receivers = new address[](3);
        receivers[0] = trader;
        receivers[1] = trader;
        receivers[2] = trader;

        vm.prank(trader);
        uint256[] memory basket = branch.convertComboNoToYesBasket(fullNo, AMOUNT, receivers);

        assertEq(basket.length, 3);
        for (uint256 index; index < basket.length; ++index) {
            assertEq(basket[index], expectedBasket[index]);
            assertEq(positions.balanceOf(trader, basket[index]), AMOUNT);
        }
        assertEq(positions.balanceOf(trader, fullNo), 0);
        assertEq(positions.balanceOf(trader, fullYes), 0);

        vm.prank(trader);
        uint256 fullNoOut = branch.mergeComboNoFromYesBasket(fullNo, AMOUNT, receiver);

        assertEq(fullNoOut, fullNo);
        for (uint256 index; index < basket.length; ++index) {
            assertEq(positions.balanceOf(trader, basket[index]), 0);
        }
        assertEq(positions.balanceOf(receiver, fullNo), AMOUNT);
    }

    function test_MergeComboNoFromYesBasketBurnsBasketAndMintsFullNo() public {
        branch.mintPosition(trader, parentNo, AMOUNT);

        address[] memory receivers = new address[](2);
        receivers[0] = trader;
        receivers[1] = trader;

        vm.prank(trader);
        uint256[] memory basket = branch.convertComboNoToYesBasket(parentNo, AMOUNT, receivers);

        vm.prank(trader);
        uint256 fullNoOut = branch.mergeComboNoFromYesBasket(parentNo, AMOUNT, receiver);

        assertEq(fullNoOut, parentNo);
        assertEq(positions.balanceOf(trader, basket[0]), 0);
        assertEq(positions.balanceOf(trader, basket[1]), 0);
        assertEq(positions.balanceOf(receiver, parentNo), AMOUNT);
    }

    function test_RevertWhen_ExtractFromComboYes() public {
        branch.mintPosition(trader, parentYes, AMOUNT);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboNoPositionRequired.selector, parentYes));
        branch.extractComboNoLeg(parentYes, 0, AMOUNT, trader, trader);
    }

    function test_RevertWhen_ExtractLegIndexOutOfRange() public {
        branch.mintPosition(trader, parentNo, AMOUNT);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboLegIndexOutOfRange.selector, uint256(2), uint256(2)));
        branch.extractComboNoLeg(parentNo, 2, AMOUNT, trader, trader);
    }

    function test_RevertWhen_ConvertBasketReceiverCountMismatch() public {
        branch.mintPosition(trader, parentNo, AMOUNT);

        address[] memory receivers = new address[](1);
        receivers[0] = trader;

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, uint256(2), uint256(1)));
        branch.convertComboNoToYesBasket(parentNo, AMOUNT, receivers);
    }

    function _expectedChildPositions(bytes32 binaryConditionId)
        internal
        view
        returns (uint256 childYes, uint256 childNo)
    {
        childYes = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL,
            _conditionForChild(
                LibNativePosition.positionIdFor(
                    LibNativePosition.MODULE_BINARY, binaryConditionId, LibNativePosition.OUTCOME_YES
                )
            ),
            LibNativePosition.OUTCOME_YES
        );
        childNo = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL,
            _conditionForChild(
                LibNativePosition.positionIdFor(
                    LibNativePosition.MODULE_BINARY, binaryConditionId, LibNativePosition.OUTCOME_NO
                )
            ),
            LibNativePosition.OUTCOME_YES
        );
    }

    function _expectedExtractionPositions(uint256 legIndex)
        internal
        view
        returns (uint256 reducedNo, uint256 residualYes)
    {
        uint256[] memory parentLegs = _sorted(aYes, bYes);
        uint256 extractedLeg = parentLegs[legIndex];
        uint256 remainingLeg = parentLegs[legIndex == 0 ? 1 : 0];

        uint256[] memory reducedLegs = new uint256[](1);
        reducedLegs[0] = remainingLeg;

        uint256 flippedExtracted = extractedLeg == aYes ? aNo : bNo;
        uint256[] memory residualLegs = _sorted(remainingLeg, flippedExtracted);

        reducedNo = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL,
            LibNativePosition.comboConditionIdFor(reducedLegs),
            LibNativePosition.OUTCOME_NO
        );
        residualYes = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL,
            LibNativePosition.comboConditionIdFor(residualLegs),
            LibNativePosition.OUTCOME_YES
        );
    }

    function _expectedYesBasketPositions() internal view returns (uint256[] memory basket) {
        uint256[] memory parentLegs = _sorted(aYes, bYes);
        uint256 firstFlip = parentLegs[0] == aYes ? aNo : bNo;
        uint256 secondFlip = parentLegs[1] == aYes ? aNo : bNo;

        uint256[] memory firstLegs = new uint256[](1);
        firstLegs[0] = firstFlip;

        uint256[] memory secondLegs = _sorted(parentLegs[0], secondFlip);

        basket = new uint256[](2);
        basket[0] = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL,
            LibNativePosition.comboConditionIdFor(firstLegs),
            LibNativePosition.OUTCOME_YES
        );
        basket[1] = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL,
            LibNativePosition.comboConditionIdFor(secondLegs),
            LibNativePosition.OUTCOME_YES
        );
    }

    function _expectedYesBasketPositions(uint256[] memory fullLegs) internal view returns (uint256[] memory basket) {
        basket = new uint256[](fullLegs.length);
        for (uint256 terminalIndex; terminalIndex < fullLegs.length; ++terminalIndex) {
            uint256[] memory basketLegs = new uint256[](terminalIndex + 1);
            for (uint256 legIndex; legIndex <= terminalIndex; ++legIndex) {
                basketLegs[legIndex] = legIndex == terminalIndex ? _flipLeg(fullLegs[legIndex]) : fullLegs[legIndex];
            }
            _sortInPlace(basketLegs);
            basket[terminalIndex] = LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL,
                LibNativePosition.comboConditionIdFor(basketLegs),
                LibNativePosition.OUTCOME_YES
            );
        }
    }

    function _flipLeg(uint256 leg) internal view returns (uint256) {
        if (leg == aYes) return aNo;
        if (leg == aNo) return aYes;
        if (leg == bYes) return bNo;
        if (leg == bNo) return bYes;
        if (leg == cYes) return cNo;
        if (leg == cNo) return cYes;
        revert("unknown leg");
    }

    function _conditionForChild(uint256 addedLeg) internal view returns (bytes32) {
        uint256[] memory parentLegs = _sorted(aYes, bYes);
        uint256[] memory childLegs = new uint256[](3);
        childLegs[0] = parentLegs[0];
        childLegs[1] = parentLegs[1];
        childLegs[2] = addedLeg;
        _sortInPlace(childLegs);
        return LibNativePosition.comboConditionIdFor(childLegs);
    }

    function _sorted(uint256 first, uint256 second, uint256 third) internal pure returns (uint256[] memory legs) {
        legs = new uint256[](3);
        legs[0] = first;
        legs[1] = second;
        legs[2] = third;
        _sortInPlace(legs);
    }

    function _sorted(uint256 first, uint256 second) internal pure returns (uint256[] memory legs) {
        legs = new uint256[](2);
        if (first < second) {
            legs[0] = first;
            legs[1] = second;
        } else {
            legs[0] = second;
            legs[1] = first;
        }
    }

    function _sortInPlace(uint256[] memory legs) internal pure {
        for (uint256 i; i < legs.length; ++i) {
            for (uint256 j = i + 1; j < legs.length; ++j) {
                if (legs[j] < legs[i]) {
                    uint256 tmp = legs[i];
                    legs[i] = legs[j];
                    legs[j] = tmp;
                }
            }
        }
    }
}
