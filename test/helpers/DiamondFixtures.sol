// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {EveMarketDiamond} from "../../src/EveMarketDiamond.sol";
import {EvesNegRiskAdapter} from "../../src/EvesNegRiskAdapter.sol";
import {BondManagerFacet} from "../../src/facets/BondManagerFacet.sol";
import {BondTokenGateFacet} from "../../src/facets/BondTokenGateFacet.sol";
import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {FeeRouterFacet} from "../../src/facets/FeeRouterFacet.sol";
import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {MarketGroupFacet} from "../../src/facets/MarketGroupFacet.sol";
import {MarketSettlementFacet} from "../../src/facets/MarketSettlementFacet.sol";
import {MarketViewFacet} from "../../src/facets/MarketViewFacet.sol";
import {NegRiskConfigFacet} from "../../src/facets/NegRiskConfigFacet.sol";
import {OBRResolutionFacet} from "../../src/facets/OBRResolutionFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {ResolverJuryFacet} from "../../src/facets/ResolverJuryFacet.sol";
import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {CollateralTradeRouterFacet} from "../../src/facets/CollateralTradeRouterFacet.sol";
import {CollateralTradeRouterExactFacet} from "../../src/facets/CollateralTradeRouterExactFacet.sol";
import {CollateralTradeRouterSellFacet} from "../../src/facets/CollateralTradeRouterSellFacet.sol";
import {CollateralTradeRouterPreviewFacet} from "../../src/facets/CollateralTradeRouterPreviewFacet.sol";
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
import {IFeeRouterFacet} from "../../src/interfaces/IFeeRouterFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {IEvesNegRiskAdapter} from "../../src/interfaces/IEvesNegRiskAdapter.sol";
import {INegRiskConfigFacet} from "../../src/interfaces/INegRiskConfigFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {IResolverJuryFacet} from "../../src/interfaces/IResolverJuryFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {LibParimutuel} from "../../src/libraries/LibParimutuel.sol";

import {ERC1155ReceiverHarness} from "./ERC1155ReceiverHarness.sol";
import {MockConditionalTokens} from "./MockConditionalTokens.sol";
import {MockCurveProfile} from "./MockCurveProfile.sol";
import {MockCollateral} from "./MockCollateral.sol";
import {MockEveToken} from "./MockEveToken.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract RoutingProbeFacet {
    bytes32 internal constant WORD_SLOT = bytes32(uint256(keccak256("eve.prediction.market.routing.probe.word")) - 1);

    function storeWord(uint256 newWord) external {
        bytes32 slot = WORD_SLOT;
        assembly {
            sstore(slot, newWord)
        }
    }

    function readWord() external view returns (uint256 word) {
        bytes32 slot = WORD_SLOT;
        assembly {
            word := sload(slot)
        }
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

contract RoutingProbeFacetV2 {
    bytes32 internal constant WORD_SLOT = bytes32(uint256(keccak256("eve.prediction.market.routing.probe.word")) - 1);

    function storeWord(uint256 newWord) external {
        bytes32 slot = WORD_SLOT;
        assembly {
            sstore(slot, newWord)
        }
    }

    function readWord() external view returns (uint256 word) {
        bytes32 slot = WORD_SLOT;
        assembly {
            word := sload(slot)
        }
    }

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract StateProbeFacet {
    function orderbookEntryFeeBps() external view returns (uint16) {
        return LibEveMarket.store().config.orderbookFeeConfig.entryFeeBps;
    }

    function spotTradeFeeBps() external view returns (uint16) {
        return LibEveMarket.store().config.spotFeeConfig.tradeFeeBps;
    }

    function permissionlessCreationEnabled() external view returns (bool) {
        return LibEveMarket.store().config.permissionlessCreationEnabled;
    }

    function marketCreationFee() external view returns (uint128) {
        return LibEveMarket.store().config.marketCreationFee;
    }

    function parimutuelCreationSeedAmount() external view returns (uint128) {
        return LibEveMarket.store().config.parimutuelCreationSeedAmount;
    }

    function spotBookCreationFee() external view returns (uint128) {
        return LibEveMarket.store().config.spotBookCreationFee;
    }

    function marketCreationBond() external view returns (uint128) {
        return LibEveMarket.store().config.marketCreationBond;
    }

    function collateralToken() external view returns (address) {
        return LibEveMarket.store().config.collateralToken;
    }

    function seniorPoolRevenueBps() external view returns (uint16) {
        return LibEveMarket.store().config.orderbookFeeConfig.seniorPoolFeeBps;
    }

    function parimutuelShareToken() external view returns (address) {
        return LibEveMarket.store().config.parimutuelShareToken;
    }

    function parimutuelEntryFeeBps() external view returns (uint16) {
        return LibEveMarket.store().config.parimutuelFeeConfig.entryFeeBps;
    }

    function parimutuelMinEntry() external view returns (uint128) {
        return LibEveMarket.store().config.parimutuelMinEntry;
    }

    function minMarketDuration() external view returns (uint64) {
        return LibEveMarket.store().config.minMarketDuration;
    }

    function maxMarketDuration() external view returns (uint64) {
        return LibEveMarket.store().config.maxMarketDuration;
    }

    function curveProfile(uint8 profileId) external view returns (address) {
        return LibEveMarket.store().curveProfiles[profileId];
    }

    function nextCurveId() external view returns (uint256) {
        return LibEveMarket.store().nextCurveId;
    }

    function setBookPricingFixture(
        bytes32 bookId,
        uint256 pricingMode,
        uint256 tickSize,
        uint256 priceDenominator,
        uint256 minTick,
        uint256 maxTick
    ) external {
        if (pricingMode > uint256(uint8(LibEveMarket.BookPricingMode.GENERIC))) {
            revert Errors.InvalidAmount(pricingMode);
        }
        if (tickSize == 0 || tickSize > type(uint128).max) {
            revert Errors.InvalidAmount(tickSize);
        }
        if (priceDenominator == 0 || priceDenominator > type(uint128).max) {
            revert Errors.InvalidAmount(priceDenominator);
        }
        if (minTick > type(uint128).max || maxTick > type(uint128).max || minTick > maxTick) {
            revert Errors.InvalidAmount(minTick > type(uint128).max ? minTick : maxTick);
        }

        LibEveMarket.Book storage book = LibEveMarket.store().books[bookId];
        if (book.bookId != bookId) {
            revert Errors.BookNotFound(bookId);
        }

        book.pricingMode = LibEveMarket.BookPricingMode(uint8(pricingMode));
        book.tickSize = uint128(tickSize);
        book.priceDenominator = uint128(priceDenominator);
        book.minTick = uint128(minTick);
        book.maxTick = uint128(maxTick);
    }

    function materializeMarketSideBookFixture(bytes32 marketId, bool isYesSide) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        LibCLOBBook.ensureMarketSideBook(state, market, isYesSide);
    }

    function isBookMaterializedFixture(bytes32 bookId) external view returns (bool materialized) {
        materialized = LibEveMarket.store().books[bookId].bookId == bookId;
    }

    function getStoredMarketCore(bytes32 marketId)
        external
        view
        returns (
            address collateralToken_,
            address creator,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId
        )
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        collateralToken_ = market.collateralToken;
        creator = market.creator;
        questionId = market.questionId;
        conditionId = market.conditionId;
        yesPositionId = market.yesPositionId;
        noPositionId = market.noPositionId;
    }

    function getStoredMarketTypeAndPositionToken(bytes32 marketId)
        external
        view
        returns (uint8 marketType, address positionToken)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        marketType = uint8(market.marketType);
        positionToken = market.positionToken;
    }

    function getStoredMarketResolutionId(bytes32 marketId) external view returns (bytes32 resolutionId) {
        resolutionId = LibEveMarket.store().markets[marketId].resolutionId;
    }

    function getStoredMarketStatus(bytes32 marketId)
        external
        view
        returns (
            bytes32 storedMarketId,
            uint64 createdAt,
            uint64 expiryTime,
            uint96 lastTradePrice,
            uint128 creationFeePaid,
            uint8 outcome,
            uint8 state,
            uint256 curveCount
        )
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        storedMarketId = market.marketId;
        createdAt = market.createdAt;
        expiryTime = market.expiryTime;
        lastTradePrice = market.lastTradePrice;
        creationFeePaid = market.creationFeePaid;
        outcome = uint8(market.outcome);
        state = uint8(market.state);
        curveCount = market.curveCount;
    }

    function getStoredCurve(uint256 curveId)
        external
        view
        returns (
            uint256 packed,
            uint128 remainingVolume,
            uint64 createdAt,
            uint32 generation,
            bool active,
            bool isYesSide,
            address maker,
            bytes32 marketId
        )
    {
        LibEveMarket.StoredCurve storage curve = LibEveMarket.store().curves[curveId];
        packed = curve.packed;
        remainingVolume = curve.remainingVolume;
        createdAt = curve.createdAt;
        generation = curve.generation;
        active = curve.active;
        isYesSide = curve.isYesSide;
        maker = curve.maker;
        marketId = LibEveMarket.store().books[curve.bookId].marketId;
    }

    function getStoredMarketFees(bytes32 marketId)
        external
        view
        returns (
            uint128 creatorFeesEscrowed,
            uint128 protocolFeesAccrued,
            bool creatorFeesClaimed,
            bool creatorFeeEligible
        )
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        creatorFeesEscrowed = market.creatorFeesEscrowed;
        protocolFeesAccrued = market.protocolFeesAccrued;
        creatorFeesClaimed = market.creatorFeesClaimed;
        creatorFeeEligible = market.creatorFeeEligible;
    }

    function getStoredCreationBond(bytes32 marketId)
        external
        view
        returns (uint128 creationBond, bool creationBondReleased)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        creationBond = market.creationBond;
        creationBondReleased = market.creationBondReleased;
    }

    function getStoredCreatorStatus(bytes32 marketId)
        external
        view
        returns (bool creatorSettledHonestly, bool creatorFeeEligible, bool creationBondReturnable)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        creatorSettledHonestly = market.creatorSettledHonestly;
        creatorFeeEligible = market.creatorFeeEligible;
        creationBondReturnable = market.creationBondReturnable;
    }

    function getStoredMarketTrading(bytes32 marketId)
        external
        view
        returns (uint96 lastTradePrice, uint128 totalFeePool, uint128 totalQuoteVolume)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        lastTradePrice = market.lastTradePrice;
        totalFeePool = market.totalFeePool;
        totalQuoteVolume = market.totalQuoteVolume;
    }

    function getStoredMakerAccounting(bytes32 marketId, address maker)
        external
        view
        returns (uint128 makerQuoteVolume, uint128 makerFeesAccrued, uint128 makerFeesClaimed)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        makerQuoteVolume = market.makerQuoteVolume[maker];
        makerFeesAccrued = market.makerFeesAccrued[maker];
        makerFeesClaimed = market.makerFeesClaimed[maker];
    }

    function getStoredResolution(bytes32 marketId)
        external
        view
        returns (
            address proposer,
            uint8 proposedOutcome,
            uint8 escalationLevel,
            bool disputed,
            uint128 bondAmount,
            uint64 proposedAt,
            uint64 disputeDeadline,
            uint64 snapshotBlock
        )
    {
        LibEveMarket.Resolution storage resolution = LibEveMarket.store().resolutions[marketId];
        proposer = resolution.proposer;
        proposedOutcome = resolution.proposedOutcome;
        escalationLevel = resolution.escalationLevel;
        disputed = resolution.disputed;
        bondAmount = resolution.bondAmount;
        proposedAt = resolution.proposedAt;
        disputeDeadline = resolution.disputeDeadline;
        snapshotBlock = resolution.snapshotBlock;
    }

    function getResolutionHistoryLength(bytes32 marketId) external view returns (uint256) {
        return LibEveMarket.store().resolutionHistory[marketId].length;
    }

    function getResolutionHistoryEntry(bytes32 marketId, uint256 index)
        external
        view
        returns (
            address proposer,
            uint8 proposedOutcome,
            uint8 escalationLevel,
            bool disputed,
            uint128 bondAmount,
            uint64 proposedAt,
            uint64 disputeDeadline,
            uint64 snapshotBlock
        )
    {
        LibEveMarket.Resolution storage resolution = LibEveMarket.store().resolutionHistory[marketId][index];
        proposer = resolution.proposer;
        proposedOutcome = resolution.proposedOutcome;
        escalationLevel = resolution.escalationLevel;
        disputed = resolution.disputed;
        bondAmount = resolution.bondAmount;
        proposedAt = resolution.proposedAt;
        disputeDeadline = resolution.disputeDeadline;
        snapshotBlock = resolution.snapshotBlock;
    }

    function getBondedTotals(address account) external view returns (uint256 amount) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        amount = state.resolutionBonded[account];
    }

    function getBondedForMarket(bytes32 marketId, address account) external view returns (uint128 amount) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        amount = state.bondedByMarket[marketId][account];
    }

    function getStoredParimutuelPool(bytes32 marketId)
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

    function getStoredParimutuelFinalization(bytes32 marketId)
        external
        view
        returns (
            uint8 rawResolvedOutcome,
            uint8 effectivePayoutOutcome,
            uint128 payoutPoolAtResolution,
            uint128 totalClaimableSharesAtResolution,
            bool finalized
        )
    {
        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        rawResolvedOutcome = uint8(pool.rawResolvedOutcome);
        effectivePayoutOutcome = uint8(pool.effectivePayoutOutcome);
        payoutPoolAtResolution = pool.payoutPoolAtResolution;
        totalClaimableSharesAtResolution = pool.totalClaimableSharesAtResolution;
        finalized = pool.finalized;
    }
}

