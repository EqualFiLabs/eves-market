// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Base64} from "../../lib/openzeppelin-contracts/contracts/utils/Base64.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract ParimutuelFacetTest is ResolutionFixture {
    uint16 internal constant DEFAULT_ENTRY_FEE_BPS = 250;
    uint128 internal constant DEFAULT_MIN_ENTRY = 1e6;
    uint64 internal constant DEFAULT_EPOCH_WINDOW = 7 days;
    uint8 internal constant EVE_ETH_PROFILE_ID = 1;
    uint128 internal constant EVE_ETH_PAYOUT_UNIT = 0.0005 ether;

    ParimutuelFacet internal parimutuelFacet;
    ParimutuelShareToken internal shareToken;
    CanonicalWETH9 internal weth;
    EveETH internal eveETH;

    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public override {
        super.setUp();

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        parimutuelFacet = new ParimutuelFacet();
        shareToken = new ParimutuelShareToken(address(diamond), "uri://parimutuel/{id}");
        weth = new CanonicalWETH9();
        eveETH = new EveETH(address(weth));

        _addFacet(address(parimutuelFacet), _parimutuelSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(500, 1_000, 8_500);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        vm.stopPrank();

        ResolutionHarnessFacet(address(diamond))
            .setParimutuelConfig(address(shareToken), DEFAULT_ENTRY_FEE_BPS, DEFAULT_MIN_ENTRY);

        collateralToken.mint(alice, 10_000_000e6);
        collateralToken.mint(bob, 10_000_000e6);
        collateralToken.mint(carol, 10_000_000e6);
    }

    function test_CreateParimutuelMarketStoresTypedMarketAndDeterministicShareIds() public {
        string memory question = "Will parimutuel creation work?";
        string memory category = "parimutuel";
        uint64 expiryTime = uint64(block.timestamp + 7 days);

        bytes32 marketId = _createParimutuelMarket(question, category, expiryTime);
        bytes32 expectedMarketId = _parimutuelMarketId(question, category, uint64(block.timestamp), expiryTime);

        assertEq(marketId, expectedMarketId);
        assertTrue(IParimutuelFacet(address(diamond)).isParimutuelMarket(marketId));
        assertEq(IParimutuelFacet(address(diamond)).getParimutuelEpochWindow(marketId), DEFAULT_EPOCH_WINDOW);

        (uint8 marketType, address positionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);
        (
            address collateralToken_,
            address storedCreator,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId
        ) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);

        assertEq(marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(positionToken, address(shareToken));
        assertEq(collateralToken_, address(collateralToken));
        assertEq(storedCreator, creator);
        assertEq(questionId, _questionIdFor(question, category, expiryTime));
        assertEq(conditionId, bytes32(0));
        assertEq(yesPositionId, _parimutuelYesPositionId(marketId));
        assertEq(noPositionId, _parimutuelNoPositionId(marketId));

        (,,,, uint128 creationFeePaid, uint8 outcome, uint8 state,) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(creationFeePaid, 0);
        assertEq(outcome, uint8(LibEveMarket.MarketOutcome.Unresolved));
        assertEq(state, uint8(LibEveMarket.MarketState.Trading));

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.totalYesShares, 0);
        assertEq(pool.totalNoShares, 0);
        assertEq(pool.payoutPool, 0);
    }

    function test_CreateParimutuelMarketSeedsPayoutPoolInsteadOfTreasury() public {
        uint128 seedAmount = 25e6;
        string memory question = "Will parimutuel creation seed the pool?";
        string memory category = "parimutuel";
        uint64 tradingStartTime = uint64(block.timestamp);
        uint64 expiryTime = tradingStartTime + 7 days;
        bytes32 expectedMarketId = _parimutuelMarketId(question, category, tradingStartTime, expiryTime);
        uint256 creatorBalanceBefore = collateralToken.balanceOf(creator);
        uint256 treasuryBalanceBefore = collateralToken.balanceOf(treasury);
        uint256 diamondBalanceBefore = collateralToken.balanceOf(address(diamond));

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setParimutuelCreationSeedAmount(seedAmount);

        _approveCreatorWithEve(seedAmount, type(uint256).max);

        vm.recordLogs();
        vm.prank(creator);
        bytes32 marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, tradingStartTime, expiryTime, DEFAULT_EPOCH_WINDOW
            );

        assertEq(marketId, expectedMarketId);
        assertEq(collateralToken.balanceOf(creator), creatorBalanceBefore - seedAmount);
        assertEq(collateralToken.balanceOf(treasury), treasuryBalanceBefore);
        assertEq(collateralToken.balanceOf(address(diamond)), diamondBalanceBefore + seedAmount);

        (,,,, uint128 creationFeePaid,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(creationFeePaid, seedAmount);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.totalYesShares, 0);
        assertEq(pool.totalNoShares, 0);
        assertEq(pool.payoutPool, seedAmount);

        _assertSeedEventAfterCreation(vm.getRecordedLogs(), expectedMarketId, seedAmount);
    }

    function test_CreateParimutuelMarketWithCollateralProfileStoresEveETHMetadataAndSeedsPool() public {
        uint128 seedAmount = 0.003 ether;
        uint128 minEntry = 0.0002 ether;
        uint256 diamondBalanceBefore = eveETH.balanceOf(address(diamond));
        uint256 diamondEveBefore = eveToken.balanceOf(address(diamond));

        vm.recordLogs();
        bytes32 marketId = _createEveETHParimutuelMarket("Will eveETH parimutuel creation work?", seedAmount, minEntry);

        assertEq(eveETH.balanceOf(creator), 0);
        assertEq(eveETH.balanceOf(address(diamond)), diamondBalanceBefore + seedAmount);
        assertEq(
            eveToken.balanceOf(address(diamond)),
            diamondEveBefore + StateProbeFacet(address(diamond)).marketCreationBond()
        );
        MarketFactoryTypes.MarketInfo memory info = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketId);
        assertEq(info.marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(info.positionTokenType, uint8(LibEveMarket.PositionTokenType.PARIMUTUEL));
        assertEq(info.collateralToken, address(eveETH));
        assertEq(info.collateralProfileId, EVE_ETH_PROFILE_ID);
        assertEq(info.payoutUnit, EVE_ETH_PAYOUT_UNIT);
        assertEq(info.creationFeePaid, seedAmount);

        MarketFactoryTypes.MarketMetadataView memory metadata =
            IMarketFactoryFacet(address(diamond)).getMarketMetadata(marketId);
        assertEq(metadata.collateralToken, address(eveETH));
        assertEq(metadata.collateralProfileId, EVE_ETH_PROFILE_ID);
        assertEq(metadata.payoutUnit, EVE_ETH_PAYOUT_UNIT);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.payoutPool, seedAmount);
        assertEq(pool.totalYesShares, 0);
        assertEq(pool.totalNoShares, 0);

        _assertCollateralProfileLog(vm.getRecordedLogs(), marketId, seedAmount);
    }

    function test_ProfileParimutuelMarketIdDoesNotCollideWithDefaultParimutuelMarket() public {
        string memory question = "Can equal wording use two collateral profiles?";
        string memory category = "parimutuel";
        uint64 tradingStartTime = uint64(block.timestamp);
        uint64 expiryTime = tradingStartTime + 7 days;

        _configureEveETHParimutuelProfile(0.001 ether, 0.0002 ether, true);
        _fundEveETH(creator, 0.001 ether);

        bytes32 defaultMarketId = _createParimutuelMarket(question, category, expiryTime);

        vm.prank(creator);
        bytes32 eveEthMarketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                question,
                category,
                DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime,
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );

        assertNotEq(eveEthMarketId, defaultMarketId);
        assertEq(eveEthMarketId, _profileParimutuelMarketId(question, category, tradingStartTime, expiryTime));
    }

    function test_RevertWhen_ProfileParimutuelCreationUsesDisabledProfile() public {
        uint128 seedAmount = 0.001 ether;
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        _configureEveETHParimutuelProfile(seedAmount, 0.0002 ether, false);
        _fundEveETH(creator, seedAmount);
        uint256 creatorBalanceBefore = eveETH.balanceOf(creator);

        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileDisabled.selector, EVE_ETH_PROFILE_ID));
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                "disabled eveETH parimutuel",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );

        assertEq(eveETH.balanceOf(creator), creatorBalanceBefore);
        assertEq(eveETH.balanceOf(address(diamond)), 0);
    }

    function test_ProfileParimutuelEntryUsesProfileMinEntry() public {
        uint128 minEntry = 0.002 ether;
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        _configureEveETHParimutuelProfile(0, minEntry, true);

        vm.prank(creator);
        bytes32 marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                "eveETH min entry",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );

        _fundEveETH(alice, minEntry);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, minEntry - 1));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, minEntry - 1, alice, 0);
    }

    function test_CreateParimutuelMarketRegistersNativeMetadataAndUri() public {
        string memory question = "Will parimutuel creation work?";
        string memory category = "parimutuel";
        uint64 expiryTime = uint64(block.timestamp + 7 days);

        bytes32 marketId = _createParimutuelMarket(question, category, expiryTime);
        uint256 yesPositionId = _parimutuelYesPositionId(marketId);
        uint256 noPositionId = _parimutuelNoPositionId(marketId);

        MarketFactoryTypes.MarketMetadataView memory marketMetadata =
            IMarketFactoryFacet(address(diamond)).getMarketMetadata(marketId);
        assertEq(marketMetadata.marketId, marketId);
        assertEq(marketMetadata.question, question);
        assertEq(marketMetadata.category, category);
        assertEq(marketMetadata.resolutionSource, DEFAULT_RESOLUTION_SOURCE);
        assertEq(marketMetadata.creator, creator);
        assertEq(marketMetadata.marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(marketMetadata.collateralToken, address(collateralToken));
        assertEq(marketMetadata.positionToken, address(shareToken));
        assertEq(marketMetadata.resolutionId, LibMarketCreation.resolutionIdFor(marketId));
        assertEq(marketMetadata.conditionId, bytes32(0));
        assertEq(marketMetadata.yesPositionId, yesPositionId);
        assertEq(marketMetadata.noPositionId, noPositionId);
        assertTrue(marketMetadata.exists);

        MarketFactoryTypes.PositionMetadataView memory yesMetadata =
            IMarketFactoryFacet(address(diamond)).getPositionMetadata(address(shareToken), yesPositionId);
        assertEq(yesMetadata.marketId, marketId);
        assertEq(yesMetadata.positionToken, address(shareToken));
        assertEq(yesMetadata.positionId, yesPositionId);
        assertEq(yesMetadata.outcome, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(yesMetadata.outcomeLabel, "YES");
        assertTrue(yesMetadata.exists);

        string memory yesJson = _decodeJsonUri(shareToken.uri(yesPositionId));
        assertTrue(_contains(yesJson, '"name":"Eves Market YES Position"'));
        assertTrue(_contains(yesJson, '"question":"Will parimutuel creation work?"'));
        assertTrue(_contains(yesJson, '"category":"parimutuel"'));
        assertTrue(_contains(yesJson, string.concat('"resolution_source":"', DEFAULT_RESOLUTION_SOURCE, '"')));
        assertTrue(_contains(yesJson, '"market_type":"PARIMUTUEL"'));
        assertTrue(
            _contains(yesJson, '"condition_id":"0x0000000000000000000000000000000000000000000000000000000000000000"')
        );
        assertTrue(_contains(yesJson, '"image":"data:image/svg+xml;base64,'));
    }

    function test_RevertWhen_ParimutuelResolutionSourceIsEmpty() public {
        uint64 expiryTime = uint64(block.timestamp + 7 days);

        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MetadataFieldRequired.selector, "resolutionSource"));
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "missing resolution source", "parimutuel", "", uint64(block.timestamp), expiryTime, DEFAULT_EPOCH_WINDOW
            );
    }

    function test_CreateParimutuelMarketEmitsCreationEvents() public {
        string memory question = "Will parimutuel creation emit events?";
        string memory category = "parimutuel";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        bytes32 expectedMarketId = _parimutuelMarketId(question, category, uint64(block.timestamp), expiryTime);

        vm.recordLogs();
        vm.prank(owner);
        assertEq(
            IParimutuelFacet(address(diamond))
                .createParimutuelMarket(
                    question,
                    category,
                    DEFAULT_RESOLUTION_SOURCE,
                    uint64(block.timestamp),
                    expiryTime,
                    DEFAULT_EPOCH_WINDOW
                ),
            expectedMarketId
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);
        _assertMarketDisplayMetadataLog(
            entries[_findLogIndex(
                    entries,
                    keccak256(
                        "MarketDisplayMetadataSet(bytes32,string,string,string,string,string,string,string,string,bytes32,bytes32)"
                    )
                )],
            expectedMarketId
        );
        _assertParimutuelMarketCreatedLog(
            entries[_findLogIndex(
                    entries,
                    keccak256(
                        "MarketCreated(bytes32,uint8,address,uint8,address,address,bytes32,bytes32,uint256,uint256,string,uint64)"
                    )
                )],
            expectedMarketId
        );
        _assertLegacyParimutuelMarketCreatedLog(
            entries[_findLogIndex(
                    entries, keccak256("ParimutuelMarketCreated(bytes32,address,address,uint256,uint256,uint64,uint64)")
                )],
            expiryTime,
            expectedMarketId
        );
    }

    function test_ParimutuelDirectBuyDoesNotMaterializeSecondaryBooks() public {
        string memory question = "Will direct buy keep books lazy?";
        string memory category = "parimutuel";
        uint64 expiryTime = uint64(block.timestamp + 7 days);

        bytes32 marketId = _createParimutuelMarket(question, category, expiryTime);
        bytes32 yesBookId = LibCLOBBook.marketBookId(marketId, true);
        bytes32 noBookId = LibCLOBBook.marketBookId(marketId, false);

        assertFalse(StateProbeFacet(address(diamond)).isBookMaterializedFixture(yesBookId));
        assertFalse(StateProbeFacet(address(diamond)).isBookMaterializedFixture(noBookId));

        _buyShares(alice, marketId, true, 100e6);

        assertFalse(StateProbeFacet(address(diamond)).isBookMaterializedFixture(yesBookId));
        assertFalse(StateProbeFacet(address(diamond)).isBookMaterializedFixture(noBookId));
    }

    function test_RevertWhen_DuplicateParimutuelMarket() public {
        string memory question = "Will duplicates be rejected?";
        string memory category = "parimutuel";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        bytes32 marketId = _createParimutuelMarket(question, category, expiryTime);

        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketAlreadyExists.selector, marketId));
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, DEFAULT_EPOCH_WINDOW
            );
    }

    function test_RevertWhen_ParimutuelExpiryTooSoon() public {
        uint64 expiryTime = uint64(block.timestamp + 1 hours - 1);
        uint64 minExpiry = uint64(block.timestamp + 1 hours);

        vm.expectRevert(abi.encodeWithSelector(Errors.ExpiryTooSoon.selector, expiryTime, minExpiry));
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "too soon",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );
    }

    function test_RevertWhen_ParimutuelExpiryTooLate() public {
        uint64 expiryTime = uint64(block.timestamp + 90 days + 1);
        uint64 maxExpiry = uint64(block.timestamp + 90 days);

        vm.expectRevert(abi.encodeWithSelector(Errors.ExpiryTooLate.selector, expiryTime, maxExpiry));
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "too late",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );
    }

    function test_RevertWhen_NonOwnerCreatesParimutuelWhilePermissionlessDisabled() public {
        uint64 expiryTime = uint64(block.timestamp + 7 days);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(false);

        vm.expectRevert(abi.encodeWithSelector(Errors.PermissionlessCreationDisabled.selector, creator));
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "disabled",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );
    }

    function test_OwnerCreatesParimutuelWithoutFeeOrBondWhilePermissionlessDisabled() public {
        string memory question = "Can owner create while disabled?";
        string memory category = "parimutuel";
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        uint256 treasuryCollateralBefore = collateralToken.balanceOf(treasury);
        uint256 diamondEveBefore = eveToken.balanceOf(address(diamond));

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(false);

        vm.prank(owner);
        bytes32 marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, DEFAULT_EPOCH_WINDOW
            );

        (, address storedCreator,,,,) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        (,,,, uint128 creationFeePaid,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        (uint128 creationBond,) = StateProbeFacet(address(diamond)).getStoredCreationBond(marketId);

        assertEq(storedCreator, owner);
        assertEq(creationFeePaid, 0);
        assertEq(creationBond, 0);
        assertEq(collateralToken.balanceOf(treasury), treasuryCollateralBefore);
        assertEq(eveToken.balanceOf(address(diamond)), diamondEveBefore);
    }

    function test_BuySharesMintsNetSharesAndRoutesEntryFees() public {
        (bytes32 marketId,, uint256 yesPositionId,) = _createDefaultParimutuelMarket("buy shares");
        uint128 amount = 1_000e6;
        // Epoch 0 (2x multiplier): netCollateral = 975e6, sharesMinted = 1_950e6
        uint128 expectedShares = 1_950e6;

        uint256 treasuryBefore = collateralToken.balanceOf(treasury);
        _buyShares(alice, marketId, true, amount);

        assertEq(shareToken.balanceOf(alice, yesPositionId), expectedShares);
        assertEq(collateralToken.balanceOf(treasury), treasuryBefore + 23_750_000);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.totalYesShares, expectedShares);
        assertEq(pool.totalNoShares, 0);
        assertEq(pool.payoutPool, 975e6); // tracks collateral, not inflated shares
        assertEq(pool.impliedYesProbability, 1e18);
        assertEq(pool.impliedNoProbability, 0);

        (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (, uint128 totalFeePool, uint128 totalQuoteVolume) =
            StateProbeFacet(address(diamond)).getStoredMarketTrading(marketId);

        assertEq(totalFeePool, 25e6);
        assertEq(totalQuoteVolume, amount);
        assertEq(creatorFeesEscrowed, 1_250_000);
        assertEq(protocolFeesAccrued, 23_750_000);
        assertEq(collateralToken.balanceOf(address(diamond)), 976_250_000);
    }

    function test_ParimutuelMarketUsesEntryFeeSnapshotAfterAdminChange() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("fee snapshot");

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(10_000, 0, 0);
        OwnershipFacet(address(diamond)).setParimutuelConfig(address(shareToken), 5_000, DEFAULT_MIN_ENTRY);
        vm.stopPrank();

        (uint128 totalFee, uint128 creatorFee, uint128 protocolFee, uint128 vaultFee, uint128 netShares) =
            IParimutuelFacet(address(diamond)).previewEntryFee(marketId, 1_000e6);

        assertEq(totalFee, 25e6);
        assertEq(creatorFee, 1_250_000);
        assertEq(protocolFee, 23_750_000);
        assertEq(vaultFee, 0);
        assertEq(netShares, 975e6);
    }

    function test_ScheduledParimutuelBlocksEntriesUntilStartAndAnchorsEpochs() public {
        _setParimutuelFees(0, 1);

        uint64 tradingStartTime = uint64(block.timestamp + 1 days);
        uint64 epochWindow = 8 hours;
        uint64 expiryTime = uint64(tradingStartTime + 2 days);

        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.prank(creator);
        bytes32 marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "scheduled parimutuel",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime,
                expiryTime,
                epochWindow
            );

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(state, uint8(LibEveMarket.MarketState.Scheduled));

        (uint256 multiplierBefore, uint256 epochBefore) =
            IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(multiplierBefore, 20_000);
        assertEq(epochBefore, 0);

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), 100e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 100e6, alice, 0);
        vm.stopPrank();

        vm.warp(tradingStartTime);
        assertEq(_buyShares(alice, marketId, true, 100e6), 200e6);

        vm.warp(tradingStartTime + 1 hours);
        (uint256 multiplierAfter, uint256 epochAfter) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(multiplierAfter, 15_000);
        assertEq(epochAfter, 1);
        assertEq(_buyShares(bob, marketId, true, 100e6), 150e6);
    }

    function test_PreviewParimutuelEntryReturnsMintAndBasisData() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("entry preview");

        IParimutuelFacet.EntryPreview memory preview =
            IParimutuelFacet(address(diamond)).previewParimutuelEntry(marketId, true, 1_000e6);

        assertEq(preview.amountIn, 1_000e6);
        assertEq(preview.totalFee, 25e6);
        assertEq(preview.creatorFee, 1_250_000);
        assertEq(preview.protocolFee, 23_750_000);
        assertEq(preview.vaultFee, 0);
        assertEq(preview.netCollateral, 975e6);
        assertEq(preview.sharesMinted, 1_950e6);
        assertEq(preview.multiplierBps, 20_000);
        assertEq(preview.epoch, 0);
        assertEq(preview.effectiveBasisWad, 5e17);
        assertEq(preview.totalYesSharesAfter, 1_950e6);
        assertEq(preview.totalNoSharesAfter, 0);
        assertEq(preview.payoutPoolAfter, 975e6);
    }

    function test_PreviewParimutuelEntryReturnsMaxBasisWhenSharesRoundToZero() public {
        _setParimutuelFees(0, 1);
        uint64 duration = 8 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("zero preview", "parimutuel", expiryTime);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        vm.warp(createdAt + (duration * 7 / 8));

        IParimutuelFacet.EntryPreview memory preview =
            IParimutuelFacet(address(diamond)).previewParimutuelEntry(marketId, true, 1);

        assertEq(preview.netCollateral, 1);
        assertEq(preview.sharesMinted, 0);
        assertEq(preview.multiplierBps, 4_000);
        assertEq(preview.epoch, 7);
        assertEq(preview.effectiveBasisWad, type(uint256).max);
        assertEq(preview.totalYesSharesAfter, 0);
        assertEq(preview.payoutPoolAfter, 1);
    }

    function test_BuyNoSharesMintsNetSharesUpdatesPoolAndEmits() public {
        (bytes32 marketId,,, uint256 noPositionId) = _createDefaultParimutuelMarket("buy no shares");
        uint128 amount = 1_000e6;
        // Epoch 0 (2x): netCollateral = 975e6, sharesMinted = 1_950e6
        uint128 expectedShares = 1_950e6;

        vm.startPrank(bob);
        collateralToken.approve(address(diamond), amount);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.ParimutuelSharesBought(marketId, bob, bob, false, amount, expectedShares, 25e6);
        uint128 minted = IParimutuelFacet(address(diamond)).buyShares(marketId, false, amount, bob, 0);
        vm.stopPrank();

        assertEq(minted, expectedShares);
        assertEq(shareToken.balanceOf(bob, noPositionId), expectedShares);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.totalYesShares, 0);
        assertEq(pool.totalNoShares, expectedShares);
        assertEq(pool.payoutPool, 975e6);
        assertEq(pool.impliedYesProbability, 0);
        assertEq(pool.impliedNoProbability, 1e18);
    }

    function test_RevertWhen_BuyBelowMinEntry() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("min entry");
        uint128 amount = DEFAULT_MIN_ENTRY - 1;

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), amount);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, amount));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, amount, alice, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_BuySharesBelowMinSharesOut() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("min shares out");
        uint128 amount = 100;

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), amount);
        vm.expectRevert(abi.encodeWithSelector(Errors.SlippageExceeded.selector, uint128(200), uint128(201)));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, amount, alice, 201);
        vm.stopPrank();
    }

    function test_RevertWhen_BuyReceiverIsZeroAddress() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("zero receiver");
        uint128 amount = 1_000e6;

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), amount);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, amount, address(0), 0);
        vm.stopPrank();
    }

    function test_RevertWhen_BuyNonTradingParimutuelMarket() public {
        (bytes32 marketId, uint64 expiryTime,,) = _createDefaultParimutuelMarket("resolved buy");
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1_000e6, alice, 0);
        vm.stopPrank();
    }

    function test_EarlyCreatorSettlementStopsParimutuelEntriesBeforeExpiry() public {
        (bytes32 marketId, uint64 expiryTime,,) = _createDefaultParimutuelMarket("early settled buy");
        assertLt(block.timestamp, expiryTime);

        _buyShares(alice, marketId, true, 1_000e6);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.Yes));

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));

        vm.startPrank(bob);
        collateralToken.approve(address(diamond), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IParimutuelFacet(address(diamond)).buyShares(marketId, false, 1_000e6, bob, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_BuyExpiredParimutuelMarket() public {
        (bytes32 marketId, uint64 expiryTime,,) = _createDefaultParimutuelMarket("expired buy");

        vm.warp(expiryTime);

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1_000e6, alice, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_EntryFeeConsumesAmount() public {
        _setParimutuelFees(10_000, 1);
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("fee consumes amount");

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.FeeExceedsAmount.selector, uint128(1), uint128(1)));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1, alice, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_BuyUsesInvalidCreatorProtocolSplit() public {
        ResolutionHarnessFacet(address(diamond)).setFeeSplitConfig(0, 8_000, 3_000, 0);
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("invalid split");

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.FeeSplitExceedsDenominator.selector, 8_000, 3_000));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1_000e6, alice, 0);
        vm.stopPrank();
    }

    function test_WhenPermissionlessCreationDisabled_BuyRoutesCreatorFeeToProtocol() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("disabled buy fee");
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(false);

        _buyShares(alice, marketId, true, 1_000e6);

        (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        assertEq(creatorFeesEscrowed, 0);
        assertEq(protocolFeesAccrued, 25e6);
        assertEq(collateralToken.balanceOf(treasury), treasuryBefore + 25e6);
    }

    function test_BuySharesBatchMintsBothSidesAndViewsMatchPool() public {
        (bytes32 marketId,, uint256 yesPositionId, uint256 noPositionId) =
            _createDefaultParimutuelMarket("batch shares");

        bytes32[] memory marketIds = new bytes32[](2);
        bool[] memory sides = new bool[](2);
        uint128[] memory amounts = new uint128[](2);
        uint128[] memory minSharesOut = new uint128[](2);
        marketIds[0] = marketId;
        marketIds[1] = marketId;
        sides[0] = true;
        sides[1] = false;
        amounts[0] = 1_000e6;
        amounts[1] = 500e6;
        minSharesOut[0] = 1_950e6;
        minSharesOut[1] = 975_000_000;

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), amounts[0] + amounts[1]);
        uint128[] memory minted =
            IParimutuelFacet(address(diamond)).buySharesBatch(marketIds, sides, amounts, minSharesOut, alice);
        vm.stopPrank();

        // Epoch 0 (2x): 975e6 * 2 = 1_950e6, 487_500_000 * 2 = 975_000_000
        assertEq(minted[0], 1_950e6);
        assertEq(minted[1], 975_000_000);
        assertEq(shareToken.balanceOf(alice, yesPositionId), 1_950e6);
        assertEq(shareToken.balanceOf(alice, noPositionId), 975_000_000);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.totalYesShares, 1_950e6);
        assertEq(pool.totalNoShares, 975_000_000);
        assertEq(pool.payoutPool, 1_462_500_000); // collateral: 975e6 + 487_500_000
        assertEq(pool.impliedYesProbability, 666_666_666_666_666_666);
        assertEq(pool.impliedNoProbability, 333_333_333_333_333_334);

        (uint256 yesShares, uint256 noShares) =
            IParimutuelFacet(address(diamond)).getParimutuelBalances(marketId, alice);
        assertEq(yesShares, 1_950e6);
        assertEq(noShares, 975_000_000);

        _assertDefaultEntryFee(marketId);
    }

    function test_BuySharesBatchAcrossMultipleMarkets() public {
        (bytes32 firstMarketId,, uint256 firstYesPositionId,) = _createDefaultParimutuelMarket("batch market one");
        (bytes32 secondMarketId,,, uint256 secondNoPositionId) = _createDefaultParimutuelMarket("batch market two");

        bytes32[] memory marketIds = new bytes32[](2);
        bool[] memory sides = new bool[](2);
        uint128[] memory amounts = new uint128[](2);
        uint128[] memory minSharesOut = new uint128[](2);
        marketIds[0] = firstMarketId;
        marketIds[1] = secondMarketId;
        sides[0] = true;
        sides[1] = false;
        amounts[0] = 1_000e6;
        amounts[1] = 2_000e6;
        minSharesOut[0] = 1_950e6;
        minSharesOut[1] = 3_900e6;

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), 3_000e6);
        uint128[] memory minted =
            IParimutuelFacet(address(diamond)).buySharesBatch(marketIds, sides, amounts, minSharesOut, alice);
        vm.stopPrank();

        assertEq(minted[0], 1_950e6);
        assertEq(minted[1], 3_900e6);
        assertEq(shareToken.balanceOf(alice, firstYesPositionId), 1_950e6);
        assertEq(shareToken.balanceOf(alice, secondNoPositionId), 3_900e6);

        IParimutuelFacet.PoolView memory firstPool = IParimutuelFacet(address(diamond)).getParimutuelPool(firstMarketId);
        IParimutuelFacet.PoolView memory secondPool =
            IParimutuelFacet(address(diamond)).getParimutuelPool(secondMarketId);
        assertEq(firstPool.totalYesShares, 1_950e6);
        assertEq(firstPool.totalNoShares, 0);
        assertEq(secondPool.totalYesShares, 0);
        assertEq(secondPool.totalNoShares, 3_900e6);
    }

    function test_ClaimPayoutPaysWinningSideProRataAndDustSweepsToEligibleCreator() public {
        _setParimutuelFees(1_000, 1);
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(10_000, 0, 0);

        (bytes32 marketId, uint64 expiryTime, uint256 yesPositionId,) = _createDefaultParimutuelMarket("winning payout");

        // Each buy: amount=10, fee=1, netCollateral=9, epoch0 2x → shares=18
        _buyShares(alice, marketId, true, 10);
        _buyShares(bob, marketId, true, 10);
        _buyShares(carol, marketId, false, 10);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        // payoutPool=27, totalYesShares=36, alice has 18 yes shares
        // payout = 18 * 27 / 36 = 13
        (uint256 previewAlice, uint256 aliceWinningShares, uint256 totalWinningShares, uint256 payoutPool) =
            IParimutuelFacet(address(diamond)).previewPayout(marketId, alice);
        assertEq(previewAlice, 13);
        assertEq(aliceWinningShares, 18);
        assertEq(totalWinningShares, 36);
        assertEq(payoutPool, 27);

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        vm.prank(alice);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 13);
        assertEq(collateralToken.balanceOf(alice), aliceBefore + 13);
        assertEq(shareToken.balanceOf(alice, yesPositionId), 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ClaimableSharesRemain.selector, marketId, 18));
        IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId);

        vm.prank(bob);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 13);

        uint256 creatorBefore = collateralToken.balanceOf(creator);
        assertEq(IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId), 1);
        assertEq(collateralToken.balanceOf(creator), creatorBefore + 1);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.claimedPayout, 26);
        assertEq(pool.claimedClaimableShares, 36);
        assertTrue(pool.dustSwept);
    }

    function test_EveETHParimutuelEntryRoutesUnsupportedVaultShareToTreasury() public {
        SEveUSDCVault vault = new SEveUSDCVault(address(collateralToken), owner, treasury, 0, address(diamond));
        uint128 amount = 1 ether;

        _configureEveETHParimutuelProfile(0, 1, true);
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setStakingVault(address(vault));

        vm.prank(creator);
        bytes32 marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                "eveETH vault fallback",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days),
                DEFAULT_EPOCH_WINDOW
            );

        _fundEveETH(alice, amount);
        uint256 treasuryBefore = eveETH.balanceOf(treasury);
        uint256 vaultBefore = eveETH.balanceOf(address(vault));
        uint128 minted = _buyEveETHShares(alice, marketId, true, amount);

        assertEq(minted, 1.95 ether);
        assertEq(eveETH.balanceOf(treasury) - treasuryBefore, 0.02375 ether);
        assertEq(eveETH.balanceOf(address(vault)), vaultBefore);
        assertEq(vault.rewardLiability(address(eveETH)), 0);

        (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        assertEq(creatorFeesEscrowed, 0.00125 ether);
        assertEq(protocolFeesAccrued, 0.02375 ether);
    }

    function test_EveETHParimutuelWinningPayoutAndDustUseMarketCollateral() public {
        _setParimutuelFees(1_000, 1);
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(10_000, 0, 0);

        uint64 expiryTime = uint64(block.timestamp + 7 days);
        bytes32 marketId = _createEveETHParimutuelMarket("eveETH winning payout", 0, 1, expiryTime);

        _fundEveETH(alice, 10);
        _fundEveETH(bob, 10);
        _fundEveETH(carol, 10);
        uint256 creatorDefaultCollateralBefore = collateralToken.balanceOf(creator);
        _buyEveETHShares(alice, marketId, true, 10);
        _buyEveETHShares(bob, marketId, true, 10);
        _buyEveETHShares(carol, marketId, false, 10);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        uint256 aliceBefore = eveETH.balanceOf(alice);
        vm.prank(alice);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 13);
        assertEq(eveETH.balanceOf(alice), aliceBefore + 13);

        vm.prank(bob);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 13);

        uint256 creatorBefore = eveETH.balanceOf(creator);
        assertEq(IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId), 1);
        assertEq(eveETH.balanceOf(creator), creatorBefore + 1);
        assertEq(collateralToken.balanceOf(creator), creatorDefaultCollateralBefore);
    }

    function test_EveETHParimutuelInvalidRefundUsesMarketCollateral() public {
        _setParimutuelFees(0, 1);

        uint64 expiryTime = uint64(block.timestamp + 7 days);
        bytes32 marketId = _createEveETHParimutuelMarket("eveETH invalid refund", 0, 1, expiryTime);

        _fundEveETH(alice, 140);
        _buyEveETHShares(alice, marketId, true, 100);
        _buyEveETHShares(alice, marketId, false, 40);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Invalid));

        uint256 aliceBefore = eveETH.balanceOf(alice);
        vm.prank(alice);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 140);
        assertEq(eveETH.balanceOf(alice), aliceBefore + 140);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.claimedPayout, 140);
        assertEq(pool.claimedClaimableShares, 280);
    }

    function test_ClaimPayoutPaysNoOutcomeAndEmits() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime,, uint256 noPositionId) = _createDefaultParimutuelMarket("no payout");

        // 0% fee, epoch 0 (2x): alice YES 50 → 100 shares, bob NO 100 → 200 shares
        _buyShares(alice, marketId, true, 50);
        _buyShares(bob, marketId, false, 100);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.No));

        // payoutPool=150, totalNoShares=200, bob has 200 → payout = 200*150/200 = 150
        (uint256 preview, uint256 bobWinningShares, uint256 totalWinningShares, uint256 payoutPool) =
            IParimutuelFacet(address(diamond)).previewPayout(marketId, bob);
        assertEq(preview, 150);
        assertEq(bobWinningShares, 200);
        assertEq(totalWinningShares, 200);
        assertEq(payoutPool, 150);

        uint256 bobBefore = collateralToken.balanceOf(bob);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.ParimutuelPayoutClaimed(marketId, bob, noPositionId, 200, 150);
        vm.prank(bob);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 150);

        assertEq(collateralToken.balanceOf(bob), bobBefore + 150);
        assertEq(shareToken.balanceOf(bob, noPositionId), 0);
    }

    function test_PayoutPreviewAndClaimUseFinalizationSnapshot() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime,,) = _createDefaultParimutuelMarket("snapshot payout");

        // 0% fee, epoch 0 (2x): alice YES 100 → 200 shares, bob NO 100 → 200 shares
        _buyShares(alice, marketId, true, 100);
        _buyShares(bob, marketId, false, 100);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        ResolutionHarnessFacet(address(diamond)).setParimutuelPool(marketId, 1, 1, 1, 0, 0, false);

        // Snapshot: payoutPoolAtResolution=200, totalClaimableSharesAtResolution=200
        (uint256 preview, uint256 aliceWinningShares, uint256 totalWinningShares, uint256 payoutPool) =
            IParimutuelFacet(address(diamond)).previewPayout(marketId, alice);
        assertEq(preview, 200);
        assertEq(aliceWinningShares, 200);
        assertEq(totalWinningShares, 200);
        assertEq(payoutPool, 200);

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        vm.prank(alice);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 200);
        assertEq(collateralToken.balanceOf(alice), aliceBefore + 200);
    }

    function test_ClaimPayoutRefundsBothSidesWhenOutcomeIsInvalid() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime, uint256 yesPositionId, uint256 noPositionId) =
            _createDefaultParimutuelMarket("invalid refund");

        // 0% fee, epoch 0 (2x): alice YES 100 → 200 shares, alice NO 40 → 80 shares
        _buyShares(alice, marketId, true, 100);
        _buyShares(alice, marketId, false, 40);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Invalid));

        // payoutPool=140, totalClaimable=280, alice has 280 → payout = 280*140/280 = 140
        (uint256 preview, uint256 claimableShares, uint256 totalClaimableShares, uint256 payoutPool) =
            IParimutuelFacet(address(diamond)).previewPayout(marketId, alice);
        assertEq(preview, 140);
        assertEq(claimableShares, 280);
        assertEq(totalClaimableShares, 280);
        assertEq(payoutPool, 140);

        vm.prank(alice);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 140);

        assertEq(shareToken.balanceOf(alice, yesPositionId), 0);
        assertEq(shareToken.balanceOf(alice, noPositionId), 0);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.claimedPayout, 140);
        assertEq(pool.claimedClaimableShares, 280);
    }

    function test_RevertWhen_ClaimHasNoWinningShares() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime,,) = _createDefaultParimutuelMarket("no winning shares");

        _buyShares(bob, marketId, true, 100);
        _buyShares(alice, marketId, false, 100);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        vm.expectRevert(abi.encodeWithSelector(Errors.NoWinningShares.selector, marketId, alice));
        vm.prank(alice);
        IParimutuelFacet(address(diamond)).claimPayout(marketId);
    }

    function test_RevertWhen_ClaimBeforeResolution() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("early claim");
        _buyShares(alice, marketId, true, 1_000e6);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotResolved.selector, marketId));
        vm.prank(alice);
        IParimutuelFacet(address(diamond)).claimPayout(marketId);
    }

    function test_ZeroWinningSideResolutionRefundsAllShares() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime,, uint256 noPositionId) =
            _createDefaultParimutuelMarket("zero winner refund");

        // 0% fee, epoch 0 (2x): bob NO 120 → 240 shares
        _buyShares(bob, marketId, false, 120);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        // Effective outcome = Invalid (no yes shares), totalClaimable=240, payoutPool=120
        (uint256 claimable, uint256 winningShares, uint256 totalWinningShares,) =
            IParimutuelFacet(address(diamond)).previewPayout(marketId, bob);
        assertEq(claimable, 120);
        assertEq(winningShares, 240);
        assertEq(totalWinningShares, 240);

        vm.prank(bob);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 120);
        assertEq(shareToken.balanceOf(bob, noPositionId), 0);
    }

    function test_SweepDustRoutesToTreasuryWhenCreatorIneligible() public {
        (bytes32 marketId, uint256 noPositionId) = _resolveDustMarketWithAllWinningClaims("treasury dust");
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit Events.ParimutuelDustSwept(marketId, treasury, 1);
        assertEq(IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId), 1);

        assertEq(collateralToken.balanceOf(treasury), treasuryBefore + 1);
        assertEq(shareToken.balanceOf(carol, noPositionId), 2); // 1 collateral * 2x epoch multiplier
    }

    function test_RevertWhen_SweepDustAlreadySwept() public {
        (bytes32 marketId,) = _resolveDustMarketWithAllWinningClaims("already swept dust");

        assertEq(IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId), 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyClaimed.selector, marketId, address(this)));
        IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId);
    }

    function test_RevertWhen_SweepWouldCaptureUnclaimedWinningPayout() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime,,) = _createDefaultParimutuelMarket("unclaimed payout");

        // 0% fee, epoch 0 (2x): alice YES 2→4, bob YES 1→2, carol NO 1→2
        _buyShares(alice, marketId, true, 2);
        _buyShares(bob, marketId, true, 1);
        _buyShares(carol, marketId, false, 1);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        vm.prank(alice);
        IParimutuelFacet(address(diamond)).claimPayout(marketId);

        uint256 treasuryBefore = collateralToken.balanceOf(treasury);
        // bob still has 2 unclaimed shares
        vm.expectRevert(abi.encodeWithSelector(Errors.ClaimableSharesRemain.selector, marketId, 2));
        IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId);
        assertEq(collateralToken.balanceOf(treasury), treasuryBefore);
    }

    function test_IsParimutuelMarketReturnsFalseForUnknownAndCLOB() public {
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        _approveCreator(50e6);

        vm.prank(creator);
        bytes32 clobMarketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "clob false", "parimutuel", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true
            );

        assertFalse(IParimutuelFacet(address(diamond)).isParimutuelMarket(bytes32("missing")));
        assertFalse(IParimutuelFacet(address(diamond)).isParimutuelMarket(clobMarketId));
    }

    function test_RevertWhen_BuySharesBatchLengthsMismatch() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("batch mismatch");

        bytes32[] memory marketIds = new bytes32[](1);
        bool[] memory sides = new bool[](2);
        uint128[] memory amounts = new uint128[](1);
        uint128[] memory minSharesOut = new uint128[](1);
        marketIds[0] = marketId;

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 1, 2));
        IParimutuelFacet(address(diamond)).buySharesBatch(marketIds, sides, amounts, minSharesOut, alice);
    }

    function test_RevertWhen_BuySharesBatchMinSharesLengthMismatch() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("batch min mismatch");

        bytes32[] memory marketIds = new bytes32[](1);
        bool[] memory sides = new bool[](1);
        uint128[] memory amounts = new uint128[](1);
        uint128[] memory minSharesOut = new uint128[](2);
        marketIds[0] = marketId;

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 1, 2));
        IParimutuelFacet(address(diamond)).buySharesBatch(marketIds, sides, amounts, minSharesOut, alice);
    }

    function test_RevertWhen_BuySharesBatchEntryBelowMinSharesOut() public {
        _setParimutuelFees(0, 1);
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("batch min shares");

        bytes32[] memory marketIds = new bytes32[](2);
        bool[] memory sides = new bool[](2);
        uint128[] memory amounts = new uint128[](2);
        uint128[] memory minSharesOut = new uint128[](2);
        marketIds[0] = marketId;
        marketIds[1] = marketId;
        sides[0] = true;
        sides[1] = false;
        amounts[0] = 100;
        amounts[1] = 100;
        minSharesOut[0] = 200;
        minSharesOut[1] = 201;

        vm.startPrank(alice);
        collateralToken.approve(address(diamond), 200);
        vm.expectRevert(abi.encodeWithSelector(Errors.SlippageExceeded.selector, uint128(200), uint128(201)));
        IParimutuelFacet(address(diamond)).buySharesBatch(marketIds, sides, amounts, minSharesOut, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_BuySharesForCLOBMarket() public {
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        _approveCreator(50e6);

        vm.prank(creator);
        bytes32 clobMarketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "clob market", "parimutuel", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true
            );

        vm.prank(alice);
        collateralToken.approve(address(diamond), 1_000e6);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotParimutuelMarket.selector, clobMarketId));
        vm.prank(alice);
        IParimutuelFacet(address(diamond)).buyShares(clobMarketId, true, 1_000e6, alice, 0);
    }

    function _resolveDustMarketWithAllWinningClaims(string memory label)
        internal
        returns (bytes32 marketId, uint256 noPositionId)
    {
        _setParimutuelFees(0, 1);
        uint64 expiryTime;
        (marketId, expiryTime,, noPositionId) = _createDefaultParimutuelMarket(label);

        // 0% fee, epoch 0 (2x): alice YES 2→4 shares, bob YES 1→2 shares, carol NO 1→2 shares
        // payoutPool=4, totalYesShares=6
        _buyShares(alice, marketId, true, 2);
        _buyShares(bob, marketId, true, 1);
        _buyShares(carol, marketId, false, 1);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        // alice: 4*4/6=2, bob: 2*4/6=1, dust=1
        vm.prank(alice);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 2);
        vm.prank(bob);
        assertEq(IParimutuelFacet(address(diamond)).claimPayout(marketId), 1);
    }

    // ── Epoch Multiplier Tests ──────────────────────────────────────────

    function test_EpochMultiplierReturns2xInEpochZero() public {
        (bytes32 marketId,,,) = _createDefaultParimutuelMarket("epoch zero");

        (uint256 multiplierBps, uint256 epoch) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(multiplierBps, 20_000); // 2.0x
        assertEq(epoch, 0);
    }

    function test_EpochMultiplierDefaultsCoverAllEightEpochs() public {
        uint64 duration = 7 days;
        (bytes32 marketId, uint64 expiryTime,,) = _createDefaultParimutuelMarket("epoch decay");
        uint64 createdAt = expiryTime - duration;

        uint16[8] memory expected = [uint16(20_000), 15_000, 11_500, 10_000, 8_500, 7_000, 5_500, 4_000];
        uint16[8] memory schedule = IParimutuelFacet(address(diamond)).getParimutuelEpochMultipliers();

        for (uint256 epoch = 0; epoch < expected.length; ++epoch) {
            assertEq(schedule[epoch], expected[epoch]);

            vm.warp(createdAt + ((duration * uint64(epoch)) / 8));
            (uint256 multiplierBps, uint256 activeEpoch) =
                IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
            assertEq(multiplierBps, expected[epoch]);
            assertEq(activeEpoch, epoch);
        }
    }

    function test_EpochMultiplierUsesConfiguredSchedule() public {
        uint16[8] memory custom = [uint16(10_001), 10_002, 10_003, 10_004, 10_005, 10_006, 10_007, 10_008];

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(diamond));
        emit Events.ParimutuelEpochMultipliersUpdated(custom);
        OwnershipFacet(address(diamond)).setParimutuelEpochMultipliers(custom);

        uint16[8] memory stored = IParimutuelFacet(address(diamond)).getParimutuelEpochMultipliers();
        for (uint256 epoch = 0; epoch < custom.length; ++epoch) {
            assertEq(stored[epoch], custom[epoch]);
        }

        uint64 duration = 8 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("configured epochs", "parimutuel", expiryTime, duration);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        vm.warp(createdAt + (duration * 5 / 8));
        (uint256 multiplierBps, uint256 activeEpoch) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(multiplierBps, custom[5]);
        assertEq(activeEpoch, 5);
    }

    function test_EpochMultiplierConfigRequiresOwnerAndBounds() public {
        uint16[8] memory custom = [uint16(10_001), 10_002, 10_003, 10_004, 10_005, 10_006, 10_007, 10_008];

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, alice));
        OwnershipFacet(address(diamond)).setParimutuelEpochMultipliers(custom);

        custom[3] = 0;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParimutuelEpochMultiplier.selector, 3, 0));
        OwnershipFacet(address(diamond)).setParimutuelEpochMultipliers(custom);

        custom[3] = 50_001;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParimutuelEpochMultiplier.selector, 3, 50_001));
        OwnershipFacet(address(diamond)).setParimutuelEpochMultipliers(custom);
    }

    function test_EpochMultiplierAffectsSharesMintedPerEpoch() public {
        _setParimutuelFees(0, 1);
        uint64 duration = 8 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("epoch shares", "parimutuel", expiryTime, duration);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        uint128 amount = 100e6;

        // Epoch 0 (2x): 100e6 collateral → 200e6 shares
        uint128 minted0 = _buyShares(alice, marketId, true, amount);
        assertEq(minted0, 200e6);

        // Epoch 1 (1.5x): warp to 12.5%
        vm.warp(createdAt + (duration / 8));
        uint128 minted1 = _buyShares(bob, marketId, true, amount);
        assertEq(minted1, 150e6);

        // Epoch 2 (1.15x): warp to 25%
        vm.warp(createdAt + (duration * 2 / 8));
        uint128 minted2 = _buyShares(carol, marketId, true, amount);
        assertEq(minted2, 115e6);

        // Epoch 3 (1x): warp to 37.5%
        vm.warp(createdAt + (duration * 3 / 8));
        uint128 minted3 = _buyShares(alice, marketId, true, amount);
        assertEq(minted3, 100e6);

        // Epochs 4-7 apply progressively larger late-entry haircuts.
        vm.warp(createdAt + (duration * 4 / 8));
        uint128 minted4 = _buyShares(bob, marketId, true, amount);
        assertEq(minted4, 85e6);

        vm.warp(createdAt + (duration * 5 / 8));
        uint128 minted5 = _buyShares(carol, marketId, true, amount);
        assertEq(minted5, 70e6);

        vm.warp(createdAt + (duration * 6 / 8));
        uint128 minted6 = _buyShares(alice, marketId, true, amount);
        assertEq(minted6, 55e6);

        vm.warp(createdAt + (duration * 7 / 8));
        uint128 minted7 = _buyShares(bob, marketId, true, amount);
        assertEq(minted7, 40e6);

        // payoutPool tracks collateral: 8 * 100e6 = 800e6
        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertEq(pool.payoutPool, 800e6);
        // totalYesShares = 200 + 150 + 115 + 100 + 85 + 70 + 55 + 40 = 815e6
        assertEq(pool.totalYesShares, 815e6);
    }

    function test_RevertWhen_LateHaircutRoundsSharesToZero() public {
        _setParimutuelFees(0, 1);
        uint64 duration = 8 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("zero haircut shares", "parimutuel", expiryTime, duration);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        vm.warp(createdAt + (duration * 7 / 8));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ParimutuelSharesWouldRoundToZero.selector, marketId, uint128(1), 4_000)
        );
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1, alice, 0);
    }

    function test_RevertWhen_MultipliedSharesExceedUint128() public {
        _setParimutuelFees(0, 1);
        uint16[8] memory custom = [uint16(50_000), 50_000, 50_000, 50_000, 50_000, 50_000, 50_000, 50_000];

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setParimutuelEpochMultipliers(custom);

        bytes32 marketId = _createParimutuelMarket("share overflow", "parimutuel", uint64(block.timestamp + 8 days));
        uint256 computedShares = (uint256(type(uint128).max) * 50_000) / 10_000;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, computedShares));
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, type(uint128).max, alice, 0);
    }

    function test_EarlyEntrantGetsLargerPayoutShareThanLateEntrant() public {
        _setParimutuelFees(0, 1);
        uint64 duration = 8 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("early vs late", "parimutuel", expiryTime, duration);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        // Alice enters epoch 0 (2x): 1000 collateral → 2000 YES shares
        _buyShares(alice, marketId, true, 1_000e6);

        // Bob enters epoch 7 (0.4x): 1000 collateral → 400 YES shares
        vm.warp(createdAt + (duration * 7 / 8));
        _buyShares(bob, marketId, true, 1_000e6);

        // Carol enters NO in epoch 7: 1000 collateral → 400 NO shares
        _buyShares(carol, marketId, false, 1_000e6);

        // payoutPool = 3000e6, totalYesShares = 2400e6
        // Resolve YES
        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        // Alice: 2000 * 3000e6 / 2400e6 = 2500e6
        // Bob: 400 * 3000e6 / 2400e6 = 500e6
        (uint256 alicePayout,,,) = IParimutuelFacet(address(diamond)).previewPayout(marketId, alice);
        (uint256 bobPayout,,,) = IParimutuelFacet(address(diamond)).previewPayout(marketId, bob);

        assertEq(alicePayout, 2_500e6);
        assertEq(bobPayout, 500e6);
        assertGt(alicePayout, bobPayout); // early entrant rewarded
    }

    function test_ParimutuelBuyFinalizeAndClaimPreservesEighteenDecimalCollateral() public {
        _setParimutuelFees(DEFAULT_ENTRY_FEE_BPS, 1e18);
        collateralToken.mint(alice, 2_000e18);
        collateralToken.mint(bob, 2_000e18);
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        bytes32 marketId = _createParimutuelMarket("18 decimal parimutuel", "parimutuel", expiryTime);

        uint128 aliceShares = _buyShares(alice, marketId, true, 1_000e18);
        uint128 bobShares = _buyShares(bob, marketId, false, 1_000e18);
        assertEq(aliceShares, 1_950e18);
        assertEq(bobShares, 1_950e18);

        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = IParimutuelFacet(address(diamond)).claimPayout(marketId);

        assertEq(payout, 1_950e18);
        assertEq(collateralToken.balanceOf(alice), aliceBefore + 1_950e18);
    }

    function test_InvalidOutcomeProRataRefundsEarlyEntrantMore() public {
        _setParimutuelFees(0, 1);
        uint64 duration = 8 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("invalid prorata", "parimutuel", expiryTime, duration);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        // Alice enters epoch 0 (2x): 500 collateral → 1000 YES shares
        _buyShares(alice, marketId, true, 500e6);

        // Bob enters epoch 7 (0.4x): 500 collateral → 200 NO shares
        vm.warp(createdAt + (duration * 7 / 8));
        _buyShares(bob, marketId, false, 500e6);

        // payoutPool = 1000e6, totalShares = 1200
        // Resolve Invalid → pro-rata
        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, uint8(LibEveMarket.MarketOutcome.Invalid));
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        // Alice: 1000 shares * 1000e6 / 1200 = 833_333_333
        // Bob: 200 shares * 1000e6 / 1200 = 166_666_666
        (uint256 alicePayout,,,) = IParimutuelFacet(address(diamond)).previewPayout(marketId, alice);
        (uint256 bobPayout,,,) = IParimutuelFacet(address(diamond)).previewPayout(marketId, bob);

        assertEq(alicePayout, 833_333_333);
        assertEq(bobPayout, 166_666_666);
        // Alice deposited 500e6 but gets back 666e6 — rewarded for early entry
        assertGt(alicePayout, 500e6);
        // Bob deposited 500e6 but gets back 333e6 — penalized for late entry
        assertLt(bobPayout, 500e6);
    }

    function test_CreateParimutuelMarketStoresCustomEpochWindow() public {
        uint64 duration = 30 days;
        uint64 epochWindow = 4 hours;
        uint64 expiryTime = uint64(block.timestamp + duration);

        bytes32 marketId = _createParimutuelMarket("custom epoch window", "parimutuel", expiryTime, epochWindow);

        assertEq(IParimutuelFacet(address(diamond)).getParimutuelEpochWindow(marketId), epochWindow);
    }

    function test_CustomEpochWindowAdvancesEpochsAndClampsBeforeExpiry() public {
        uint64 duration = 30 days;
        uint64 epochWindow = 4 hours;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("custom epoch advance", "parimutuel", expiryTime, epochWindow);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        (uint256 mult0, uint256 ep0) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(mult0, 20_000);
        assertEq(ep0, 0);

        vm.warp(createdAt + 30 minutes);
        (uint256 mult1, uint256 ep1) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(mult1, 15_000);
        assertEq(ep1, 1);

        vm.warp(createdAt + 2 hours);
        (uint256 mult4, uint256 ep4) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(mult4, 8_500);
        assertEq(ep4, 4);

        vm.warp(createdAt + epochWindow);
        (uint256 mult7, uint256 ep7) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(mult7, 4_000);
        assertEq(ep7, 7);

        vm.warp(createdAt + 20 days);
        (uint256 multLate, uint256 epLate) = IParimutuelFacet(address(diamond)).getEpochMultiplier(marketId);
        assertEq(multLate, 4_000);
        assertEq(epLate, 7);
    }

    function test_RevertWhen_ParimutuelEpochWindowIsZero() public {
        uint64 expiryTime = uint64(block.timestamp + 7 days);

        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParimutuelEpochWindow.selector, 0, uint64(7 days)));
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "zero epoch window", "parimutuel", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0
            );
    }

    function test_RevertWhen_ParimutuelEpochWindowExceedsCap() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(4 hours);

        uint64 duration = 7 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        uint64 epochWindow = 4 hours + 1;

        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidParimutuelEpochWindow.selector, epochWindow, uint64(4 hours))
        );
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "epoch exceeds cap",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                epochWindow
            );
    }

    function test_RevertWhen_ParimutuelEpochWindowExceedsMarketDuration() public {
        uint64 duration = 2 days;
        uint64 expiryTime = uint64(block.timestamp + duration);
        uint64 epochWindow = duration + 1;

        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParimutuelEpochWindow.selector, epochWindow, duration));
        vm.prank(creator);
        IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "epoch exceeds duration",
                "parimutuel",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                expiryTime,
                epochWindow
            );
    }

    function test_CustomEpochWindowAffectsSharesMintedOnLongMarket() public {
        _setParimutuelFees(0, 1);

        uint64 duration = 30 days;
        uint64 epochWindow = 4 hours;
        uint64 expiryTime = uint64(block.timestamp + duration);
        bytes32 marketId = _createParimutuelMarket("custom epoch shares", "parimutuel", expiryTime, epochWindow);
        (, uint64 createdAt,,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        uint128 amount = 100e6;

        uint128 minted0 = _buyShares(alice, marketId, true, amount);
        assertEq(minted0, 200e6);

        vm.warp(createdAt + 2 hours);
        uint128 minted4 = _buyShares(bob, marketId, true, amount);
        assertEq(minted4, 85e6);

        vm.warp(createdAt + 20 days);
        uint128 mintedLate = _buyShares(carol, marketId, true, amount);
        assertEq(mintedLate, 40e6);
    }

    function _createDefaultParimutuelMarket(string memory label)
        internal
        returns (bytes32 marketId, uint64 expiryTime, uint256 yesPositionId, uint256 noPositionId)
    {
        expiryTime = uint64(block.timestamp + 7 days);
        marketId = _createParimutuelMarket(label, "parimutuel", expiryTime);
        (,,,, yesPositionId, noPositionId) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
    }

    function _createParimutuelMarket(string memory question, string memory category, uint64 expiryTime)
        internal
        returns (bytes32 marketId)
    {
        marketId = _createParimutuelMarket(question, category, expiryTime, DEFAULT_EPOCH_WINDOW);
    }

    function _createParimutuelMarket(
        string memory question,
        string memory category,
        uint64 expiryTime,
        uint64 epochWindow
    ) internal returns (bytes32 marketId) {
        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, epochWindow
            );
    }

    function _buyShares(address buyer, bytes32 marketId, bool isYes, uint128 amount) internal returns (uint128 minted) {
        vm.startPrank(buyer);
        collateralToken.approve(address(diamond), amount);
        minted = IParimutuelFacet(address(diamond)).buyShares(marketId, isYes, amount, buyer, 0);
        vm.stopPrank();
    }

    function _buyEveETHShares(address buyer, bytes32 marketId, bool isYes, uint128 amount)
        internal
        returns (uint128 minted)
    {
        vm.prank(buyer);
        minted = IParimutuelFacet(address(diamond)).buyShares(marketId, isYes, amount, buyer, 0);
    }

    function _createEveETHParimutuelMarket(string memory question, uint128 seedAmount, uint128 minEntry)
        internal
        returns (bytes32 marketId)
    {
        string memory category = "parimutuel";
        uint64 tradingStartTime = uint64(block.timestamp);
        uint64 expiryTime = tradingStartTime + 7 days;
        bytes32 expectedMarketId = _profileParimutuelMarketId(question, category, tradingStartTime, expiryTime);

        _configureEveETHParimutuelProfile(seedAmount, minEntry, true);
        _fundEveETH(creator, seedAmount);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                question,
                category,
                DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime,
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );
        assertEq(marketId, expectedMarketId);
    }

    function _createEveETHParimutuelMarket(
        string memory question,
        uint128 seedAmount,
        uint128 minEntry,
        uint64 expiryTime
    ) internal returns (bytes32 marketId) {
        string memory category = "parimutuel";
        uint64 tradingStartTime = uint64(block.timestamp);
        bytes32 expectedMarketId = _profileParimutuelMarketId(question, category, tradingStartTime, expiryTime);

        _configureEveETHParimutuelProfile(seedAmount, minEntry, true);
        _fundEveETH(creator, seedAmount);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                question,
                category,
                DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime,
                expiryTime,
                DEFAULT_EPOCH_WINDOW
            );
        assertEq(marketId, expectedMarketId);
    }

    function _configureEveETHParimutuelProfile(uint128 seedAmount, uint128 minEntry, bool enabled) internal {
        vm.startPrank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(EVE_ETH_PROFILE_ID, address(eveETH), address(weth), EVE_ETH_PAYOUT_UNIT, 0, enabled);
        OwnershipFacet(address(diamond))
            .setCollateralProfileParimutuelCreationSeedAmount(EVE_ETH_PROFILE_ID, seedAmount);
        OwnershipFacet(address(diamond)).setCollateralProfileParimutuelMinEntry(EVE_ETH_PROFILE_ID, minEntry);
        vm.stopPrank();

        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);
    }

    function _fundEveETH(address account, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        vm.deal(account, amount);
        vm.startPrank(account);
        weth.deposit{value: amount}();
        weth.approve(address(eveETH), amount);
        eveETH.wrap(amount, account);
        eveETH.approve(address(diamond), type(uint256).max);
        vm.stopPrank();
    }

    function _finalizeCreatorResolution(bytes32 marketId, uint64 expiryTime, uint8 outcome) internal {
        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, outcome);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }

    function _setParimutuelFees(uint16 entryFeeBps, uint128 minEntry) internal {
        ResolutionHarnessFacet(address(diamond)).setParimutuelConfig(address(shareToken), entryFeeBps, minEntry);
    }

    function _assertDefaultEntryFee(bytes32 marketId) internal view {
        (uint128 totalFee, uint128 creatorFee, uint128 protocolFee, uint128 vaultFee, uint128 netShares) =
            IParimutuelFacet(address(diamond)).previewEntryFee(marketId, 1_000e6);

        assertEq(totalFee, 25e6);
        assertEq(creatorFee, 1_250_000);
        assertEq(protocolFee, 23_750_000);
        assertEq(vaultFee, 0);
        assertEq(netShares, 975e6);
    }

    function _assertParimutuelMarketCreatedLog(Vm.Log memory entry, bytes32 marketId) internal view {
        assertEq(entry.emitter, address(diamond));
        assertEq(
            entry.topics[0],
            keccak256(
                "MarketCreated(bytes32,uint8,address,uint8,address,address,bytes32,bytes32,uint256,uint256,string,uint64)"
            )
        );
        assertEq(entry.topics[1], marketId);
        assertEq(entry.topics[2], bytes32(uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL))));
        assertEq(entry.topics[3], bytes32(uint256(uint160(owner))));

        assertGt(entry.data.length, 0);
    }

    function _assertMarketDisplayMetadataLog(Vm.Log memory entry, bytes32 marketId) internal view {
        assertEq(entry.emitter, address(diamond));
        assertEq(
            entry.topics[0],
            keccak256(
                "MarketDisplayMetadataSet(bytes32,string,string,string,string,string,string,string,string,bytes32,bytes32)"
            )
        );
        assertEq(entry.topics[1], marketId);
        assertGt(entry.data.length, 0);
    }

    function _assertLegacyParimutuelMarketCreatedLog(Vm.Log memory entry, uint64 expiryTime, bytes32 marketId)
        internal
        view
    {
        assertEq(entry.emitter, address(diamond));
        assertEq(
            entry.topics[0], keccak256("ParimutuelMarketCreated(bytes32,address,address,uint256,uint256,uint64,uint64)")
        );
        assertEq(entry.topics[1], marketId);
        assertEq(entry.topics[2], bytes32(uint256(uint160(owner))));
        assertEq(entry.topics[3], bytes32(uint256(uint160(address(shareToken)))));

        (uint256 yesPositionId, uint256 noPositionId, uint64 loggedExpiryTime, uint64 loggedEpochWindow) =
            abi.decode(entry.data, (uint256, uint256, uint64, uint64));
        assertEq(yesPositionId, _parimutuelYesPositionId(marketId));
        assertEq(noPositionId, _parimutuelNoPositionId(marketId));
        assertEq(loggedExpiryTime, expiryTime);
        assertEq(loggedEpochWindow, DEFAULT_EPOCH_WINDOW);
    }

    function _assertSeedEventAfterCreation(Vm.Log[] memory entries, bytes32 marketId, uint128 seedAmount)
        internal
        view
    {
        uint256 marketCreatedIndex = _findLogIndex(
            entries,
            keccak256(
                "MarketCreated(bytes32,uint8,address,uint8,address,address,bytes32,bytes32,uint256,uint256,string,uint64)"
            )
        );
        uint256 parimutuelCreatedIndex = _findLogIndex(
            entries, keccak256("ParimutuelMarketCreated(bytes32,address,address,uint256,uint256,uint64,uint64)")
        );
        uint256 seededIndex = _findLogIndex(entries, keccak256("ParimutuelCreationSeeded(bytes32,address,uint128)"));

        assertLt(marketCreatedIndex, seededIndex);
        assertLt(parimutuelCreatedIndex, seededIndex);
        assertEq(entries[marketCreatedIndex].topics[1], marketId);
        assertEq(entries[marketCreatedIndex].topics[3], entries[seededIndex].topics[2]);
        assertEq(entries[parimutuelCreatedIndex].topics[1], marketId);
        assertEq(entries[parimutuelCreatedIndex].topics[2], entries[seededIndex].topics[2]);
        assertEq(entries[seededIndex].topics[0], keccak256("ParimutuelCreationSeeded(bytes32,address,uint128)"));
        assertEq(entries[seededIndex].topics[1], marketId);
        assertEq(entries[seededIndex].topics[2], bytes32(uint256(uint160(creator))));
        assertEq(abi.decode(entries[seededIndex].data, (uint128)), seedAmount);
    }

    function _assertCollateralProfileLog(Vm.Log[] memory entries, bytes32 marketId, uint128 seedAmount) internal view {
        uint256 profileIndex =
            _findLogIndex(entries, keccak256("MarketCollateralProfile(bytes32,uint8,address,uint128,uint128)"));
        assertLt(profileIndex, entries.length);
        assertEq(entries[profileIndex].topics[1], marketId);
        assertEq(entries[profileIndex].topics[2], bytes32(uint256(EVE_ETH_PROFILE_ID)));
        assertEq(entries[profileIndex].topics[3], bytes32(uint256(uint160(address(eveETH)))));

        (uint128 payoutUnit, uint128 creationFee) = abi.decode(entries[profileIndex].data, (uint128, uint128));
        assertEq(payoutUnit, EVE_ETH_PAYOUT_UNIT);
        assertEq(creationFee, seedAmount);
    }

    function _findLogIndex(Vm.Log[] memory entries, bytes32 topic0) internal pure returns (uint256) {
        for (uint256 index; index < entries.length; ++index) {
            if (entries[index].topics[0] == topic0) {
                return index;
            }
        }
        return type(uint256).max;
    }

    function _parimutuelMarketId(
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime
    ) internal view returns (bytes32) {
        return LibMarketCreation.marketIdFor(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.PARIMUTUEL,
            LibEveMarket.PositionTokenType.PARIMUTUEL
        );
    }

    function _profileParimutuelMarketId(
        string memory question,
        string memory category,
        uint64 tradingStartTime,
        uint64 expiryTime
    ) internal view returns (bytes32) {
        return LibMarketCreation.profileMarketIdFor(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(eveETH),
            EVE_ETH_PROFILE_ID,
            EVE_ETH_PAYOUT_UNIT,
            LibEveMarket.MarketType.PARIMUTUEL,
            LibEveMarket.PositionTokenType.PARIMUTUEL
        );
    }

    function _parimutuelYesPositionId(bytes32 marketId) internal view returns (uint256) {
        return LibMarketCreation.parimutuelPositionId(address(diamond), marketId, 1);
    }

    function _parimutuelNoPositionId(bytes32 marketId) internal view returns (uint256) {
        return LibMarketCreation.parimutuelPositionId(address(diamond), marketId, 2);
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
