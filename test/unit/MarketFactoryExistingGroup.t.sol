// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";

import {CurveTradingFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract MarketFactoryExistingGroupTest is CurveTradingFixture {
    function test_CreateMarketGroupFromExistingLinksMetadataOnly() public {
        bytes32 firstMarketId = _createCreatorMarket("existing group first", 7 days);
        bytes32 secondMarketId = _createCreatorMarket("existing group second", 8 days);
        MarketFactoryTypes.MarketInfo memory beforeInfo =
            IMarketFactoryFacet(address(diamond)).getMarketInfo(firstMarketId);

        MarketFactoryTypes.ExistingMarketGroupCreationParams memory params =
            _existingGroupParams("gamma-event", "Gamma Event", 2);
        params.markets[0] = _existingMarketParam(firstMarketId, "First", 1);
        params.markets[1] = _existingMarketParam(secondMarketId, "Second", 2);

        vm.prank(creator);
        bytes32 groupId = IMarketFactoryFacet(address(diamond)).createMarketGroupFromExisting(params);

        MarketFactoryTypes.MarketGroupView memory group = IMarketFactoryFacet(address(diamond)).getMarketGroup(groupId);
        bytes32[] memory marketIds = IMarketFactoryFacet(address(diamond)).getMarketGroupMarkets(groupId);
        MarketFactoryTypes.GroupMarketDisplayView memory secondDisplay =
            IMarketFactoryFacet(address(diamond)).getGroupMarketDisplay(groupId, secondMarketId);
        MarketFactoryTypes.MarketInfo memory afterInfo =
            IMarketFactoryFacet(address(diamond)).getMarketInfo(firstMarketId);

        assertTrue(group.exists);
        assertEq(group.creator, creator);
        assertEq(group.marketCount, 2);
        assertEq(marketIds.length, 2);
        assertEq(marketIds[0], firstMarketId);
        assertEq(marketIds[1], secondMarketId);
        assertTrue(secondDisplay.exists);
        assertEq(secondDisplay.sortOrder, 1);
        assertEq(secondDisplay.displayLabel, "Second");
        assertEq(afterInfo.totalCurveCount, beforeInfo.totalCurveCount);
        assertEq(afterInfo.creationFeePaid, beforeInfo.creationFeePaid);
        assertEq(afterInfo.tradingStartTime, beforeInfo.tradingStartTime);
    }

    function test_AddMarketsToGroupAppendsContiguously() public {
        bytes32 firstMarketId = _createCreatorMarket("append group first", 7 days);
        bytes32 secondMarketId = _createCreatorMarket("append group second", 8 days);
        bytes32 thirdMarketId = _createCreatorMarket("append group third", 9 days);

        MarketFactoryTypes.ExistingMarketGroupCreationParams memory params =
            _existingGroupParams("append-event", "Append Event", 1);
        params.markets[0] = _existingMarketParam(firstMarketId, "First", 1);

        vm.prank(creator);
        bytes32 groupId = IMarketFactoryFacet(address(diamond)).createMarketGroupFromExisting(params);

        MarketFactoryTypes.ExistingGroupMarketParam[] memory appendMarkets =
            new MarketFactoryTypes.ExistingGroupMarketParam[](2);
        appendMarkets[0] = _existingMarketParam(secondMarketId, "Second", 2);
        appendMarkets[1] = _existingMarketParam(thirdMarketId, "Third", 3);

        vm.prank(creator);
        IMarketFactoryFacet(address(diamond)).addMarketsToGroup(groupId, appendMarkets);

        bytes32[] memory marketIds = IMarketFactoryFacet(address(diamond)).getMarketGroupMarkets(groupId);
        MarketFactoryTypes.GroupMarketDisplayView memory thirdDisplay =
            IMarketFactoryFacet(address(diamond)).getGroupMarketDisplay(groupId, thirdMarketId);

        assertEq(marketIds.length, 3);
        assertEq(marketIds[0], firstMarketId);
        assertEq(marketIds[1], secondMarketId);
        assertEq(marketIds[2], thirdMarketId);
        assertEq(thirdDisplay.sortOrder, 2);
        assertEq(thirdDisplay.lineValueBps, 3);
    }

    function test_CreateMarketGroupFromExistingRejectsDuplicatesAndWrongCreator() public {
        bytes32 creatorMarketId = _createCreatorMarket("duplicate existing group", 7 days);
        bytes32 makerMarketId = _createMakerMarket("wrong creator existing group", 8 days);

        MarketFactoryTypes.ExistingMarketGroupCreationParams memory duplicateParams =
            _existingGroupParams("duplicate-event", "Duplicate Event", 2);
        duplicateParams.markets[0] = _existingMarketParam(creatorMarketId, "First", 1);
        duplicateParams.markets[1] = _existingMarketParam(creatorMarketId, "First Again", 2);

        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateGroupMarket.selector, bytes32(0), creatorMarketId));
        vm.prank(creator);
        IMarketFactoryFacet(address(diamond)).createMarketGroupFromExisting(duplicateParams);

        MarketFactoryTypes.ExistingMarketGroupCreationParams memory wrongCreatorParams =
            _existingGroupParams("wrong-creator-event", "Wrong Creator Event", 2);
        wrongCreatorParams.markets[0] = _existingMarketParam(creatorMarketId, "Creator", 1);
        wrongCreatorParams.markets[1] = _existingMarketParam(makerMarketId, "Maker", 2);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotMarketCreator.selector, creator, maker));
        vm.prank(creator);
        IMarketFactoryFacet(address(diamond)).createMarketGroupFromExisting(wrongCreatorParams);
    }

    function test_GroupIdChangesWhenFullMarketListChanges() public {
        bytes32 firstMarketId = _createCreatorMarket("hash group first", 7 days);
        bytes32 secondMarketId = _createCreatorMarket("hash group second", 8 days);

        MarketFactoryTypes.ExistingMarketGroupCreationParams memory firstParams =
            _existingGroupParams("hash-event", "Hash Event", 1);
        firstParams.markets[0] = _existingMarketParam(firstMarketId, "First", 1);

        MarketFactoryTypes.ExistingMarketGroupCreationParams memory secondParams =
            _existingGroupParams("hash-event", "Hash Event", 2);
        secondParams.markets[0] = _existingMarketParam(firstMarketId, "First", 1);
        secondParams.markets[1] = _existingMarketParam(secondMarketId, "Second", 2);

        vm.prank(creator);
        bytes32 firstGroupId = IMarketFactoryFacet(address(diamond)).createMarketGroupFromExisting(firstParams);
        vm.prank(creator);
        bytes32 secondGroupId = IMarketFactoryFacet(address(diamond)).createMarketGroupFromExisting(secondParams);

        assertTrue(firstGroupId != secondGroupId);
    }

    function _createCreatorMarket(string memory question, uint64 duration) internal returns (bytes32 marketId) {
        (marketId,,) = _createTradingMarket(question, "mirror-existing-group", duration);
    }

    function _createMakerMarket(string memory question, uint64 duration) internal returns (bytes32 marketId) {
        uint64 expiryTime = uint64(block.timestamp) + duration;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        collateralToken.mint(maker, creationFee);
        eveToken.mint(maker, 200e18);

        vm.prank(maker);
        collateralToken.approve(address(diamond), creationFee);
        vm.prank(maker);
        eveToken.approve(address(diamond), type(uint256).max);
        vm.prank(maker);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                question,
                "mirror-existing-group",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                0,
                true
            );
    }

    function _existingGroupParams(string memory slug, string memory title, uint256 length)
        internal
        pure
        returns (MarketFactoryTypes.ExistingMarketGroupCreationParams memory params)
    {
        params.display.slug = slug;
        params.display.title = title;
        params.display.archetype = 4;
        params.display.metadataURI = "ipfs://group";
        params.display.externalRef.source = 1;
        params.display.externalRef.sourceEventId = "event-id";
        params.display.externalRef.sourceSlug = slug;
        params.display.externalRef.snapshotHash = keccak256(abi.encodePacked(slug, title));
        params.markets = new MarketFactoryTypes.ExistingGroupMarketParam[](length);
    }

    function _existingMarketParam(bytes32 marketId, string memory label, int32 lineValueBps)
        internal
        pure
        returns (MarketFactoryTypes.ExistingGroupMarketParam memory param)
    {
        param.marketId = marketId;
        param.display.displayLabel = label;
        param.display.lineLabel = "line";
        param.display.lineValueBps = lineValueBps;
        param.display.groupType = 6;
    }
}