contract ResolutionHarnessFacet {
    function harnessReturnBond(bytes32 marketId, uint256 proposalIndex) external {
        IBondManagerFacet(address(this)).returnBond(marketId, proposalIndex);
    }

    function harnessSlashBond(bytes32 marketId, uint256 proposalIndex, address recipient) external {
        IBondManagerFacet(address(this)).slashBond(marketId, proposalIndex, recipient);
    }

    function harnessLockResolutionBond(address bonder, uint8 escalationLevel) external {
        IBondTokenGateFacet(address(this)).lockResolutionBond(bonder, escalationLevel);
    }

    function harnessUnlockResolutionBond(address bonder, uint128 amount) external {
        IBondTokenGateFacet(address(this)).unlockResolutionBond(bonder, amount);
    }

    function harnessFinalizeFromJury(bytes32 marketId, uint8 finalResult) external {
        IOBRResolutionFacet(address(this)).finalizeFromJury(marketId, finalResult);
    }

    function setResolutionMode(uint256 mode) external {
        if (mode > uint256(uint8(LibEveMarket.ResolutionMode.ObrJury))) {
            revert Errors.InvalidConfigValue("resolutionMode");
        }

        LibEveMarket.store().config.resolutionMode = LibEveMarket.ResolutionMode(mode);
    }

    function setCreatorFeesEscrowed(bytes32 marketId, uint128 amount) external {
        LibEveMarket.store().markets[marketId].creatorFeesEscrowed = amount;
    }

    function setMarketPositionIds(bytes32 marketId, uint256 yesPositionId, uint256 noPositionId) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.yesPositionId = yesPositionId;
        market.noPositionId = noPositionId;
    }

    function setMarketPositionToken(bytes32 marketId, address positionToken) external {
        LibEveMarket.store().markets[marketId].positionToken = positionToken;
    }

    function setMarketTypeAndPositionToken(bytes32 marketId, uint256 marketType, address positionToken) external {
        if (marketType > uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL))) {
            revert Errors.InvalidAmount(marketType);
        }

        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketType = LibEveMarket.MarketType(marketType);
        market.positionTokenType = market.marketType == LibEveMarket.MarketType.CLOB
            ? LibEveMarket.PositionTokenType.CTF
            : LibEveMarket.PositionTokenType.PARIMUTUEL;
        market.positionToken = positionToken;
    }

    function setMultiOutcomeResolutionMarket(bytes32 marketId, address positionToken, uint256 outcomeCount) external {
        if (outcomeCount == 0 || outcomeCount > type(uint8).max) {
            revert Errors.InvalidAmount(outcomeCount);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];
        market.marketType = LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK;
        market.positionTokenType = LibEveMarket.PositionTokenType.CTF;
        market.positionToken = positionToken;

        address adapterAddress = state.negRiskAdapter;
        if (adapterAddress == address(0)) revert Errors.ZeroAddress();
        IEvesNegRiskAdapter adapter = IEvesNegRiskAdapter(adapterAddress);
        bytes32 eventId = adapter.prepareEvent(marketId, outcomeCount);
        market.conditionId = eventId;

        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
        multi.marketId = marketId;
        multi.conditionId = eventId;
        multi.outcomeCount = uint8(outcomeCount);
        multi.exists = true;
        multi.adapter = adapterAddress;
        multi.wrappedCollateral = adapter.wrappedCollateral();
    }

    function setParimutuelPool(
        bytes32 marketId,
        uint256 totalYesShares,
        uint256 totalNoShares,
        uint256 payoutPool,
        uint256 claimedPayout,
        uint256 claimedClaimableShares,
        bool dustSwept
    ) external {
        if (totalYesShares > type(uint128).max) revert Errors.InvalidAmount(totalYesShares);
        if (totalNoShares > type(uint128).max) revert Errors.InvalidAmount(totalNoShares);
        if (payoutPool > type(uint128).max) revert Errors.InvalidAmount(payoutPool);
        if (claimedPayout > type(uint128).max) revert Errors.InvalidAmount(claimedPayout);
        if (claimedClaimableShares > type(uint128).max) revert Errors.InvalidAmount(claimedClaimableShares);

        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        pool.totalYesShares = uint128(totalYesShares);
        pool.totalNoShares = uint128(totalNoShares);
        pool.payoutPool = uint128(payoutPool);
        pool.claimedPayout = uint128(claimedPayout);
        pool.claimedClaimableShares = uint128(claimedClaimableShares);
        pool.dustSwept = dustSwept;
    }

    function setParimutuelConfig(address shareToken, uint256 entryFeeBps, uint256 minEntry) external {
        if (entryFeeBps > type(uint16).max || minEntry > type(uint128).max) {
            revert Errors.InvalidAmount(entryFeeBps > type(uint16).max ? entryFeeBps : minEntry);
        }

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.parimutuelShareToken = shareToken;
        config.parimutuelFeeConfig.entryFeeBps = uint16(entryFeeBps);
        config.parimutuelMinEntry = uint128(minEntry);
    }

    function setMarginAssetFixture(address marginAsset) external {
        LibEveMarket.store().marginAsset = marginAsset;
    }

    function setFeeSplitConfig(
        uint256 makerFeeBps,
        uint256 creatorFeeBps,
        uint256 protocolFeeBps,
        uint256 seniorPoolFeeBps
    ) external {
        if (makerFeeBps > type(uint16).max) revert Errors.InvalidAmount(makerFeeBps);
        if (creatorFeeBps > type(uint16).max) revert Errors.InvalidAmount(creatorFeeBps);
        if (protocolFeeBps > type(uint16).max) revert Errors.InvalidAmount(protocolFeeBps);
        if (seniorPoolFeeBps > type(uint16).max) revert Errors.InvalidAmount(seniorPoolFeeBps);

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.orderbookFeeConfig = LibEveMarket.BookFeeConfig({
            entryFeeBps: config.orderbookFeeConfig.entryFeeBps,
            makerFeeBps: uint16(makerFeeBps),
            creatorFeeBps: uint16(creatorFeeBps),
            protocolFeeBps: uint16(protocolFeeBps),
            seniorPoolFeeBps: uint16(seniorPoolFeeBps),
            resolverFeeBps: 0
        });
        config.spotFeeConfig = LibEveMarket.SpotFeeConfig({
            tradeFeeBps: config.spotFeeConfig.tradeFeeBps,
            makerFeeBps: uint16(makerFeeBps),
            protocolFeeBps: uint16(protocolFeeBps),
            seniorPoolFeeBps: uint16(seniorPoolFeeBps),
            resolverFeeBps: 0
        });
        config.parimutuelFeeConfig.creatorFeeBps = uint16(creatorFeeBps);
        config.parimutuelFeeConfig.protocolFeeBps = uint16(protocolFeeBps);
        config.parimutuelFeeConfig.seniorPoolFeeBps = uint16(seniorPoolFeeBps);
    }
}

