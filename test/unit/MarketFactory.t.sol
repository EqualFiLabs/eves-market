// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Base64} from "../../lib/openzeppelin-contracts/contracts/utils/Base64.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";

import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";

import {MarketFactoryFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {PlainGnosisCTFMock} from "../helpers/PlainGnosisCTFMock.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract MarketFactoryTest is MarketFactoryFixture {
    struct ProfileMarketFixture {
        uint8 profileId;
        address profileCollateral;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint128 payoutUnit;
        uint128 creationFee;
        uint128 initialVolume;
    }

    function test_CreateMarketStoresConditionDataAndRoutesFee() public {
        string memory question = "Will ETH close above 4k?";
        string memory category = "crypto";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        _approveCreator(creationFee);

        ExpectedMarketData memory expected = _expectedMarketData(question, category, expiryTime);

        _expectMarketCreated(expected, question, expiryTime);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        _assertCreatedMarket(marketId, expected, expiryTime, creationFee, creationBond);
        _assertUnpreparedCondition(expected.conditionId);
        assertFalse(
            StateProbeFacet(address(diamond)).isBookMaterializedFixture(LibCLOBBook.marketBookId(marketId, true))
        );
        assertFalse(
            StateProbeFacet(address(diamond)).isBookMaterializedFixture(LibCLOBBook.marketBookId(marketId, false))
        );
    }

    function test_CreateMarketsCreatesScheduledBatchWithinCap() public {
        uint16 batchCap = 3;
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setMarketCreationBatchCap(batchCap);

        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();
        _approveCreatorWithEve(uint256(creationFee) * batchCap, uint256(creationBond) * batchCap);

        MarketFactoryTypes.MarketCreationParams[] memory params =
            new MarketFactoryTypes.MarketCreationParams[](batchCap);
        uint64 firstStart = uint64(block.timestamp + 1 hours);
        for (uint256 index = 0; index < batchCap; ++index) {
            uint64 tradingStartTime = firstStart + uint64(index) * 1 hours;
            params[index] = MarketFactoryTypes.MarketCreationParams({
                question: string.concat("Will BTC close green in hour ", vm.toString(index)),
                category: "crypto",
                resolutionSource: DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime: tradingStartTime,
                expiryTime: tradingStartTime + 1 hours,
                initialVolume: 0,
                initialDirection: true,
                display: _emptyMarketDisplay(),
                externalRef: _emptyExternalRef()
            });
        }

        vm.prank(creator);
        bytes32[] memory marketIds = IMarketFactoryFacet(address(diamond)).createMarkets(params);

        assertEq(marketIds.length, batchCap);
        for (uint256 index = 0; index < batchCap; ++index) {
            MarketFactoryTypes.MarketInfo memory market =
                IMarketFactoryFacet(address(diamond)).getMarketInfo(marketIds[index]);
            assertEq(market.tradingStartTime, params[index].tradingStartTime);
            assertEq(market.expiryTime, params[index].expiryTime);
            assertEq(market.state, uint8(LibEveMarket.MarketState.Scheduled));
            assertFalse(
                StateProbeFacet(address(diamond))
                    .isBookMaterializedFixture(LibCLOBBook.marketBookId(marketIds[index], true))
            );
            assertFalse(
                StateProbeFacet(address(diamond))
                    .isBookMaterializedFixture(LibCLOBBook.marketBookId(marketIds[index], false))
            );
        }
    }

    function test_CreateMarketWithCollateralProfileStoresPayoutUnitAndUsesQuestionCondition() public {
        string memory question = "Will ETH-denominated markets launch?";
        string memory category = "crypto";
        ProfileMarketFixture memory fixture = _prepareProfileCollateralMarket();
        ExpectedMarketData memory expected = _expectedProfileMarketData(question, category, fixture);

        _expectProfileMarketCreated(expected, question, fixture);
        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                fixture.profileId,
                question,
                category,
                DEFAULT_RESOLUTION_SOURCE,
                fixture.tradingStartTime,
                fixture.expiryTime,
                fixture.initialVolume,
                true
            );

        assertEq(marketId, expected.marketId);
        _assertProfileMarketCreated(marketId, expected, fixture);
        _assertProfileMarketIdIncludesPayoutUnit(question, category, marketId, fixture);
    }

    function test_RevertWhen_CreateMarketWithDisabledCollateralProfile() public {
        uint8 profileId = 2;
        MockUSDG profileCollateral = new MockUSDG();

        vm.prank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(profileId, address(profileCollateral), address(0), 1, 0, false);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileDisabled.selector, profileId));
        IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                profileId,
                "Disabled profile",
                "crypto",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days),
                0,
                true
            );
    }

    function test_CreateMarketGroupCreatesLinkedBinaryMarkets() public {
        string memory title = "Iran peace deal by...";
        uint256 marketCount = 3;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();
        _approveCreatorWithEve(uint256(creationFee) * marketCount, uint256(creationBond) * marketCount);

        MarketFactoryTypes.MarketCreationParams[] memory params =
            new MarketFactoryTypes.MarketCreationParams[](marketCount);
        uint64 startTime = uint64(block.timestamp);
        for (uint256 index = 0; index < marketCount; ++index) {
            uint64 expiryTime = uint64(block.timestamp + 7 days + index * 7 days);
            params[index] = MarketFactoryTypes.MarketCreationParams({
                question: string.concat("Will there be a peace deal by week ", vm.toString(index + 1), "?"),
                category: "politics",
                resolutionSource: DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime: startTime,
                expiryTime: expiryTime,
                initialVolume: 0,
                initialDirection: true,
                display: _emptyMarketDisplay(),
                externalRef: _emptyExternalRef()
            });
        }

        vm.recordLogs();
        vm.prank(creator);
        (bytes32 groupId, bytes32[] memory marketIds) =
            IMarketFactoryFacet(address(diamond)).createMarketGroup(title, params);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 expectedGroupId = keccak256(
            abi.encodePacked("EVE_MARKET_GROUP", creator, keccak256(bytes(title)), marketIds[0], marketCount)
        );
        assertEq(groupId, expectedGroupId);
        assertEq(marketIds.length, marketCount);
        _assertMarketGroupLogs(entries, groupId, title, marketIds);

        for (uint256 index = 0; index < marketCount; ++index) {
            MarketFactoryTypes.MarketInfo memory market =
                IMarketFactoryFacet(address(diamond)).getMarketInfo(marketIds[index]);
            assertEq(market.creator, creator);
            assertEq(market.marketType, uint8(LibEveMarket.MarketType.CLOB));
            assertEq(market.positionTokenType, uint8(LibEveMarket.PositionTokenType.CTF));
            assertEq(market.expiryTime, params[index].expiryTime);
        }
    }

    function test_CreateMarketStoresDisplayAndExternalReference() public {
        string memory question = "Will mirrored markets launch?";
        string memory category = "protocol";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        _approveCreator(StateProbeFacet(address(diamond)).marketCreationFee());

        MarketFactoryTypes.MarketCreationParams memory params = _marketCreationParams(
            question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true
        );
        params.display = MarketFactoryTypes.MarketDisplayInput({
            slug: "mirrored-markets-launch",
            title: "Mirrored markets launch",
            subtitle: "Protocol launch market",
            rules: "Resolve yes if mirrored markets launch before expiry.",
            imageUrl: "ipfs://image",
            iconUrl: "ipfs://icon",
            metadataURI: "ipfs://metadata",
            tagsJson: '["protocol","mirrors"]'
        });
        params.externalRef = MarketFactoryTypes.ExternalMarketRefInput({
            source: 1,
            sourceEventId: "gamma-event-1",
            sourceMarketId: "gamma-market-1",
            sourceSlug: "gamma-slug",
            sourceConditionId: "condition-1",
            snapshotHash: keccak256("snapshot")
        });

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond)).createMarket(params);

        MarketFactoryTypes.MarketDisplayView memory display =
            IMarketFactoryFacet(address(diamond)).getMarketDisplay(marketId);
        assertEq(display.marketId, marketId);
        assertEq(display.slug, "mirrored-markets-launch");
        assertEq(display.title, "Mirrored markets launch");
        assertEq(display.metadataURI, "ipfs://metadata");
        assertEq(display.rulesHash, keccak256(bytes("Resolve yes if mirrored markets launch before expiry.")));
        assertTrue(display.exists);

        MarketFactoryTypes.MarketExternalRefView memory externalRef =
            IMarketFactoryFacet(address(diamond)).getMarketExternalRef(marketId);
        assertEq(externalRef.marketId, marketId);
        assertEq(externalRef.source, 1);
        assertEq(externalRef.sourceEventIdHash, keccak256(bytes("gamma-event-1")));
        assertEq(externalRef.sourceMarketIdHash, keccak256(bytes("gamma-market-1")));
        assertEq(externalRef.sourceSlugHash, keccak256(bytes("gamma-slug")));
        assertEq(externalRef.sourceConditionIdHash, keccak256(bytes("condition-1")));
        assertEq(externalRef.snapshotHash, keccak256("snapshot"));
        assertTrue(externalRef.exists);
    }

    function test_CreateTypedMarketGroupStoresGroupAndChildDisplay() public {
        uint256 marketCount = 2;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();
        _approveCreatorWithEve(uint256(creationFee) * marketCount, uint256(creationBond) * marketCount);

        MarketFactoryTypes.MarketGroupCreationParams memory params;
        params.display = MarketFactoryTypes.GroupDisplayInput({
            slug: "california-governor-2026",
            title: "California Governor Election 2026",
            archetype: 2,
            metadataURI: "ipfs://group",
            externalRef: _emptyExternalRef()
        });
        params.markets = new MarketFactoryTypes.GroupMarketCreationParam[](marketCount);
        params.markets[0] = MarketFactoryTypes.GroupMarketCreationParam({
            market: _marketCreationParams(
                "Will Alice win?",
                "politics",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days),
                0,
                true
            ),
            display: MarketFactoryTypes.GroupMarketDisplayInput({
                displayLabel: "Alice", lineLabel: "", lineValueBps: 0, groupType: 1
            })
        });
        params.markets[1] = MarketFactoryTypes.GroupMarketCreationParam({
            market: _marketCreationParams(
                "Will Bob win?",
                "politics",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 8 days),
                0,
                true
            ),
            display: MarketFactoryTypes.GroupMarketDisplayInput({
                displayLabel: "Bob", lineLabel: "", lineValueBps: 0, groupType: 1
            })
        });

        vm.prank(creator);
        (bytes32 groupId, bytes32[] memory marketIds) = IMarketFactoryFacet(address(diamond)).createMarketGroup(params);

        MarketFactoryTypes.MarketGroupView memory group = IMarketFactoryFacet(address(diamond)).getMarketGroup(groupId);
        assertEq(group.groupId, groupId);
        assertEq(group.creator, creator);
        assertEq(group.slug, "california-governor-2026");
        assertEq(group.title, "California Governor Election 2026");
        assertEq(group.archetype, 2);
        assertEq(group.marketCount, marketCount);
        assertTrue(group.exists);

        bytes32[] memory storedMarketIds = IMarketFactoryFacet(address(diamond)).getMarketGroupMarkets(groupId);
        assertEq(storedMarketIds.length, marketCount);
        assertEq(storedMarketIds[0], marketIds[0]);
        assertEq(storedMarketIds[1], marketIds[1]);

        MarketFactoryTypes.GroupMarketDisplayView memory firstDisplay =
            IMarketFactoryFacet(address(diamond)).getGroupMarketDisplay(groupId, marketIds[0]);
        assertEq(firstDisplay.displayLabel, "Alice");
        assertEq(firstDisplay.sortOrder, 0);
        assertEq(firstDisplay.groupType, 1);
        assertTrue(firstDisplay.exists);
    }

    function test_RevertWhen_CreateMarketsExceedsBatchCap() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setMarketCreationBatchCap(2);

        MarketFactoryTypes.MarketCreationParams[] memory params = new MarketFactoryTypes.MarketCreationParams[](3);
        uint64 firstStart = uint64(block.timestamp + 1 hours);
        for (uint256 index = 0; index < params.length; ++index) {
            uint64 tradingStartTime = firstStart + uint64(index) * 1 hours;
            params[index] = MarketFactoryTypes.MarketCreationParams({
                question: string.concat("Will capped batch reject hour ", vm.toString(index)),
                category: "crypto",
                resolutionSource: DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime: tradingStartTime,
                expiryTime: tradingStartTime + 1 hours,
                initialVolume: 0,
                initialDirection: true,
                display: _emptyMarketDisplay(),
                externalRef: _emptyExternalRef()
            });
        }

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, params.length));
        IMarketFactoryFacet(address(diamond)).createMarkets(params);
    }

    function test_RevertWhen_CreateMarketGroupTitleIsEmpty() public {
        MarketFactoryTypes.MarketCreationParams[] memory params = new MarketFactoryTypes.MarketCreationParams[](1);
        params[0] = MarketFactoryTypes.MarketCreationParams({
            question: "Will empty group titles be rejected?",
            category: "miscellaneous",
            resolutionSource: DEFAULT_RESOLUTION_SOURCE,
            tradingStartTime: uint64(block.timestamp),
            expiryTime: uint64(block.timestamp + 7 days),
            initialVolume: 0,
            initialDirection: true,
            display: _emptyMarketDisplay(),
            externalRef: _emptyExternalRef()
        });

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        IMarketFactoryFacet(address(diamond)).createMarketGroup("", params);
    }

    function test_CreateMarketRegistersYesNoPositionMetadata() public {
        string memory question = "Will Base prediction markets grow?";
        string memory category = "ecosystem";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        ExpectedMarketData memory expected = _expectedMarketData(question, category, expiryTime);
        string memory yesJson = _decodeJsonUri(
            IMarketFactoryFacet(address(diamond)).positionTokenURI(address(conditionalTokens), expected.yesPositionId)
        );
        string memory noJson = _decodeJsonUri(
            IMarketFactoryFacet(address(diamond)).positionTokenURI(address(conditionalTokens), expected.noPositionId)
        );

        assertEq(marketId, expected.marketId);
        assertTrue(_contains(yesJson, '"name":"Eves Market YES Position"'));
        assertTrue(_contains(yesJson, '"question":"Will Base prediction markets grow?"'));
        assertTrue(_contains(yesJson, '"category":"ecosystem"'));
        assertTrue(_contains(yesJson, string.concat('"resolution_source":"', DEFAULT_RESOLUTION_SOURCE, '"')));
        assertTrue(_contains(yesJson, '"outcome":"YES"'));
        assertTrue(_contains(yesJson, '"market_type":"CLOB"'));
        assertTrue(_contains(yesJson, '"resolution_id":"'));
        assertTrue(_contains(yesJson, '"image":"data:image/svg+xml;base64,'));

        assertTrue(_contains(noJson, '"name":"Eves Market NO Position"'));
        assertTrue(_contains(noJson, '"outcome":"NO"'));

        MarketFactoryTypes.MarketMetadataView memory marketMetadata =
            IMarketFactoryFacet(address(diamond)).getMarketMetadata(marketId);
        assertEq(marketMetadata.marketId, expected.marketId);
        assertEq(marketMetadata.question, question);
        assertEq(marketMetadata.category, category);
        assertEq(marketMetadata.resolutionSource, DEFAULT_RESOLUTION_SOURCE);
        assertEq(marketMetadata.creator, creator);
        assertEq(marketMetadata.expiryTime, expiryTime);
        assertEq(marketMetadata.marketType, uint8(LibEveMarket.MarketType.CLOB));
        assertEq(marketMetadata.collateralToken, address(collateralToken));
        assertEq(marketMetadata.positionToken, address(conditionalTokens));
        assertEq(marketMetadata.resolutionId, expected.resolutionId);
        assertEq(marketMetadata.conditionId, expected.conditionId);
        assertEq(marketMetadata.yesPositionId, expected.yesPositionId);
        assertEq(marketMetadata.noPositionId, expected.noPositionId);
        assertTrue(marketMetadata.exists);

        MarketFactoryTypes.PositionMetadataView memory yesMetadata = IMarketFactoryFacet(address(diamond))
            .getPositionMetadata(address(conditionalTokens), expected.yesPositionId);
        assertEq(yesMetadata.positionToken, address(conditionalTokens));
        assertEq(yesMetadata.positionId, expected.yesPositionId);
        assertEq(yesMetadata.marketId, expected.marketId);
        assertEq(yesMetadata.outcome, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(yesMetadata.outcomeLabel, "YES");
        assertTrue(yesMetadata.exists);

        assertEq(conditionalTokens.uri(expected.yesPositionId), "");
    }

    function test_CreateMarketWithPlainGnosisCTFSkipsOptionalMetadata() public {
        PlainGnosisCTFMock plainCtf = new PlainGnosisCTFMock();
        string memory question = "Can plain Gnosis CTF launch markets?";
        string memory category = "compatibility";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();
        uint128 initialVolume = 250e6;

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(plainCtf));

        _approveCreator(uint256(creationFee) + initialVolume);
        ExpectedMarketData memory expected = _expectedPlainGnosisMarket(plainCtf, question, category, expiryTime);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, initialVolume, true
            );

        _assertPlainGnosisMarket(plainCtf, marketId, expected, initialVolume);
        assertEq(collateralToken.balanceOf(creator), 10_000_000e6 - creationFee - initialVolume);
        assertEq(collateralToken.balanceOf(treasury), creationFee);
        assertEq(eveToken.balanceOf(creator), 20_000e18 - creationBond);
    }

    function _expectedPlainGnosisMarket(
        PlainGnosisCTFMock plainCtf,
        string memory question,
        string memory category,
        uint64 expiryTime
    ) internal view returns (ExpectedMarketData memory expected) {
        expected.marketId = LibMarketCreation.marketIdFor(
            question,
            category,
            uint64(block.timestamp),
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        expected.questionId = LibMarketCreation.questionIdFor(question, category, uint64(block.timestamp), expiryTime);
        expected.resolutionId = LibMarketCreation.resolutionIdFor(expected.marketId);
        expected.conditionId = plainCtf.getConditionId(address(diamond), expected.resolutionId, 2);
        expected.yesPositionId = plainCtf.getPositionId(
            IERC20(address(collateralToken)), plainCtf.getCollectionId(bytes32(0), expected.conditionId, 1)
        );
        expected.noPositionId = plainCtf.getPositionId(
            IERC20(address(collateralToken)), plainCtf.getCollectionId(bytes32(0), expected.conditionId, 2)
        );
    }

    function _assertPlainGnosisMarket(
        PlainGnosisCTFMock plainCtf,
        bytes32 marketId,
        ExpectedMarketData memory expected,
        uint128 initialVolume
    ) internal view {
        _assertPlainGnosisCore(plainCtf, marketId, expected);
        assertEq(plainCtf.getOutcomeSlotCount(expected.conditionId), 2);
        assertEq(plainCtf.balanceOf(address(diamond), expected.yesPositionId), initialVolume);
        assertEq(plainCtf.balanceOf(creator, expected.noPositionId), initialVolume);

        MarketFactoryTypes.MarketMetadataView memory metadata =
            IMarketFactoryFacet(address(diamond)).getMarketMetadata(marketId);
        assertEq(metadata.marketId, expected.marketId);
        assertEq(metadata.positionToken, address(plainCtf));
        assertEq(metadata.conditionId, expected.conditionId);
        assertEq(metadata.yesPositionId, expected.yesPositionId);
        assertEq(metadata.noPositionId, expected.noPositionId);
        assertTrue(metadata.exists);
    }

    function _assertPlainGnosisCore(PlainGnosisCTFMock plainCtf, bytes32 marketId, ExpectedMarketData memory expected)
        internal
        view
    {
        (
            address storedCollateralToken,
            address storedCreator,
            bytes32 storedQuestionId,
            bytes32 storedConditionId,
            uint256 storedYesPositionId,
            uint256 storedNoPositionId
        ) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        (uint8 storedMarketType, address storedPositionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);

        assertEq(marketId, expected.marketId);
        assertEq(storedMarketType, uint8(LibEveMarket.MarketType.CLOB));
        assertEq(storedPositionToken, address(plainCtf));
        assertEq(storedCollateralToken, address(collateralToken));
        assertEq(storedCreator, creator);
        assertEq(storedQuestionId, expected.questionId);
        assertEq(storedConditionId, expected.conditionId);
        assertEq(storedYesPositionId, expected.yesPositionId);
        assertEq(storedNoPositionId, expected.noPositionId);
    }

    function test_RevertWhen_ResolutionSourceIsEmpty() public {
        string memory question = "Missing resolution source";
        string memory category = "crypto";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MetadataFieldRequired.selector, "resolutionSource"));
        IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, "", uint64(block.timestamp), expiryTime, 0, true);
    }

    function test_RevertWhen_NonOwnerCreatesWhilePermissionlessCreationDisabled() public {
        string memory question = "Curated launch";
        string memory category = "launch";
        uint64 expiryTime = uint64(block.timestamp + 7 days);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(false);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.PermissionlessCreationDisabled.selector, creator));
        IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);
    }

    function test_OwnerCanCreateMarketWithoutFeeOrBondWhilePermissionlessCreationDisabled() public {
        string memory question = "Admin launch market";
        string memory category = "launch";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        uint256 treasuryBalanceBefore = collateralToken.balanceOf(treasury);
        uint256 ownerEveBefore = eveToken.balanceOf(owner);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(false);

        ExpectedMarketData memory expected = _expectedMarketData(question, category, expiryTime);

        vm.prank(owner);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        _assertStoredMarketCore(marketId, expected, owner);
        _assertUnpreparedCondition(expected.conditionId);
        _assertMarketPositionView(marketId, expected);
        _assertStoredCreationState(marketId, expected.marketId, expiryTime, 0);
        _assertStoredCreationBond(marketId, 0, false);
        assertEq(collateralToken.balanceOf(treasury), treasuryBalanceBefore);
        assertEq(eveToken.balanceOf(owner), ownerEveBefore);
    }

    function test_OwnerCanCreateMarketWithoutFeeOrBondWhenPermissionlessCreationEnabled() public {
        string memory question = "Admin bypass market";
        string memory category = "launch";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        uint256 treasuryBalanceBefore = collateralToken.balanceOf(treasury);
        uint256 ownerEveBefore = eveToken.balanceOf(owner);

        ExpectedMarketData memory expected = _expectedMarketData(question, category, expiryTime);

        vm.prank(owner);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        _assertStoredMarketCore(marketId, expected, owner);
        _assertUnpreparedCondition(expected.conditionId);
        _assertMarketPositionView(marketId, expected);
        _assertStoredCreationState(marketId, expected.marketId, expiryTime, 0);
        _assertStoredCreationBond(marketId, 0, false);
        assertEq(collateralToken.balanceOf(treasury), treasuryBalanceBefore);
        assertEq(eveToken.balanceOf(owner), ownerEveBefore);
    }

    function test_CreateMarketAcceptsMinAndMaxDurationBounds() public {
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint64 minExpiry = uint64(block.timestamp) + StateProbeFacet(address(diamond)).minMarketDuration();
        uint64 maxExpiry = uint64(block.timestamp) + StateProbeFacet(address(diamond)).maxMarketDuration();

        _approveCreator(uint256(creationFee) * 2);

        vm.startPrank(creator);
        bytes32 minMarketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "Bounded min", "general", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), minExpiry, 0, true
            );
        bytes32 maxMarketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "Bounded max", "general", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), maxExpiry, 0, false
            );
        vm.stopPrank();

        assertTrue(minMarketId != bytes32(0));
        assertTrue(maxMarketId != bytes32(0));
        assertTrue(minMarketId != maxMarketId);
    }

    function test_RevertWhen_CreationFeeFundingIsInsufficient() public {
        string memory question = "Will BTC break ATH?";
        string memory category = "crypto";
        uint64 expiryTime = uint64(block.timestamp + 5 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        vm.prank(creator);
        collateralToken.approve(address(diamond), creationFee - 1);

        vm.prank(creator);
        vm.expectRevert(Errors.InsufficientCreationFeeOrReserve.selector);
        IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);
    }

    function test_RevertWhen_CreationBondFundingIsInsufficient() public {
        string memory question = "Will EVE rally?";
        string memory category = "crypto";
        uint64 expiryTime = uint64(block.timestamp + 5 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        _approveCreatorWithEve(creationFee, creationBond - 1);

        vm.prank(creator);
        vm.expectRevert(Errors.InsufficientCreationBond.selector);
        IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);
    }

    function test_RevertWhen_InitialLiquidityFundingIsInsufficient() public {
        string memory question = "Will SOL hit 500?";
        string memory category = "crypto";
        uint64 expiryTime = uint64(block.timestamp + 5 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 initialVolume = 100;

        vm.prank(creator);
        collateralToken.approve(address(diamond), uint256(creationFee) + uint256(initialVolume) - 1);

        vm.prank(creator);
        vm.expectRevert(Errors.InsufficientInitialLiquidityCollateral.selector);
        IMarketFactoryFacet(address(diamond))
            .createMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, initialVolume, true
            );
    }

    function test_RevertWhen_MarketAlreadyExists() public {
        string memory question = "Will Base exceed 1B txs?";
        string memory category = "ecosystem";
        uint64 expiryTime = uint64(block.timestamp + 10 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(uint256(creationFee) * 2);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketAlreadyExists.selector, marketId));
        IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);
    }

    function test_CreateMarketToleratesAlreadyPreparedDiamondCondition() public {
        string memory question = "Will prepared markets still launch?";
        string memory category = "griefing";
        uint64 expiryTime = uint64(block.timestamp + 10 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        ExpectedMarketData memory expected = _expectedMarketData(question, category, expiryTime);
        conditionalTokens.prepareCondition(address(diamond), expected.resolutionId, 2);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        _assertCreatedMarket(
            marketId, expected, expiryTime, creationFee, StateProbeFacet(address(diamond)).marketCreationBond()
        );
        _assertPreparedCondition(expected.resolutionId, expected.conditionId);
    }

    function test_CreateMarketSeedsInitialCurveAndReturnsOppositeInventory() public {
        string memory question = "Will gas stay below 0.2 gwei?";
        string memory category = "ethereum";
        uint64 expiryTime = uint64(block.timestamp + 14 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();
        uint128 initialVolume = 250;

        _approveCreator(uint256(creationFee) + uint256(initialVolume));

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, initialVolume, true
            );

        bytes32 expectedMarketId = LibMarketCreation.marketIdFor(
            question,
            category,
            uint64(block.timestamp),
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        bytes32 expectedConditionId =
            conditionalTokens.getConditionId(address(diamond), LibMarketCreation.resolutionIdFor(expectedMarketId), 2);
        (bytes32 conditionId,,,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        _assertSeededCurveState(marketId, initialVolume, true, uint24((14 days) / 60));
        _assertBootstrapInventory(marketId, initialVolume, true);
        _assertStoredCreationBond(marketId, creationBond, false);
        _assertPreparedCondition(LibMarketCreation.resolutionIdFor(expectedMarketId), expectedConditionId);

        assertEq(conditionId, expectedConditionId);
    }

    function test_SyncMarketStateTransitionsExpiredMarketsToPending() public {
        string memory question = "Will USDC remain above 0.999?";
        string memory category = "stablecoins";
        uint64 expiryTime = uint64(block.timestamp + 2 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        vm.warp(expiryTime);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.MarketExpired(marketId);

        uint8 state = MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
        (,,,,,, uint8 storedState,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(state, uint8(LibEveMarket.MarketState.Pending));
        assertEq(storedState, uint8(LibEveMarket.MarketState.Pending));

        uint8 repeatedState = MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
        assertEq(repeatedState, uint8(LibEveMarket.MarketState.Pending));
    }

    function _prepareProfileCollateralMarket() internal returns (ProfileMarketFixture memory fixture) {
        fixture.profileId = 1;
        fixture.tradingStartTime = uint64(block.timestamp);
        fixture.expiryTime = uint64(block.timestamp + 7 days);
        fixture.payoutUnit = 0.0005 ether;
        fixture.creationFee = 0.002 ether;
        fixture.initialVolume = fixture.payoutUnit * 2;

        MockEveToken profileCollateral = new MockEveToken();
        fixture.profileCollateral = address(profileCollateral);

        vm.prank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(
                fixture.profileId, fixture.profileCollateral, address(0), fixture.payoutUnit, fixture.creationFee, true
            );

        uint256 funded = uint256(fixture.creationFee) + fixture.initialVolume;
        profileCollateral.mint(creator, funded);
        vm.startPrank(creator);
        profileCollateral.approve(address(diamond), funded);
        eveToken.approve(address(diamond), StateProbeFacet(address(diamond)).marketCreationBond());
        vm.stopPrank();
    }

    function _emptyMarketDisplay() internal pure returns (MarketFactoryTypes.MarketDisplayInput memory display) {}

    function _emptyExternalRef() internal pure returns (MarketFactoryTypes.ExternalMarketRefInput memory externalRef) {}

    function _marketCreationParams(
        string memory question,
        string memory category,
        string memory resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint128 initialVolume,
        bool initialDirection
    ) internal pure returns (MarketFactoryTypes.MarketCreationParams memory params) {
        params = MarketFactoryTypes.MarketCreationParams({
            question: question,
            category: category,
            resolutionSource: resolutionSource,
            tradingStartTime: tradingStartTime,
            expiryTime: expiryTime,
            initialVolume: initialVolume,
            initialDirection: initialDirection,
            display: _emptyMarketDisplay(),
            externalRef: _emptyExternalRef()
        });
    }

    function _expectedProfileMarketData(
        string memory question,
        string memory category,
        ProfileMarketFixture memory fixture
    ) internal view returns (ExpectedMarketData memory expected) {
        expected.marketId = LibMarketCreation.profileMarketIdFor(
            question,
            category,
            fixture.tradingStartTime,
            fixture.expiryTime,
            fixture.profileCollateral,
            fixture.profileId,
            fixture.payoutUnit,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        expected.questionId =
            LibMarketCreation.questionIdFor(question, category, fixture.tradingStartTime, fixture.expiryTime);
        expected.resolutionId = expected.questionId;
        expected.conditionId = conditionalTokens.getConditionId(address(diamond), expected.questionId, 2);
        (expected.yesPositionId, expected.noPositionId) =
            _positionIdsFor(fixture.profileCollateral, expected.conditionId);
    }

    function _expectProfileMarketCreated(
        ExpectedMarketData memory expected,
        string memory question,
        ProfileMarketFixture memory fixture
    ) internal {
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.MarketCreated(
            expected.marketId,
            uint8(LibEveMarket.MarketType.CLOB),
            creator,
            uint8(LibEveMarket.PositionTokenType.CTF),
            address(conditionalTokens),
            fixture.profileCollateral,
            expected.resolutionId,
            expected.conditionId,
            expected.yesPositionId,
            expected.noPositionId,
            question,
            fixture.expiryTime
        );
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.MarketCollateralProfile(
            expected.marketId, fixture.profileId, fixture.profileCollateral, fixture.payoutUnit, fixture.creationFee
        );
    }

    function _assertProfileMarketCreated(
        bytes32 marketId,
        ExpectedMarketData memory expected,
        ProfileMarketFixture memory fixture
    ) internal view {
        _assertPreparedCondition(expected.questionId, expected.conditionId);
        assertEq(conditionalTokens.balanceOf(address(diamond), expected.yesPositionId), fixture.initialVolume);
        assertEq(conditionalTokens.balanceOf(creator, expected.noPositionId), fixture.initialVolume);
        assertEq(conditionalTokens.collateralBalance(IERC20(fixture.profileCollateral)), fixture.initialVolume);
        assertEq(IERC20(fixture.profileCollateral).balanceOf(creator), 0);
        assertEq(IERC20(fixture.profileCollateral).balanceOf(treasury), fixture.creationFee);

        MarketFactoryTypes.MarketInfo memory info = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketId);
        assertEq(info.collateralToken, fixture.profileCollateral);
        assertEq(info.collateralProfileId, fixture.profileId);
        assertEq(info.payoutUnit, fixture.payoutUnit);
        assertEq(info.creationFeePaid, fixture.creationFee);

        MarketFactoryTypes.MarketMetadataView memory metadata =
            IMarketFactoryFacet(address(diamond)).getMarketMetadata(marketId);
        assertEq(metadata.collateralToken, fixture.profileCollateral);
        assertEq(metadata.resolutionId, expected.questionId);
        assertEq(metadata.conditionId, expected.conditionId);
        assertEq(metadata.collateralProfileId, fixture.profileId);
        assertEq(metadata.payoutUnit, fixture.payoutUnit);
    }

    function _assertProfileMarketIdIncludesPayoutUnit(
        string memory question,
        string memory category,
        bytes32 marketId,
        ProfileMarketFixture memory fixture
    ) internal view {
        bytes32 recomputed = IMarketFactoryFacet(address(diamond))
            .computeProfileMarketId(
                question,
                category,
                fixture.tradingStartTime,
                fixture.expiryTime,
                fixture.profileCollateral,
                fixture.profileId,
                fixture.payoutUnit,
                LibEveMarket.MarketType.CLOB,
                LibEveMarket.PositionTokenType.CTF
            );
        bytes32 otherPayoutUnit = LibMarketCreation.profileMarketIdFor(
            question,
            category,
            fixture.tradingStartTime,
            fixture.expiryTime,
            fixture.profileCollateral,
            fixture.profileId,
            fixture.payoutUnit * 2,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        assertEq(recomputed, marketId);
        assertTrue(otherPayoutUnit != marketId);
    }

    function _assertSeededCurveState(
        bytes32 marketId,
        uint128 initialVolume,
        bool initialDirection,
        uint24 expectedDurationMinutes
    ) internal view {
        (
            uint256 packed,
            uint128 remainingVolume,
            uint64 createdAt,
            uint32 generation,
            bool active,
            bool isYesSide,
            address maker,
            bytes32 storedMarketId
        ) = StateProbeFacet(address(diamond)).getStoredCurve(0);
        (,,,,,,, uint256 curveCount) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(packed);

        assertEq(createdAt, uint64(block.timestamp));
        assertEq(remainingVolume, initialVolume);
        assertEq(generation, 1);
        assertTrue(active);
        assertEq(isYesSide, initialDirection);
        assertEq(maker, creator);
        assertEq(storedMarketId, marketId);
        assertEq(curveCount, 1);
        assertEq(params.startPrice, 500_000_000);
        assertEq(params.endPrice, 500_000_000);
        assertEq(params.profileId, 0);
        assertEq(params.durationMinutes, expectedDurationMinutes);
        assertEq(StateProbeFacet(address(diamond)).nextCurveId(), 1);
    }

    function _assertBootstrapInventory(bytes32 marketId, uint128 initialVolume, bool initialDirection) internal view {
        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        if (initialDirection) {
            assertEq(conditionalTokens.balanceOf(address(diamond), yesPositionId), initialVolume);
            assertEq(conditionalTokens.balanceOf(creator, noPositionId), initialVolume);
        } else {
            assertEq(conditionalTokens.balanceOf(address(diamond), noPositionId), initialVolume);
            assertEq(conditionalTokens.balanceOf(creator, yesPositionId), initialVolume);
        }

        assertEq(conditionalTokens.collateralBalance(IERC20(address(collateralToken))), initialVolume);
    }

    function _assertCreatedMarket(
        bytes32 marketId,
        ExpectedMarketData memory expected,
        uint64 expiryTime,
        uint128 creationFee,
        uint128 creationBond
    ) internal view {
        assertEq(marketId, expected.marketId);
        _assertStoredMarketCore(marketId, expected, creator);
        _assertMarketPositionView(marketId, expected);
        _assertStoredCreationState(marketId, expected.marketId, expiryTime, creationFee);
        _assertStoredCreationBond(marketId, creationBond, false);
        assertEq(collateralToken.balanceOf(creator), 10_000_000e6 - creationFee);
        assertEq(collateralToken.balanceOf(treasury), creationFee);
        assertEq(eveToken.balanceOf(creator), 20_000e18 - creationBond);
        assertEq(StateProbeFacet(address(diamond)).nextCurveId(), 0);
    }

    function _assertStoredMarketCore(bytes32 marketId, ExpectedMarketData memory expected, address expectedCreator)
        internal
        view
    {
        (
            address storedCollateralToken,
            address storedCreator,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId
        ) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        (uint8 storedMarketType, address storedPositionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);

        assertEq(storedMarketType, uint8(LibEveMarket.MarketType.CLOB));
        assertEq(storedPositionToken, address(conditionalTokens));
        assertEq(storedCollateralToken, address(collateralToken));
        assertEq(storedCreator, expectedCreator);
        assertEq(questionId, expected.questionId);
        assertEq(conditionId, expected.conditionId);
        assertEq(yesPositionId, expected.yesPositionId);
        assertEq(noPositionId, expected.noPositionId);
    }

    function _assertPreparedCondition(bytes32 expectedQuestionId, bytes32 conditionId) internal view {
        (address oracle, bytes32 storedQuestionId, uint256 outcomeSlotCount, bool prepared, bool reported,) =
            conditionalTokens.getConditionDetails(conditionId);

        assertEq(oracle, address(diamond));
        assertEq(storedQuestionId, expectedQuestionId);
        assertEq(outcomeSlotCount, 2);
        assertTrue(prepared);
        assertFalse(reported);
    }

    function _assertUnpreparedCondition(bytes32 conditionId) internal view {
        assertEq(conditionalTokens.getOutcomeSlotCount(conditionId), 0);
    }

    function _assertMarketPositionView(bytes32 marketId, ExpectedMarketData memory expected) internal view {
        (
            bytes32 fetchedConditionId,
            address fetchedCollateralToken,
            uint256 fetchedYesPositionId,
            uint256 fetchedNoPositionId
        ) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(fetchedConditionId, expected.conditionId);
        assertEq(fetchedCollateralToken, address(collateralToken));
        assertEq(fetchedYesPositionId, expected.yesPositionId);
        assertEq(fetchedNoPositionId, expected.noPositionId);
    }

    function _assertStoredCreationState(
        bytes32 marketId,
        bytes32 expectedMarketId,
        uint64 expiryTime,
        uint128 creationFee
    ) internal view {
        (
            bytes32 storedMarketId,
            uint64 createdAt,
            uint64 storedExpiryTime,
            uint96 lastTradePrice,
            uint128 creationFeePaid,
            uint8 outcome,
            uint8 state,
            uint256 curveCount
        ) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(storedMarketId, expectedMarketId);
        assertEq(createdAt, uint64(block.timestamp));
        assertEq(storedExpiryTime, expiryTime);
        assertEq(lastTradePrice, 0);
        assertEq(creationFeePaid, creationFee);
        assertEq(outcome, 0);
        assertEq(state, uint8(LibEveMarket.MarketState.Trading));
        assertEq(curveCount, 0);
    }

    function _assertStoredCreationBond(bytes32 marketId, uint128 creationBond, bool released) internal view {
        (uint128 storedCreationBondEve, bool creationBondReleased) =
            StateProbeFacet(address(diamond)).getStoredCreationBond(marketId);

        assertEq(storedCreationBondEve, creationBond);
        assertEq(creationBondReleased, released);
    }

    function _expectMarketCreated(ExpectedMarketData memory expected, string memory question, uint64 expiryTime)
        internal
    {
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.MarketCreated(
            expected.marketId,
            uint8(LibEveMarket.MarketType.CLOB),
            creator,
            uint8(LibEveMarket.PositionTokenType.CTF),
            address(conditionalTokens),
            address(collateralToken),
            expected.resolutionId,
            expected.conditionId,
            expected.yesPositionId,
            expected.noPositionId,
            question,
            expiryTime
        );
    }

    function _assertMarketGroupLogs(
        Vm.Log[] memory entries,
        bytes32 groupId,
        string memory title,
        bytes32[] memory marketIds
    ) internal view {
        bool createdFound = _assertMarketGroupCreatedLog(entries, groupId, title, marketIds.length);
        uint256 addedCount = _assertMarketGroupAddedLogs(entries, groupId, marketIds);

        assertTrue(createdFound);
        assertEq(addedCount, marketIds.length);
    }

    function _assertMarketGroupCreatedLog(
        Vm.Log[] memory entries,
        bytes32 groupId,
        string memory title,
        uint256 expectedMarketCount
    ) internal view returns (bool createdFound) {
        bytes32 groupCreatedSig = keccak256("MarketGroupCreated(bytes32,address,bytes32,string,uint256)");
        bytes32 titleHash = keccak256(bytes(title));

        for (uint256 index = 0; index < entries.length; ++index) {
            Vm.Log memory entry = entries[index];
            if (entry.emitter != address(diamond) || entry.topics[0] != groupCreatedSig) {
                continue;
            }

            (string memory emittedTitle, uint256 marketCount) = abi.decode(entry.data, (string, uint256));
            assertEq(entry.topics[1], groupId);
            assertEq(entry.topics[2], bytes32(uint256(uint160(creator))));
            assertEq(entry.topics[3], titleHash);
            assertEq(emittedTitle, title);
            assertEq(marketCount, expectedMarketCount);
            createdFound = true;
        }
    }

    function _assertMarketGroupAddedLogs(Vm.Log[] memory entries, bytes32 groupId, bytes32[] memory marketIds)
        internal
        view
        returns (uint256 addedCount)
    {
        bytes32 groupMarketAddedSig = keccak256("MarketGroupMarketAdded(bytes32,bytes32,uint256)");

        for (uint256 index = 0; index < entries.length; ++index) {
            Vm.Log memory entry = entries[index];
            if (entry.emitter != address(diamond) || entry.topics[0] != groupMarketAddedSig) {
                continue;
            }

            uint256 legIndex = uint256(entry.topics[3]);
            assertLt(legIndex, marketIds.length);
            assertEq(entry.topics[1], groupId);
            assertEq(entry.topics[2], marketIds[legIndex]);
            addedCount += 1;
        }
    }

    function _decodeJsonUri(string memory uri) internal pure returns (string memory) {
        string memory prefix = "data:application/json;base64,";
        bytes memory uriBytes = bytes(uri);
        bytes memory prefixBytes = bytes(prefix);
        bytes memory encoded = new bytes(uriBytes.length - prefixBytes.length);

        for (uint256 index = 0; index < prefixBytes.length; ++index) {
            assertEq(uriBytes[index], prefixBytes[index]);
        }
        for (uint256 index = 0; index < encoded.length; ++index) {
            encoded[index] = uriBytes[index + prefixBytes.length];
        }

        return string(Base64.decode(string(encoded)));
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0 || needleBytes.length > haystackBytes.length) {
            return needleBytes.length == 0;
        }

        for (uint256 cursor = 0; cursor <= haystackBytes.length - needleBytes.length; ++cursor) {
            bool matched = true;
            for (uint256 offset = 0; offset < needleBytes.length; ++offset) {
                if (haystackBytes[cursor + offset] != needleBytes[offset]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                return true;
            }
        }

        return false;
    }
}