abstract contract DiamondFixture is Test, ERC1155ReceiverHarness {
    string internal constant DEFAULT_RESOLUTION_SOURCE = "Official market rules and published primary source.";

    address internal owner;
    address internal outsider;

    EveMarketDiamond internal diamond;
    DiamondCutFacet internal cutFacet;
    DiamondLoupeFacet internal loupeFacet;
    OwnershipFacet internal ownershipFacet;
    FeeConfigFacet internal feeConfigFacet;
    RoutingProbeFacet internal routingProbe;
    RoutingProbeFacetV2 internal routingProbeV2;
    StateProbeFacet internal stateProbe;

    function setUp() public virtual {
        owner = makeAddr("owner");
        outsider = makeAddr("outsider");

        cutFacet = new DiamondCutFacet();
        loupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        feeConfigFacet = new FeeConfigFacet();
        routingProbe = new RoutingProbeFacet();
        routingProbeV2 = new RoutingProbeFacetV2();
        stateProbe = new StateProbeFacet();

        diamond = new EveMarketDiamond(owner, address(cutFacet));

        _addFacet(address(loupeFacet), _loupeSelectors());
        _addFacet(address(ownershipFacet), _ownershipSelectors());
        _addFacet(address(feeConfigFacet), _feeConfigSelectors());
        _addFacet(address(routingProbe), _routingProbeSelectors());
        _addFacet(address(stateProbe), _stateProbeSelectors());
    }

    function _addFacet(address facetAddress, bytes4[] memory selectors) internal {
        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: facetAddress, action: DiamondCutFacet.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), new bytes(0));
    }

    function _replaceFacet(address facetAddress, bytes4[] memory selectors) internal {
        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: facetAddress, action: DiamondCutFacet.FacetCutAction.Replace, functionSelectors: selectors
        });

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), new bytes(0));
    }

    function _removeSelectors(bytes4[] memory selectors) internal {
        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: address(0), action: DiamondCutFacet.FacetCutAction.Remove, functionSelectors: selectors
        });

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), new bytes(0));
    }

    function _loupeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = DiamondLoupeFacet.facets.selector;
        selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        selectors[3] = DiamondLoupeFacet.facetAddress.selector;
    }

    function _ownershipSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](37);
        selectors[0] = OwnershipFacet.transferOwnership.selector;
        selectors[1] = OwnershipFacet.owner.selector;
        selectors[2] = OwnershipFacet.setResolutionBondConfig.selector;
        selectors[3] = OwnershipFacet.setMarketCreationFee.selector;
        selectors[4] = OwnershipFacet.setMarketCreationBond.selector;
        selectors[5] = OwnershipFacet.setPermissionlessCreationEnabled.selector;
        selectors[6] = OwnershipFacet.setDefaultConditionalTokens.selector;
        selectors[7] = OwnershipFacet.setCollateralToken.selector;
        selectors[8] = OwnershipFacet.setEveToken.selector;
        selectors[9] = OwnershipFacet.setEveTreasury.selector;
        selectors[10] = OwnershipFacet.setParimutuelConfig.selector;
        selectors[11] = OwnershipFacet.setDurationParams.selector;
        selectors[12] = OwnershipFacet.setDisputeWindow.selector;
        selectors[13] = OwnershipFacet.setCreatorSettleGrace.selector;
        selectors[14] = OwnershipFacet.setOpenResolutionTimeout.selector;
        selectors[15] = OwnershipFacet.setMaxEscalation.selector;
        selectors[16] = OwnershipFacet.registerCurveProfile.selector;
        selectors[17] = OwnershipFacet.setSpotBookCreationFee.selector;
        selectors[18] = OwnershipFacet.setParimutuelEpochWindowCap.selector;
        selectors[19] = OwnershipFacet.setParimutuelEpochMultipliers.selector;
        selectors[20] = OwnershipFacet.setMarketCreationBatchCap.selector;
        selectors[21] = OwnershipFacet.setParimutuelCreationSeedAmount.selector;
        selectors[22] = OwnershipFacet.setCollateralProfile.selector;
        selectors[23] = OwnershipFacet.setCollateralProfileEnabled.selector;
        selectors[24] = OwnershipFacet.setCollateralProfilePayoutUnit.selector;
        selectors[25] = OwnershipFacet.setCollateralProfileMarketCreationFee.selector;
        selectors[26] = OwnershipFacet.setCollateralProfileParimutuelCreationSeedAmount.selector;
        selectors[27] = OwnershipFacet.setCollateralProfileParimutuelMinEntry.selector;
        selectors[28] = OwnershipFacet.setCollateralProfileParlayUnderwritingFee.selector;
        selectors[29] = OwnershipFacet.setDelayedOrderConfig.selector;
        selectors[30] = OwnershipFacet.setDelayedOrderProcessing.selector;
        selectors[31] = OwnershipFacet.setDelayedOrderGuards.selector;
        selectors[32] = OwnershipFacet.setDelayedOrderProtocolProcessor.selector;
        selectors[33] = OwnershipFacet.setMarketDelayedExecution.selector;
        selectors[34] = OwnershipFacet.setBookDelayedExecution.selector;
        selectors[35] = OwnershipFacet.setResolutionMode.selector;
        selectors[36] = OwnershipFacet.setStaticsDollarRail.selector;
    }

    function _feeConfigSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = FeeConfigFacet.setOrderbookEntryFeeBps.selector;
        selectors[1] = FeeConfigFacet.setSpotTradeFeeBps.selector;
        selectors[2] = FeeConfigFacet.setComboTradeFeeBps.selector;
        selectors[3] = FeeConfigFacet.setOrderbookFeeSplit.selector;
        selectors[4] = FeeConfigFacet.setSpotFeeSplit.selector;
        selectors[5] = FeeConfigFacet.setComboFeeSplit.selector;
        selectors[6] = FeeConfigFacet.setParimutuelFeeSplit.selector;
    }

    function _routingProbeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = RoutingProbeFacet.storeWord.selector;
        selectors[1] = RoutingProbeFacet.readWord.selector;
        selectors[2] = RoutingProbeFacet.version.selector;
    }

    function _stateProbeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](37);
        selectors[0] = StateProbeFacet.orderbookEntryFeeBps.selector;
        selectors[1] = StateProbeFacet.permissionlessCreationEnabled.selector;
        selectors[2] = StateProbeFacet.marketCreationFee.selector;
        selectors[3] = StateProbeFacet.spotBookCreationFee.selector;
        selectors[4] = StateProbeFacet.marketCreationBond.selector;
        selectors[5] = StateProbeFacet.collateralToken.selector;
        selectors[6] = StateProbeFacet.seniorPoolRevenueBps.selector;
        selectors[7] = StateProbeFacet.minMarketDuration.selector;
        selectors[8] = StateProbeFacet.maxMarketDuration.selector;
        selectors[9] = StateProbeFacet.curveProfile.selector;
        selectors[10] = StateProbeFacet.nextCurveId.selector;
        selectors[11] = StateProbeFacet.getStoredMarketCore.selector;
        selectors[12] = StateProbeFacet.getStoredMarketStatus.selector;
        selectors[13] = StateProbeFacet.getStoredCurve.selector;
        selectors[14] = StateProbeFacet.getStoredMarketFees.selector;
        selectors[15] = StateProbeFacet.getStoredCreationBond.selector;
        selectors[16] = StateProbeFacet.getStoredResolution.selector;
        selectors[17] = StateProbeFacet.getResolutionHistoryLength.selector;
        selectors[18] = StateProbeFacet.getResolutionHistoryEntry.selector;
        selectors[19] = StateProbeFacet.getBondedTotals.selector;
        selectors[20] = StateProbeFacet.getBondedForMarket.selector;
        selectors[21] = StateProbeFacet.getStoredMarketTrading.selector;
        selectors[22] = StateProbeFacet.getStoredMakerAccounting.selector;
        selectors[23] = StateProbeFacet.getStoredMarketTypeAndPositionToken.selector;
        selectors[24] = StateProbeFacet.getStoredMarketResolutionId.selector;
        selectors[25] = StateProbeFacet.getStoredParimutuelPool.selector;
        selectors[26] = StateProbeFacet.parimutuelShareToken.selector;
        selectors[27] = StateProbeFacet.parimutuelEntryFeeBps.selector;
        selectors[28] = StateProbeFacet.parimutuelMinEntry.selector;
        selectors[29] = StateProbeFacet.getStoredCreatorStatus.selector;
        selectors[30] = StateProbeFacet.getStoredParimutuelFinalization.selector;
        selectors[31] = StateProbeFacet.setBookPricingFixture.selector;
        selectors[32] = StateProbeFacet.spotTradeFeeBps.selector;
        selectors[33] = StateProbeFacet.materializeMarketSideBookFixture.selector;
        selectors[34] = StateProbeFacet.isBookMaterializedFixture.selector;
        selectors[35] = StateProbeFacet.parimutuelCreationSeedAmount.selector;
    }

    function _resolutionHarnessSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](15);
        selectors[0] = ResolutionHarnessFacet.harnessReturnBond.selector;
        selectors[1] = ResolutionHarnessFacet.harnessSlashBond.selector;
        selectors[2] = ResolutionHarnessFacet.harnessLockResolutionBond.selector;
        selectors[3] = ResolutionHarnessFacet.harnessUnlockResolutionBond.selector;
        selectors[4] = ResolutionHarnessFacet.setCreatorFeesEscrowed.selector;
        selectors[5] = ResolutionHarnessFacet.setMarketPositionIds.selector;
        selectors[6] = ResolutionHarnessFacet.setMarketPositionToken.selector;
        selectors[7] = ResolutionHarnessFacet.setMarketTypeAndPositionToken.selector;
        selectors[8] = ResolutionHarnessFacet.setParimutuelPool.selector;
        selectors[9] = ResolutionHarnessFacet.setParimutuelConfig.selector;
        selectors[10] = ResolutionHarnessFacet.setFeeSplitConfig.selector;
        selectors[11] = ResolutionHarnessFacet.harnessFinalizeFromJury.selector;
        selectors[12] = ResolutionHarnessFacet.setResolutionMode.selector;
        selectors[13] = ResolutionHarnessFacet.setMultiOutcomeResolutionMarket.selector;
        selectors[14] = ResolutionHarnessFacet.setMarginAssetFixture.selector;
    }

    function _parimutuelSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = bytes4(
            keccak256(
                "createParimutuelMarket((string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[1] = bytes4(
            keccak256(
                "createParimutuelMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[2] = IParimutuelFacet.buyShares.selector;
        selectors[3] = IParimutuelFacet.buySharesBatch.selector;
        selectors[4] = IParimutuelFacet.claimPayout.selector;
        selectors[5] = IParimutuelFacet.sweepParimutuelDust.selector;
        selectors[6] = bytes4(keccak256("createParimutuelMarket(string,string,string,uint64,uint64,uint64)"));
        selectors[7] = bytes4(
            keccak256("createParimutuelMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint64)")
        );
    }

    function _parimutuelViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = IParimutuelFacet.previewPayout.selector;
        selectors[1] = IParimutuelFacet.previewEntryFee.selector;
        selectors[2] = IParimutuelFacet.getParimutuelPool.selector;
        selectors[3] = IParimutuelFacet.getParimutuelBalances.selector;
        selectors[4] = IParimutuelFacet.isParimutuelMarket.selector;
        selectors[5] = IParimutuelFacet.getParimutuelEpochWindow.selector;
        selectors[6] = IParimutuelFacet.getEpochMultiplier.selector;
        selectors[7] = IParimutuelFacet.getParimutuelEpochMultipliers.selector;
        selectors[8] = IParimutuelFacet.previewParimutuelEntry.selector;
    }
}

abstract contract MarketFactoryFixture is DiamondFixture {
    struct ExpectedMarketData {
        bytes32 marketId;
        bytes32 questionId;
        bytes32 resolutionId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    address internal creator;
    address internal trader;
    address internal treasury;

    MockConditionalTokens internal conditionalTokens;
    MockUSDC internal collateralToken;
    MockEveToken internal eveToken;
    MarketFactoryFacet internal marketFactoryFacet;
    MarketGroupFacet internal marketGroupFacet;
    MarketViewFacet internal marketViewFacet;

    function setUp() public virtual override {
        super.setUp();

        creator = makeAddr("creator");
        trader = makeAddr("trader");
        treasury = makeAddr("treasury");

        conditionalTokens = new MockConditionalTokens();
        collateralToken = new MockUSDC();
        eveToken = new MockEveToken();
        marketFactoryFacet = new MarketFactoryFacet();
        marketGroupFacet = new MarketGroupFacet();
        marketViewFacet = new MarketViewFacet();

        _addFacet(address(marketFactoryFacet), _marketFactorySelectors());
        _addFacet(address(marketGroupFacet), _marketGroupSelectors());
        _addFacet(address(marketViewFacet), _marketViewSelectors());

        collateralToken.mint(creator, 10_000_000e6);
        collateralToken.mint(trader, 10_000_000e6);
        eveToken.mint(creator, 20_000e18);
        eveToken.mint(trader, 20_000e18);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(conditionalTokens));
        OwnershipFacet(address(diamond)).setCollateralToken(address(collateralToken));
        OwnershipFacet(address(diamond)).setEveToken(address(eveToken));
        OwnershipFacet(address(diamond)).setResolutionBondConfig(address(eveToken), 0.1 ether, 0.5 ether);
        OwnershipFacet(address(diamond)).setEveTreasury(treasury);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(true);
        OwnershipFacet(address(diamond)).setMarketCreationFee(50e6);
        OwnershipFacet(address(diamond)).setMarketCreationBond(100e18);
        OwnershipFacet(address(diamond)).setMarketCreationBatchCap(24);
        OwnershipFacet(address(diamond)).setDurationParams(1 hours, 90 days);
        vm.stopPrank();
    }

    function _marketFactorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = bytes4(
            keccak256(
                "createMarket((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[1] = IMarketFactoryFacet.createMarkets.selector;
        selectors[2] = MarketFactoryFacet.syncMarketState.selector;
        selectors[3] = bytes4(
            keccak256(
                "createMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[4] = bytes4(keccak256("createMarket(string,string,string,uint64,uint64,uint128,bool)"));
        selectors[5] = bytes4(
            keccak256("createMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint128,bool)")
        );
    }

    function _marketGroupSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = bytes4(
            keccak256(
                "createMarketGroup(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)),(string,string,int32,uint8))[]))"
            )
        );
        selectors[1] = bytes4(
            keccak256(
                "createMarketGroup(string,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32))[])"
            )
        );
        selectors[2] = bytes4(
            keccak256(
                "createMarketGroupFromExisting(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),(bytes32,(string,string,int32,uint8))[]))"
            )
        );
        selectors[3] = bytes4(keccak256("addMarketsToGroup(bytes32,(bytes32,(string,string,int32,uint8))[])"));
    }

    function _marketViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](19);
        selectors[0] = IMarketFactoryFacet.getMarketPositions.selector;
        selectors[1] = IMarketFactoryFacet.getMarketInfo.selector;
        selectors[2] = IMarketFactoryFacet.getMarketSummaries.selector;
        selectors[3] = IMarketFactoryFacet.getMarketConfig.selector;
        selectors[4] = IMarketFactoryFacet.getUserMarketPositions.selector;
        selectors[5] = IMarketFactoryFacet.getMarketMetadata.selector;
        selectors[6] = IMarketFactoryFacet.getPositionMetadata.selector;
        selectors[7] = IMarketFactoryFacet.positionTokenURI.selector;
        selectors[8] = IMarketFactoryFacet.computeMarketId.selector;
        selectors[9] = IMarketFactoryFacet.getMarketTokenInfo.selector;
        selectors[10] = IMarketFactoryFacet.getCollateralProfile.selector;
        selectors[11] = IMarketFactoryFacet.getCollateralProfileParimutuelConfig.selector;
        selectors[12] = IMarketFactoryFacet.getCollateralProfileParlayUnderwritingFee.selector;
        selectors[13] = IMarketFactoryFacet.computeProfileMarketId.selector;
        selectors[14] = IMarketFactoryFacet.getMarketDisplay.selector;
        selectors[15] = IMarketFactoryFacet.getMarketExternalRef.selector;
        selectors[16] = IMarketFactoryFacet.getMarketGroup.selector;
        selectors[17] = IMarketFactoryFacet.getMarketGroupMarkets.selector;
        selectors[18] = IMarketFactoryFacet.getGroupMarketDisplay.selector;
    }

    function _approveCreator(uint256 amount) internal {
        _approveCreatorWithEve(amount, type(uint256).max);
    }

    function _approveCreatorWithEve(uint256 collateralAmount, uint256 bondAmount) internal {
        vm.prank(creator);
        collateralToken.approve(address(diamond), collateralAmount);

        vm.prank(creator);
        eveToken.approve(address(diamond), bondAmount);
    }

    function _marketIdFor(string memory question, string memory category, uint64 expiryTime)
        internal
        view
        returns (bytes32 marketId)
    {
        marketId = _marketIdFor(question, category, uint64(block.timestamp), expiryTime);
    }

    function _marketIdFor(string memory question, string memory category, uint64 tradingStartTime, uint64 expiryTime)
        internal
        view
        returns (bytes32 marketId)
    {
        marketId = LibMarketCreation.marketIdFor(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
    }

    function _questionIdFor(string memory question, string memory category, uint64 expiryTime)
        internal
        view
        returns (bytes32 questionId)
    {
        questionId = _questionIdFor(question, category, uint64(block.timestamp), expiryTime);
    }

    function _questionIdFor(string memory question, string memory category, uint64 tradingStartTime, uint64 expiryTime)
        internal
        pure
        returns (bytes32 questionId)
    {
        questionId = LibMarketCreation.questionIdFor(question, category, tradingStartTime, expiryTime);
    }

    function _expectedMarketData(string memory question, string memory category, uint64 expiryTime)
        internal
        view
        returns (ExpectedMarketData memory expected)
    {
        expected.marketId = _marketIdFor(question, category, uint64(block.timestamp), expiryTime);
        expected.questionId = _questionIdFor(question, category, uint64(block.timestamp), expiryTime);
        expected.resolutionId = LibMarketCreation.resolutionIdFor(expected.marketId);
        expected.conditionId = conditionalTokens.getConditionId(address(diamond), expected.resolutionId, 2);
        (expected.yesPositionId, expected.noPositionId) = _positionIdsFor(expected.conditionId);
    }

    function _positionIdsFor(bytes32 conditionId) internal view returns (uint256 yesPositionId, uint256 noPositionId) {
        return _positionIdsFor(address(collateralToken), conditionId);
    }

    function _positionIdsFor(address targetCollateralToken, bytes32 conditionId)
        internal
        view
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        bytes32 yesCollectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, 1);
        bytes32 noCollectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, 2);

        yesPositionId = conditionalTokens.getPositionId(IERC20(targetCollateralToken), yesCollectionId);
        noPositionId = conditionalTokens.getPositionId(IERC20(targetCollateralToken), noCollectionId);
    }
}

abstract contract CurveTradingFixture is MarketFactoryFixture {
    address internal maker;
    address internal taker;

    CurveCLOBFacet internal curveCLOBFacet;
    MockCurveProfile internal curveProfile;
    ResolutionHarnessFacet internal curveHarness;

    function setUp() public virtual override {
        super.setUp();

        maker = makeAddr("maker");
        taker = makeAddr("taker");

        curveProfile = new MockCurveProfile();
        curveHarness = new ResolutionHarnessFacet();

        _addCurveFacets();
        _addFacet(address(curveHarness), _resolutionHarnessSelectors());

        collateralToken.mint(maker, 10_000_000e6);
        collateralToken.mint(taker, 10_000_000e6);

        vm.startPrank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(8_500, 500, 1_000, 0, 0);
        OwnershipFacet(address(diamond)).registerCurveProfile(3, address(curveProfile));
        vm.stopPrank();
    }

    function _addCurveFacets() internal {
        _addFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        _addFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        curveCLOBFacet = new CurveCLOBFacet();
        _addFacet(address(curveCLOBFacet), _curveTradeSelectors());
        _addFacet(address(new CurveViewFacet()), _curveViewSelectors());
        _addFacet(address(new BookFacet()), _bookSelectors());
        _addFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        _addFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        _addFacet(address(new BookSellFacet()), _bookSellSelectors());
        _addFacet(address(new BookViewFacet()), _bookViewSelectors());
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
        selectors[1] = ICurveInventoryFacet.mergeInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](16);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.postCurvesBatch.selector;
        selectors[2] = ICurveLifecycleFacet.postBidCurve.selector;
        selectors[3] = ICurveLifecycleFacet.postBidCurvesBatch.selector;
        selectors[4] = ICurveLifecycleFacet.postCurvesMultiMarket.selector;
        selectors[5] = ICurveLifecycleFacet.postBidCurvesMultiMarket.selector;
        selectors[6] = ICurveLifecycleFacet.updateCurve.selector;
        selectors[7] = ICurveLifecycleFacet.updateCurvesBatch.selector;
        selectors[8] = ICurveLifecycleFacet.updateCurveFromNow.selector;
        selectors[9] = ICurveLifecycleFacet.updateCurvesFromNowBatch.selector;
        selectors[10] = ICurveLifecycleFacet.topUpCurvesBatch.selector;
        selectors[11] = ICurveLifecycleFacet.splitAndTopUpCurvesBatch.selector;
        selectors[12] = ICurveLifecycleFacet.topUpCurvesMultiMarket.selector;
        selectors[13] = ICurveLifecycleFacet.splitAndTopUpCurvesMultiMarket.selector;
        selectors[14] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[15] = ICurveLifecycleFacet.cancelCurvesBatch.selector;
    }

    function _curveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveViewFacet.getCurveInfo.selector;
        selectors[1] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[2] = ICurveViewFacet.previewCurveQuote.selector;
        selectors[3] = ICurveViewFacet.previewBestExecution.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.computeBookId.selector;
        selectors[2] = IBookAdminFacet.getBookInfo.selector;
        selectors[3] = IBookAdminFacet.isBookMaterialized.selector;
        selectors[4] = IBookAdminFacet.getMarketSideBook.selector;
        selectors[5] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[6] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[3] = IBookOrderFacet.reactivateBookCurve.selector;
        selectors[4] = IBookOrderFacet.pruneBookCurves.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
    }

    function _bookSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function _bookViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookCurveIdsPage.selector;
        selectors[2] = IBookViewFacet.getActiveBookCurveIdsPage.selector;
        selectors[3] = IBookViewFacet.getBookTopOfBookPage.selector;
    }

    function _createTradingMarket(string memory question, string memory category, uint64 duration)
        internal
        returns (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp) + duration;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        expected = _expectedMarketData(question, category, expiryTime);
    }

    function _splitFrom(address account, bytes32 marketId, uint128 collateralAmount)
        internal
        returns (uint128 sharesMinted)
    {
        vm.startPrank(account);
        collateralToken.approve(address(diamond), collateralAmount);
        sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, collateralAmount);
        vm.stopPrank();
    }

    function _approvePositions(address account) internal {
        vm.prank(account);
        conditionalTokens.setApprovalForAll(address(diamond), true);
    }

    function _postCurveFromMaker(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId
    ) internal returns (uint256 curveId) {
        vm.prank(maker);
        curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId,
                isYesSide,
                volume,
                startPrice,
                endPrice,
                durationMinutes,
                profileId,
                LibEveMarket.PositionTokenType.CTF
            );
    }
}

abstract contract ResolutionFixture is MarketFactoryFixture {
    address internal challengerOne;
    address internal challengerTwo;
    address internal challengerThree;
    address internal voterOne;
    address internal voterTwo;

    BondManagerFacet internal bondManagerFacet;
    BondTokenGateFacet internal bondTokenGateFacet;
    OBRResolutionFacet internal obrResolutionFacet;
    ResolverJuryFacet internal resolverJuryFacet;
    ResolutionHarnessFacet internal resolutionHarness;
    EvesNegRiskAdapter internal negRiskAdapter;

    function setUp() public virtual override {
        super.setUp();

        challengerOne = makeAddr("challengerOne");
        challengerTwo = makeAddr("challengerTwo");
        challengerThree = makeAddr("challengerThree");
        voterOne = makeAddr("voterOne");
        voterTwo = makeAddr("voterTwo");

        eveToken = new MockEveToken();
        bondManagerFacet = new BondManagerFacet();
        bondTokenGateFacet = new BondTokenGateFacet();
        obrResolutionFacet = new OBRResolutionFacet();
        resolverJuryFacet = new ResolverJuryFacet();
        resolutionHarness = new ResolutionHarnessFacet();
        negRiskAdapter = new EvesNegRiskAdapter(address(conditionalTokens), address(collateralToken), address(diamond));

        _addFacet(address(bondManagerFacet), _bondManagerSelectors());
        _addFacet(address(bondTokenGateFacet), _bondTokenGateSelectors());
        _addFacet(address(obrResolutionFacet), _obrResolutionSelectors());
        _addFacet(address(resolverJuryFacet), _resolverJurySelectors());
        _addFacet(address(resolutionHarness), _resolutionHarnessSelectors());
        _addFacet(address(new NegRiskConfigFacet()), _negRiskConfigSelectors());
        _addFacet(address(new SeniorCapitalFacet()), _seniorCapitalSelectors());
        _addFacet(address(new SeniorCapitalViewFacet()), _seniorCapitalViewSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setEveToken(address(eveToken));
        OwnershipFacet(address(diamond)).setResolutionBondConfig(address(eveToken), 0.1 ether, 0.5 ether);
        OwnershipFacet(address(diamond)).setDisputeWindow(2 hours);
        OwnershipFacet(address(diamond)).setCreatorSettleGrace(24 hours);
        OwnershipFacet(address(diamond)).setOpenResolutionTimeout(24 hours);
        OwnershipFacet(address(diamond)).setMaxEscalation(2);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        INegRiskConfigFacet(address(diamond)).setNegRiskAdapter(address(negRiskAdapter));
        vm.stopPrank();
        ResolutionHarnessFacet(address(diamond)).setResolutionMode(uint8(LibEveMarket.ResolutionMode.ObrJury));
        ResolutionHarnessFacet(address(diamond)).setMarginAssetFixture(address(collateralToken));

        _mintAndApproveEve(creator, 20_000e18);
        _mintAndApproveEve(challengerOne, 20_000e18);
        _mintAndApproveEve(challengerTwo, 20_000e18);
        _mintAndApproveEve(challengerThree, 20_000e18);
        _mintAndApproveEve(treasury, 20_000e18);

        vm.deal(challengerOne, 10 ether);
        vm.deal(challengerTwo, 10 ether);
        vm.deal(challengerThree, 10 ether);
        vm.deal(treasury, 10 ether);
    }

    function _bondManagerSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IBondManagerFacet.slashBond.selector;
        selectors[1] = IBondManagerFacet.returnBond.selector;
        selectors[2] = IBondManagerFacet.routeBond.selector;
    }

    function _negRiskConfigSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = INegRiskConfigFacet.setNegRiskAdapter.selector;
        selectors[1] = INegRiskConfigFacet.negRiskAdapter.selector;
    }

    function _seniorCapitalSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = ISeniorCapitalFacet.depositSeniorCapital.selector;
        selectors[1] = ISeniorCapitalFacet.withdrawPendingSeniorCapital.selector;
        selectors[2] = ISeniorCapitalFacet.activateSeniorCapital.selector;
        selectors[3] = ISeniorCapitalFacet.requestSeniorCapitalExit.selector;
        selectors[4] = ISeniorCapitalFacet.cancelSeniorCapitalExit.selector;
        selectors[5] = ISeniorCapitalFacet.processSeniorCapitalExits.selector;
        selectors[6] = ISeniorCapitalFacet.claimSeniorCapitalFees.selector;
        selectors[7] = ISeniorCapitalFacet.donateSeniorCapitalFees.selector;
        selectors[8] = ISeniorCapitalFacet.claimSeniorCapitalExit.selector;
    }

    function _seniorCapitalViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = ISeniorCapitalFacet.seniorCapitalState.selector;
        selectors[1] = ISeniorCapitalFacet.seniorCapitalAccount.selector;
        selectors[2] = ISeniorCapitalFacet.seniorCapitalExit.selector;
        selectors[3] = ISeniorCapitalFacet.seniorCapitalBucket.selector;
        selectors[4] = ISeniorCapitalFacet.pendingSeniorCapitalFees.selector;
        selectors[5] = ISeniorCapitalFacet.claimableSeniorCapitalExit.selector;
    }

    function _bondTokenGateSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBondTokenGateFacet.lockResolutionBond.selector;
        selectors[1] = IBondTokenGateFacet.unlockResolutionBond.selector;
    }

    function _obrResolutionSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IOBRResolutionFacet.settleMarket.selector;
        selectors[1] = IOBRResolutionFacet.openResolution.selector;
        selectors[2] = IOBRResolutionFacet.disputeResolution.selector;
        selectors[3] = IOBRResolutionFacet.adminFinalizeResolution.selector;
        selectors[4] = IOBRResolutionFacet.getResolutionHistory.selector;
        selectors[5] = IOBRResolutionFacet.finalizeResolution.selector;
        selectors[6] = IOBRResolutionFacet.getMarketStatus.selector;
        selectors[7] = IOBRResolutionFacet.settleMarketEarly.selector;
        selectors[8] = IOBRResolutionFacet.finalizeFromJury.selector;
        selectors[9] = IOBRResolutionFacet.resolutionMode.selector;
    }

    function _resolverJurySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](20);
        selectors[0] = IResolverJuryFacet.initiateDispute.selector;
        selectors[1] = IResolverJuryFacet.openRandomnessCommit.selector;
        selectors[2] = IResolverJuryFacet.commitRandomness.selector;
        selectors[3] = IResolverJuryFacet.closeRandomnessCommit.selector;
        selectors[4] = IResolverJuryFacet.revealRandomness.selector;
        selectors[5] = IResolverJuryFacet.closeRandomnessReveal.selector;
        selectors[6] = IResolverJuryFacet.selectCommittee.selector;
        selectors[7] = IResolverJuryFacet.closeCommit.selector;
        selectors[8] = IResolverJuryFacet.closeRevealAndTally.selector;
        selectors[9] = IResolverJuryFacet.openAppeal.selector;
        selectors[10] = IResolverJuryFacet.finalizeDispute.selector;
        selectors[11] = IResolverJuryFacet.applyRandomnessFallback.selector;
        selectors[12] = IResolverJuryFacet.commitVote.selector;
        selectors[13] = IResolverJuryFacet.revealVote.selector;
        selectors[14] = IResolverJuryFacet.disputeView.selector;
        selectors[15] = IResolverJuryFacet.committeeMembers.selector;
        selectors[16] = IResolverJuryFacet.outcomeTally.selector;
        selectors[17] = IResolverJuryFacet.revealedVote.selector;
        selectors[18] = IResolverJuryFacet.provisionalResult.selector;
        selectors[19] = ResolverJuryFacet.disputeIdForMarket.selector;
    }

    function _createPendingMarket(string memory question, string memory category, uint64 duration)
        internal
        returns (bytes32 marketId, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp) + duration;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
    }

    function _seedCreatorFees(bytes32 marketId, uint128 amount) internal {
        collateralToken.mint(address(diamond), amount);
        ResolutionHarnessFacet(address(diamond)).setCreatorFeesEscrowed(marketId, amount);
    }

    function _mintAndApproveEve(address account, uint256 amount) internal {
        eveToken.mint(account, amount);
        vm.prank(account);
        eveToken.approve(address(diamond), type(uint256).max);
    }
}

abstract contract SettlementFeeFixture is ResolutionFixture {
    address internal maker;
    address internal taker;

    CurveCLOBFacet internal curveCLOBFacet;
    FeeRouterFacet internal feeRouterFacet;
    MarketSettlementFacet internal marketSettlementFacet;
    MockCurveProfile internal curveProfile;

    function setUp() public virtual override {
        super.setUp();

        maker = makeAddr("maker");
        taker = makeAddr("taker");

        feeRouterFacet = new FeeRouterFacet();
        marketSettlementFacet = new MarketSettlementFacet();
        curveProfile = new MockCurveProfile();

        _addSettlementCurveFacets();
        _addFacet(address(feeRouterFacet), _feeRouterSelectors());
        _addFacet(address(marketSettlementFacet), _marketSettlementSelectors());
        _addFacet(address(new CollateralTradeRouterFacet()), _tradeRouterSelectors());
        _addFacet(address(new CollateralTradeRouterExactFacet()), _tradeRouterExactSelectors());
        _addFacet(address(new CollateralTradeRouterSellFacet()), _tradeRouterSellSelectors());
        _addFacet(address(new CollateralTradeRouterPreviewFacet()), _tradeRouterPreviewSelectors());

        collateralToken.mint(maker, 10_000_000e6);
        collateralToken.mint(taker, 10_000_000e6);

        vm.startPrank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(8_500, 500, 1_000, 0, 0);
        OwnershipFacet(address(diamond)).registerCurveProfile(3, address(curveProfile));
        vm.stopPrank();
    }

    function _addSettlementCurveFacets() internal {
        _addFacet(address(new CurveInventoryFacet()), _settlementCurveInventorySelectors());
        _addFacet(address(new CurveLifecycleFacet()), _settlementCurveLifecycleSelectors());
        curveCLOBFacet = new CurveCLOBFacet();
        _addFacet(address(curveCLOBFacet), _settlementCurveTradeSelectors());
        _addFacet(address(new CurveViewFacet()), _settlementCurveViewSelectors());
    }

    function _settlementCurveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
        selectors[1] = ICurveInventoryFacet.mergeInventory.selector;
    }

    function _settlementCurveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.postCurvesBatch.selector;
        selectors[2] = ICurveLifecycleFacet.postBidCurve.selector;
        selectors[3] = ICurveLifecycleFacet.postBidCurvesBatch.selector;
        selectors[4] = ICurveLifecycleFacet.postCurvesMultiMarket.selector;
        selectors[5] = ICurveLifecycleFacet.postBidCurvesMultiMarket.selector;
        selectors[6] = ICurveLifecycleFacet.updateCurve.selector;
        selectors[7] = ICurveLifecycleFacet.updateCurvesBatch.selector;
        selectors[8] = ICurveLifecycleFacet.updateCurveFromNow.selector;
        selectors[9] = ICurveLifecycleFacet.updateCurvesFromNowBatch.selector;
        selectors[10] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[11] = ICurveLifecycleFacet.cancelCurvesBatch.selector;
    }

    function _settlementCurveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function _settlementCurveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveViewFacet.getCurveInfo.selector;
        selectors[1] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[2] = ICurveViewFacet.previewCurveQuote.selector;
        selectors[3] = ICurveViewFacet.previewBestExecution.selector;
    }

    function _feeRouterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
        selectors[0] = IFeeRouterFacet.claimCreatorFees.selector;
        selectors[1] = IFeeRouterFacet.claimMakerFees.selector;
        selectors[2] = IFeeRouterFacet.previewMakerFees.selector;
        selectors[3] = IFeeRouterFacet.getMakerMarketAccounting.selector;
        selectors[4] = IFeeRouterFacet.configureMarketMakerRewards.selector;
        selectors[5] = IFeeRouterFacet.fundMarketMakerRewards.selector;
        selectors[6] = IFeeRouterFacet.claimMarketMakerRewards.selector;
        selectors[7] = IFeeRouterFacet.previewMarketMakerRewards.selector;
        selectors[8] = IFeeRouterFacet.claimBookCreatorFees.selector;
        selectors[9] = IFeeRouterFacet.claimBookMakerFees.selector;
        selectors[10] = IFeeRouterFacet.previewBookMakerFees.selector;
        selectors[11] = IFeeRouterFacet.getMakerBookAccounting.selector;
    }

    function _marketSettlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMarketSettlementFacet.getCTFRedemptionParams.selector;
        selectors[1] = IMarketSettlementFacet.previewCTFRedemption.selector;
        selectors[2] = IMarketSettlementFacet.previewParimutuelPayout.selector;
        selectors[3] = IMarketSettlementFacet.previewRedemption.selector;
    }

    function _tradeRouterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.buyWithCollateral.selector;
    }

    function _tradeRouterExactSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.buyWithCollateralExact.selector;
    }

    function _tradeRouterSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.sellWithCollateral.selector;
    }

    function _tradeRouterPreviewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.previewSellBest.selector;
        selectors[1] = ITradeRouter.executeExactRouterTransfer.selector;
    }

    function _createTradingMarket(string memory question, string memory category, uint64 duration)
        internal
        returns (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp) + duration;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        expected = _expectedMarketData(question, category, expiryTime);
    }

    function _splitFrom(address account, bytes32 marketId, uint128 collateralAmount)
        internal
        returns (uint128 sharesMinted)
    {
        vm.startPrank(account);
        collateralToken.approve(address(diamond), collateralAmount);
        sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, collateralAmount);
        vm.stopPrank();
    }

    function _approvePositions(address account) internal {
        vm.prank(account);
        conditionalTokens.setApprovalForAll(address(diamond), true);
    }

    function _postCurveFromMaker(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId
    ) internal returns (uint256 curveId) {
        vm.prank(maker);
        curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId,
                isYesSide,
                volume,
                startPrice,
                endPrice,
                durationMinutes,
                profileId,
                LibEveMarket.PositionTokenType.CTF
            );
    }

    function _fillCurveFromTaker(uint256 curveId, uint128 collateralIn)
        internal
        returns (uint128 sharesOut, uint128 fee, uint128 price)
    {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares, uint128 previewFee, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, collateralIn);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), collateralIn);
        sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, 0, generation, commitment);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);
        fee = previewFee;
        price = previewPrice;
    }

    function _createFilledMarket(
        string memory question,
        string memory category,
        uint64 duration,
        uint128 makerInventory,
        uint72 price,
        uint16 feeRate,
        uint128 takerCollateral
    )
        internal
        returns (
            bytes32 marketId,
            ExpectedMarketData memory expected,
            uint64 expiryTime,
            uint256 curveId,
            uint128 sharesOut,
            uint128 fee
        )
    {
        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(feeRate);

        (marketId, expected, expiryTime) = _createTradingMarket(question, category, duration);
        _splitFrom(maker, marketId, makerInventory);
        _approvePositions(maker);

        curveId = _postCurveFromMaker(marketId, true, makerInventory, price, price, 180, 0);
        (sharesOut, fee,) = _fillCurveFromTaker(curveId, takerCollateral);
    }

    function _createFilledMarketWithFee(
        string memory question,
        string memory category,
        uint64 duration,
        uint128 makerInventory,
        uint72 price,
        uint16 feeRate,
        uint128 takerCollateral
    ) internal returns (bytes32 marketId, uint64 expiryTime, uint128 fee) {
        ExpectedMarketData memory expected;
        uint256 curveId;
        uint128 sharesOut;

        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(feeRate);

        (marketId, expected, expiryTime) = _createTradingMarket(question, category, duration);
        _splitFrom(maker, marketId, makerInventory);
        _approvePositions(maker);

        curveId = _postCurveFromMaker(marketId, true, makerInventory, price, price, 180, 0);
        (sharesOut, fee,) = _fillCurveFromTaker(curveId, takerCollateral);

        expected;
        curveId;
        sharesOut;
    }

    function _expireMarket(bytes32 marketId, uint64 expiryTime) internal {
        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
    }

    function _finalizeCreatorResolution(bytes32 marketId, uint64 expiryTime, uint8 outcome) internal {
        _expireMarket(marketId, expiryTime);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, outcome);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }

    function _finalizeChallengedResolution(
        bytes32 marketId,
        uint64 expiryTime,
        uint8 creatorOutcome,
        uint8 challengerOutcome
    ) internal {
        _expireMarket(marketId, expiryTime);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, creatorOutcome);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, challengerOutcome);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }

    function _finalizeMissingResolution(bytes32 marketId, uint64 expiryTime) internal {
        vm.warp(expiryTime + 48 hours);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }
}

abstract contract CollateralRouterFixture is DiamondFixture {
    uint16 internal constant DEFAULT_FILL_FEE_RATE = 0;
    uint72 internal constant DEFAULT_FLAT_PRICE = 500_000_000;

    struct ExpectedMarketData {
        bytes32 marketId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    address internal creator;
    address internal maker;
    address internal taker;
    address internal treasury;

    MockConditionalTokens internal conditionalTokens;
    MockEveToken internal eveToken;
    MockCollateral internal routerCollateral;
    MockCurveProfile internal curveProfile;

    function setUp() public virtual override {
        super.setUp();

        creator = makeAddr("creator");
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        treasury = makeAddr("treasury");

        conditionalTokens = new MockConditionalTokens();
        eveToken = new MockEveToken();
        routerCollateral = new MockCollateral();
        curveProfile = new MockCurveProfile();

        _addFacet(address(new MarketFactoryFacet()), _marketFactorySelectors());
        _addFacet(address(new MarketViewFacet()), _marketViewSelectors());
        _addFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        _addFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        _addFacet(address(new CurveCLOBFacet()), _curveTradeSelectors());
        _addFacet(address(new CurveViewFacet()), _curveViewSelectors());

        _fundRouterCollateral(creator, 100_000e18);
        _fundRouterCollateral(maker, 100_000e18);
        _fundRouterCollateral(taker, 100_000e18);
        eveToken.mint(creator, 20_000e18);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(conditionalTokens));
        OwnershipFacet(address(diamond)).setCollateralToken(address(routerCollateral));
        OwnershipFacet(address(diamond)).setEveToken(address(eveToken));
        OwnershipFacet(address(diamond)).setResolutionBondConfig(address(eveToken), 0, 0);
        OwnershipFacet(address(diamond)).setEveTreasury(treasury);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(true);
        OwnershipFacet(address(diamond)).setMarketCreationFee(0);
        OwnershipFacet(address(diamond)).setMarketCreationBond(0);
        OwnershipFacet(address(diamond)).setDurationParams(1 hours, 90 days);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(8_500, 500, 1_000, 0, 0);
        OwnershipFacet(address(diamond)).registerCurveProfile(3, address(curveProfile));
        vm.stopPrank();
    }

    function _fundRouterCollateral(address account, uint256 amount) internal {
        routerCollateral.mint(account, amount);
        vm.prank(account);
        routerCollateral.approve(address(diamond), type(uint256).max);
    }

    function _createTradingMarket(string memory question, uint64 duration)
        internal
        returns (bytes32 marketId, ExpectedMarketData memory expected)
    {
        uint64 expiryTime = uint64(block.timestamp) + duration;
        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, "router", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        (bytes32 conditionId,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        expected = ExpectedMarketData({
            marketId: marketId, conditionId: conditionId, yesPositionId: yesPositionId, noPositionId: noPositionId
        });
    }

    function _splitFromMaker(bytes32 marketId, uint128 collateralAmount) internal returns (uint128 sharesMinted) {
        vm.startPrank(maker);
        routerCollateral.approve(address(diamond), collateralAmount);
        sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, collateralAmount);
        vm.stopPrank();
    }

    function _postCurveFromMaker(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes
    ) internal returns (uint256 curveId) {
        vm.prank(maker);
        curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId,
                isYesSide,
                volume,
                startPrice,
                endPrice,
                durationMinutes,
                0,
                LibEveMarket.PositionTokenType.CTF
            );
    }

    function _approvePositions(address account) internal {
        vm.prank(account);
        conditionalTokens.setApprovalForAll(address(diamond), true);
    }

    function _marketFactorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("createMarket(string,string,string,uint64,uint64,uint128,bool)"));
        selectors[1] = MarketFactoryFacet.syncMarketState.selector;
    }

    function _marketViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IMarketFactoryFacet.getMarketPositions.selector;
        selectors[1] = IMarketFactoryFacet.getMarketInfo.selector;
        selectors[2] = IMarketFactoryFacet.getMarketConfig.selector;
        selectors[3] = IMarketFactoryFacet.computeMarketId.selector;
        selectors[4] = IMarketFactoryFacet.getMarketMetadata.selector;
        selectors[5] = IMarketFactoryFacet.getPositionMetadata.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
        selectors[1] = ICurveInventoryFacet.mergeInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.postBidCurve.selector;
        selectors[2] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[3] = ICurveLifecycleFacet.updateCurve.selector;
    }

    function _curveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveViewFacet.getCurveInfo.selector;
        selectors[1] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[2] = ICurveViewFacet.previewCurveQuote.selector;
        selectors[3] = ICurveViewFacet.previewBestExecution.selector;
    }
}
