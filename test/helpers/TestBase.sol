// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IParimutuelShareToken} from "../../src/interfaces/IParimutuelShareToken.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibCTF} from "../../src/libraries/LibCTF.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibDiamond} from "../../src/libraries/LibDiamond.sol";
import {LibDelayedOrder} from "../../src/libraries/LibDelayedOrder.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {LibParimutuel} from "../../src/libraries/LibParimutuel.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {ERC1155ReceiverHarness} from "./ERC1155ReceiverHarness.sol";
import {MockConditionalTokens} from "./MockConditionalTokens.sol";
import {MockCurveProfile} from "./MockCurveProfile.sol";
import {MockEveToken} from "./MockEveToken.sol";
import {MockUSDC} from "./MockUSDC.sol";

interface ITestStateFacet {
    function configure(address conditionalTokens, address collateralToken, address eveToken, address eveTreasury)
        external;

    function configureParimutuelFixture(address shareToken, uint256 entryFeeBps, uint256 minEntry) external;

    function setSpotBookCreationFeeFixture(uint256 fee) external;

    function setSpotFeeConfigFixture(
        uint256 tradeFeeBps,
        uint256 makerFeeBps,
        uint256 protocolFeeBps,
        uint256 vaultFeeBps
    ) external;

    function setOrderbookFeeConfigFixture(
        uint256 entryFeeBps,
        uint256 makerFeeBps,
        uint256 creatorFeeBps,
        uint256 protocolFeeBps,
        uint256 vaultFeeBps
    ) external;

    function setDelayedOrderConfigFixture(
        uint256 protectionDelayBlocks,
        uint256 executionGraceBlocks,
        uint256 restingDurationMinutes
    ) external;

    function setDelayedOrderProcessingFixture(uint256 processingMode, uint256 processorFeeShareBps) external;

    function setDelayedOrderProtocolProcessorFixture(address processor, bool allowed) external;

    function setMarketDelayedExecutionFixture(bytes32 marketId, bool enabled) external;

    function setBookDelayedExecutionFixture(bytes32 bookId, bool enabled) external;

    function getMarketDelayedExecutionFixture(bytes32 marketId) external view returns (bool enabled);

    function getBookDelayedExecutionFixture(bytes32 bookId) external view returns (bool enabled);

    function spotBookCreationFeeFixture() external view returns (uint128 fee);

    function setBookPricingFixture(
        bytes32 bookId,
        uint256 pricingMode,
        uint256 tickSize,
        uint256 priceDenominator,
        uint256 minTick,
        uint256 maxTick
    ) external;

    function materializeMarketSideBookFixture(bytes32 marketId, bool isYesSide) external;

    function registerCurveProfileFixture(uint8 profileId, address profileContract) external;

    function createMarketFixture(bytes32 marketId, string calldata question, address creator, uint64 expiryTime)
        external
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId);

    function createParimutuelMarketFixture(
        bytes32 marketId,
        string calldata question,
        string calldata category,
        address creator,
        uint64 expiryTime
    ) external returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId);

    function buySharesFixture(bytes32 marketId, address buyer, bool isYes, uint128 amount, address receiver)
        external
        returns (uint128 sharesMinted);

    function postCurveFixture(
        bytes32 marketId,
        address maker,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId
    ) external returns (uint256 curveId);

    function fillCurveFixture(uint256 curveId, address taker, uint128 collateralIn, uint128 sharesOut, uint128 fee)
        external;

    function routeTradeFixture(
        bytes32 marketId,
        address taker,
        bool isYesSide,
        uint128 totalCollateralIn,
        uint128 totalSharesOut,
        uint128 averagePrice,
        uint256 curveCount
    ) external;

    function creatorSettledFixture(bytes32 marketId, uint8 outcome) external;

    function openResolutionFixture(bytes32 marketId, address proposer, uint8 outcome) external;

    function disputeResolutionFixture(bytes32 marketId, address disputer, uint8 counterOutcome, uint8 escalationLevel)
        external;

    function resolveMarketFixture(bytes32 marketId, uint8 outcome) external;

    function resolveParimutuelMarketFixture(bytes32 marketId, uint8 outcome) external;

    function payoutReportedFixture(bytes32 marketId, uint8 outcome, bytes32 payoutVectorHash) external;

    function bondSlashedFixture(bytes32 marketId, address slashedAddress, uint128 amount) external;

    function creatorFeesForfeitedFixture(bytes32 marketId, uint128 amount) external;

    function makerFeesClaimedFixture(bytes32 marketId, address maker, uint128 amount) external;

    function creatorFeesClaimedFixture(bytes32 marketId, uint128 amount) external;

    function getConfigAddresses()
        external
        view
        returns (address conditionalTokens, address collateralToken, address eveToken, address eveTreasury);

    function getParimutuelConfigFixture()
        external
        view
        returns (address shareToken, uint16 entryFeeBps, uint128 minEntry);

    function getStoredMarket(bytes32 marketId)
        external
        view
        returns (
            address collateralToken,
            address creator,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId,
            uint128 totalFeePool,
            uint128 totalQuoteVolume,
            uint8 outcome,
            uint8 state
        );

    function getStoredMarketCore(bytes32 marketId)
        external
        view
        returns (
            address collateralToken,
            address creator,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId
        );

    function getStoredMarketAccounting(bytes32 marketId)
        external
        view
        returns (uint128 totalFeePool, uint128 totalQuoteVolume, uint8 outcome, uint8 state);

    function getStoredMarketTypeAndPositionToken(bytes32 marketId)
        external
        view
        returns (uint8 marketType, address positionToken);

    function getStoredParimutuelPoolFixture(bytes32 marketId)
        external
        view
        returns (
            uint128 totalYesShares,
            uint128 totalNoShares,
            uint128 payoutPool,
            uint128 claimedPayout,
            uint128 claimedClaimableShares,
            bool dustSwept
        );

    function getStoredCurve(uint256 curveId)
        external
        view
        returns (
            uint256 packed,
            uint128 remainingVolume,
            uint32 generation,
            bool active,
            bool isYesSide,
            address maker,
            bytes32 marketId
        );

    function getStoredCurveState(uint256 curveId)
        external
        view
        returns (
            uint128 remainingVolume,
            uint32 generation,
            bool active,
            bool isYesSide,
            address maker,
            bytes32 marketId
        );

    function getStoredCurvePacked(uint256 curveId) external view returns (uint256 packed);
}

error FunctionNotFound(bytes4 selector);

contract MockDiamond is ERC1155ReceiverHarness {
    address public immutable owner;

    mapping(bytes4 selector => address facet) internal _facets;

    constructor(address owner_) {
        owner = owner_;
    }

    function registerFacet(address facet, bytes4[] calldata selectors) external {
        if (msg.sender != owner) {
            revert Errors.NotContractOwner(msg.sender);
        }

        for (uint256 index = 0; index < selectors.length; ++index) {
            _facets[selectors[index]] = facet;
        }
    }

    function facetForSelector(bytes4 selector) external view returns (address) {
        return _facets[selector];
    }

    fallback() external payable {
        address facet = _facets[msg.sig];
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

contract TestStateFacet {
    using SafeERC20 for IERC20;

    uint256 internal constant FEE_BPS_DENOMINATOR = 10_000;

    struct ParimutuelFixtureFees {
        uint128 totalFee;
        uint128 creatorFee;
        uint128 protocolFee;
        uint128 netShares;
    }

    function configure(address conditionalTokens, address collateralToken, address eveToken, address eveTreasury)
        external
    {
        if (LibDiamond.contractOwner() == address(0)) {
            LibDiamond.setContractOwner(msg.sender);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();

        state.config.defaultConditionalTokens = conditionalTokens;
        state.config.collateralToken = collateralToken;
        state.config.eveToken = eveToken;
        state.config.bondToken = eveToken;
        state.config.eveTreasury = eveTreasury;
        state.config.permissionlessCreationEnabled = true;
        state.config.marketCreationFee = 50e6;
        state.config.marketCreationBond = 100e18;
        state.config.orderbookFeeConfig = LibEveMarket.BookFeeConfig({
            entryFeeBps: 0, makerFeeBps: 8_500, creatorFeeBps: 500, protocolFeeBps: 1_000, vaultFeeBps: 0
        });
        state.config.spotFeeConfig =
            LibEveMarket.SpotFeeConfig({tradeFeeBps: 0, makerFeeBps: 8_500, protocolFeeBps: 1_500, vaultFeeBps: 0});
        state.config.parimutuelFeeConfig = LibEveMarket.ParimutuelFeeConfig({
            entryFeeBps: 0, creatorFeeBps: 500, protocolFeeBps: 9_500, vaultFeeBps: 0
        });
        state.config.minMarketDuration = 1 hours;
        state.config.maxMarketDuration = 90 days;
        state.config.disputeWindow = 2 hours;
        state.config.creatorSettleGrace = 1 days;
        state.config.openResolutionTimeout = 2 days;
        state.config.parimutuelEpochWindowCap = 30 days;
        state.config.maxEscalation = 2;
    }

    function configureParimutuelFixture(address shareToken, uint256 entryFeeBps, uint256 minEntry) external {
        if (shareToken == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (entryFeeBps > type(uint16).max || minEntry > type(uint128).max) {
            revert Errors.InvalidAmount(entryFeeBps > type(uint16).max ? entryFeeBps : minEntry);
        }

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.parimutuelShareToken = shareToken;
        config.parimutuelFeeConfig.entryFeeBps = uint16(entryFeeBps);
        config.parimutuelMinEntry = uint128(minEntry);
    }

    function setSpotBookCreationFeeFixture(uint256 fee) external {
        if (fee > type(uint128).max) {
            revert Errors.InvalidAmount(fee);
        }
        LibEveMarket.store().config.spotBookCreationFee = uint128(fee);
    }

    function setSpotFeeConfigFixture(
        uint256 tradeFeeBps,
        uint256 makerFeeBps,
        uint256 protocolFeeBps,
        uint256 vaultFeeBps
    ) external {
        if (tradeFeeBps > type(uint16).max) revert Errors.InvalidAmount(tradeFeeBps);
        if (makerFeeBps > type(uint16).max) revert Errors.InvalidAmount(makerFeeBps);
        if (protocolFeeBps > type(uint16).max) revert Errors.InvalidAmount(protocolFeeBps);
        if (vaultFeeBps > type(uint16).max) revert Errors.InvalidAmount(vaultFeeBps);

        LibEveMarket.store().config.spotFeeConfig = LibEveMarket.SpotFeeConfig({
            tradeFeeBps: uint16(tradeFeeBps),
            makerFeeBps: uint16(makerFeeBps),
            protocolFeeBps: uint16(protocolFeeBps),
            vaultFeeBps: uint16(vaultFeeBps)
        });
    }

    function setOrderbookFeeConfigFixture(
        uint256 entryFeeBps,
        uint256 makerFeeBps,
        uint256 creatorFeeBps,
        uint256 protocolFeeBps,
        uint256 vaultFeeBps
    ) external {
        if (entryFeeBps > type(uint16).max) revert Errors.InvalidAmount(entryFeeBps);
        if (makerFeeBps > type(uint16).max) revert Errors.InvalidAmount(makerFeeBps);
        if (creatorFeeBps > type(uint16).max) revert Errors.InvalidAmount(creatorFeeBps);
        if (protocolFeeBps > type(uint16).max) revert Errors.InvalidAmount(protocolFeeBps);
        if (vaultFeeBps > type(uint16).max) revert Errors.InvalidAmount(vaultFeeBps);

        LibEveMarket.store().config.orderbookFeeConfig = LibEveMarket.BookFeeConfig({
            entryFeeBps: uint16(entryFeeBps),
            makerFeeBps: uint16(makerFeeBps),
            creatorFeeBps: uint16(creatorFeeBps),
            protocolFeeBps: uint16(protocolFeeBps),
            vaultFeeBps: uint16(vaultFeeBps)
        });
    }

    function setDelayedOrderConfigFixture(
        uint256 protectionDelayBlocks,
        uint256 executionGraceBlocks,
        uint256 restingDurationMinutes
    ) external {
        if (protectionDelayBlocks > type(uint64).max) {
            revert Errors.InvalidAmount(protectionDelayBlocks);
        }
        if (executionGraceBlocks > type(uint64).max) revert Errors.InvalidAmount(executionGraceBlocks);
        if (restingDurationMinutes > type(uint24).max) revert Errors.InvalidAmount(restingDurationMinutes);

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.delayedOrderProtectionDelayBlocks = uint64(protectionDelayBlocks);
        config.delayedOrderExecutionGraceBlocks = uint64(executionGraceBlocks);
        config.delayedOrderRestingDurationMinutes = uint24(restingDurationMinutes);
    }

    function setDelayedOrderProcessingFixture(uint256 processingMode, uint256 processorFeeShareBps) external {
        if (processingMode > uint256(uint8(LibEveMarket.ProcessingMode.Paused))) {
            revert Errors.InvalidAmount(processingMode);
        }
        if (processorFeeShareBps > 10_000) {
            revert Errors.InvalidAmount(processorFeeShareBps);
        }

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.delayedOrderProcessingMode = LibEveMarket.ProcessingMode(uint8(processingMode));
        config.delayedOrderProcessorFeeShareBps = uint16(processorFeeShareBps);
    }

    function setDelayedOrderProtocolProcessorFixture(address processor, bool allowed) external {
        LibDelayedOrder.setProtocolProcessor(processor, allowed);
    }

    function setMarketDelayedExecutionFixture(bytes32 marketId, bool enabled) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        market.delayedExecutionEnabled = enabled;
    }

    function setBookDelayedExecutionFixture(bytes32 bookId, bool enabled) external {
        LibEveMarket.Book storage book = LibEveMarket.store().books[bookId];
        if (book.bookId != bookId) {
            revert Errors.BookNotFound(bookId);
        }
        book.delayedExecutionEnabled = enabled;
    }

    function getMarketDelayedExecutionFixture(bytes32 marketId) external view returns (bool enabled) {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        enabled = market.delayedExecutionEnabled;
    }

    function getBookDelayedExecutionFixture(bytes32 bookId) external view returns (bool enabled) {
        LibEveMarket.Book storage book = LibEveMarket.store().books[bookId];
        if (book.bookId != bookId) {
            revert Errors.BookNotFound(bookId);
        }
        enabled = book.delayedExecutionEnabled;
    }

    function spotBookCreationFeeFixture() external view returns (uint128 fee) {
        fee = LibEveMarket.store().config.spotBookCreationFee;
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

    function registerCurveProfileFixture(uint8 profileId, address profileContract) external {
        LibEveMarket.store().curveProfiles[profileId] = profileContract;
    }

    function createMarketFixture(bytes32 marketId, string calldata question, address creator, uint64 expiryTime)
        external
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];

        if (market.marketId != bytes32(0)) {
            revert Errors.MarketAlreadyExists(marketId);
        }

        uint64 tradingStartTime = uint64(block.timestamp);
        bytes32 questionId = LibMarketCreation.questionIdFor(question, "binary", tradingStartTime, expiryTime);
        bytes32 resolutionId = LibMarketCreation.resolutionIdFor(marketId);
        conditionId = LibCTF.prepareMarketCondition(LibEveMarket.store().config.defaultConditionalTokens, resolutionId);
        (yesPositionId, noPositionId) = LibCTF.derivePositionIds(
            LibEveMarket.store().config.defaultConditionalTokens,
            LibEveMarket.store().config.collateralToken,
            conditionId
        );

        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.positionTokenType = LibEveMarket.PositionTokenType.CTF;
        market.positionToken = LibEveMarket.store().config.defaultConditionalTokens;
        market.collateralToken = LibEveMarket.store().config.collateralToken;
        market.creator = creator;
        market.questionId = questionId;
        market.resolutionId = resolutionId;
        market.conditionId = conditionId;
        market.yesPositionId = yesPositionId;
        market.noPositionId = noPositionId;
        market.createdAt = tradingStartTime;
        market.tradingStartTime = tradingStartTime;
        market.expiryTime = expiryTime;
        market.orderbookFeeConfig = LibEveMarket.store().config.orderbookFeeConfig;
        market.creationFeePaid = LibEveMarket.store().config.marketCreationFee;
        market.creationBond = LibEveMarket.store().config.marketCreationBond;
        market.outcome = LibEveMarket.MarketOutcome.Unresolved;
        market.state = LibEveMarket.MarketState.Trading;
        market.delayedExecutionEnabled = true;
        LibCLOBBook.setMarketBookIds(market);

        _emitMarketFixtureCreated(market, question);
    }

    function _emitMarketFixtureCreated(LibEveMarket.Market storage market, string calldata question) internal {
        emit Events.MarketCreated(
            market.marketId,
            uint8(market.marketType),
            market.creator,
            uint8(market.positionTokenType),
            market.positionToken,
            market.collateralToken,
            market.resolutionId,
            market.conditionId,
            market.yesPositionId,
            market.noPositionId,
            question,
            market.expiryTime
        );
    }

    function createParimutuelMarketFixture(
        bytes32 marketId,
        string calldata question,
        string calldata category,
        address creator,
        uint64 expiryTime
    ) external returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        if (state.config.parimutuelShareToken == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (market.marketId != bytes32(0)) {
            revert Errors.MarketAlreadyExists(marketId);
        }

        uint64 tradingStartTime = uint64(block.timestamp);
        bytes32 questionId = LibMarketCreation.questionIdFor(question, category, tradingStartTime, expiryTime);
        bytes32 resolutionId = LibMarketCreation.resolutionIdFor(marketId);
        conditionId = bytes32(0);
        yesPositionId = _parimutuelYesPositionId(marketId);
        noPositionId = _parimutuelNoPositionId(marketId);

        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.PARIMUTUEL;
        market.positionTokenType = LibEveMarket.PositionTokenType.PARIMUTUEL;
        market.positionToken = state.config.parimutuelShareToken;
        market.collateralToken = state.config.collateralToken;
        market.creator = creator;
        market.questionId = questionId;
        market.resolutionId = resolutionId;
        market.conditionId = conditionId;
        market.yesPositionId = yesPositionId;
        market.noPositionId = noPositionId;
        market.createdAt = tradingStartTime;
        market.tradingStartTime = tradingStartTime;
        market.expiryTime = expiryTime;
        market.parimutuelEpochWindow = expiryTime - tradingStartTime;
        market.parimutuelFeeConfig = state.config.parimutuelFeeConfig;
        market.creationFeePaid = state.config.parimutuelCreationSeedAmount;
        market.creationBond = state.config.marketCreationBond;
        market.outcome = LibEveMarket.MarketOutcome.Unresolved;
        market.state = LibEveMarket.MarketState.Trading;
        _setParimutuelFixturePoolSeed(marketId, state.config.parimutuelCreationSeedAmount);
        LibCLOBBook.setMarketBookIds(market);

        _emitParimutuelMarketFixtureCreated(market, question);
    }

    function _setParimutuelFixturePoolSeed(bytes32 marketId, uint128 seedAmount) internal {
        LibParimutuel.store().pools[marketId].payoutPool = seedAmount;
    }

    function _emitParimutuelMarketFixtureCreated(LibEveMarket.Market storage market, string calldata question)
        internal
    {
        emit Events.MarketCreated(
            market.marketId,
            uint8(market.marketType),
            market.creator,
            uint8(market.positionTokenType),
            market.positionToken,
            market.collateralToken,
            market.resolutionId,
            market.conditionId,
            market.yesPositionId,
            market.noPositionId,
            question,
            market.expiryTime
        );
        emit Events.ParimutuelMarketCreated(
            market.marketId,
            market.creator,
            market.positionToken,
            market.yesPositionId,
            market.noPositionId,
            market.expiryTime,
            market.parimutuelEpochWindow
        );
    }

    function buySharesFixture(bytes32 marketId, address buyer, bool isYes, uint128 amount, address receiver)
        external
        returns (uint128 sharesMinted)
    {
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.marketType != LibEveMarket.MarketType.PARIMUTUEL) {
            revert Errors.NotParimutuelMarket(marketId);
        }
        if (
            (market.state != LibEveMarket.MarketState.Trading && market.state != LibEveMarket.MarketState.Scheduled)
                || block.timestamp < market.tradingStartTime || block.timestamp >= market.expiryTime
        ) {
            revert Errors.MarketNotTrading(marketId);
        }
        if (amount < state.config.parimutuelMinEntry) {
            revert Errors.InvalidAmount(amount);
        }
        ParimutuelFixtureFees memory fees = _fixtureEntryFees(market, state.config, amount);
        sharesMinted = fees.netShares;

        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        pool.payoutPool += sharesMinted;
        if (isYes) {
            pool.totalYesShares += sharesMinted;
        } else {
            pool.totalNoShares += sharesMinted;
        }

        market.totalFeePool += fees.totalFee;
        market.totalQuoteVolume += amount;
        market.creatorFeesEscrowed += fees.creatorFee;
        market.protocolFeesAccrued += fees.protocolFee;

        IERC20 collateralToken = IERC20(market.collateralToken);
        collateralToken.safeTransferFrom(buyer, address(this), amount);
        if (fees.protocolFee != 0) {
            collateralToken.safeTransfer(state.config.eveTreasury, fees.protocolFee);
        }

        IParimutuelShareToken(market.positionToken)
            .mint(receiver, isYes ? market.yesPositionId : market.noPositionId, sharesMinted);

        emit Events.ParimutuelSharesBought(marketId, buyer, receiver, isYes, amount, sharesMinted, fees.totalFee);
    }

    function _fixtureEntryFees(
        LibEveMarket.Market storage market,
        LibEveMarket.MarketConfig storage config,
        uint128 amount
    ) internal view returns (ParimutuelFixtureFees memory fees) {
        LibEveMarket.ParimutuelFeeConfig storage feeConfig = market.parimutuelFeeConfig;
        if (uint256(feeConfig.creatorFeeBps) + feeConfig.protocolFeeBps > FEE_BPS_DENOMINATOR) {
            revert Errors.FeeSplitExceedsDenominator(feeConfig.creatorFeeBps, feeConfig.protocolFeeBps);
        }
        uint256 splitTotal = uint256(feeConfig.creatorFeeBps) + feeConfig.protocolFeeBps + feeConfig.vaultFeeBps;
        if (splitTotal != FEE_BPS_DENOMINATOR) {
            revert Errors.InvalidFeeSplit(splitTotal);
        }

        fees.totalFee = uint128((uint256(amount) * feeConfig.entryFeeBps) / FEE_BPS_DENOMINATOR);
        if (fees.totalFee >= amount) {
            revert Errors.FeeExceedsAmount(amount, fees.totalFee);
        }

        fees.creatorFee = uint128((uint256(fees.totalFee) * feeConfig.creatorFeeBps) / FEE_BPS_DENOMINATOR);
        fees.protocolFee = uint128((uint256(fees.totalFee) * feeConfig.protocolFeeBps) / FEE_BPS_DENOMINATOR);
        fees.netShares = amount - fees.totalFee;

        uint128 vaultFee = fees.totalFee - fees.creatorFee - fees.protocolFee;
        if (!config.permissionlessCreationEnabled) {
            fees.protocolFee += fees.creatorFee;
            fees.creatorFee = 0;
        }
        if (config.stakingVault == address(0)) {
            fees.protocolFee += vaultFee;
        }
    }

    function postCurveFixture(
        bytes32 marketId,
        address maker,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId
    ) external returns (uint256 curveId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        if (profileId > 2 && state.curveProfiles[profileId] == address(0)) {
            revert Errors.InvalidProfileId(profileId);
        }
        LibEveMarket.Book storage book = LibCLOBBook.ensureMarketSideBook(state, market, isYesSide);

        curveId = state.nextCurveId++;

        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.packed = LibCurvePacking.pack(startPrice, endPrice, durationMinutes, profileId);
        curve.remainingVolume = volume;
        curve.createdAt = uint64(block.timestamp);
        curve.generation = 1;
        curve.active = true;
        curve.isYesSide = isYesSide;
        curve.curveSide = LibEveMarket.CurveSide.ASK;
        curve.maker = maker;
        curve.bookId = book.bookId;

        market.curveCount += 1;
        book.curveCount += 1;
        state.bookCurveIds[book.bookId].push(curveId);

        emit Events.CurvePosted(marketId, curveId, maker, isYesSide, curve.packed);
    }

    function fillCurveFixture(uint256 curveId, address taker, uint128 collateralIn, uint128 sharesOut, uint128 fee)
        external
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];

        if (!curve.active) {
            revert Errors.CurveNotActive(curveId);
        }
        if (sharesOut > curve.remainingVolume) {
            revert Errors.InsufficientVolume(sharesOut, curve.remainingVolume);
        }

        LibEveMarket.Market storage market = state.markets[state.books[curve.bookId].marketId];
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(curve.packed);

        curve.remainingVolume -= sharesOut;
        market.lastTradePrice = params.startPrice;
        market.totalFeePool += fee;
        market.totalQuoteVolume += collateralIn;
        market.makerFeesAccrued[curve.maker] += uint128((uint256(fee) * 8_500) / 10_000);

        emit Events.CurveFilled(curveId, curve.maker, taker, collateralIn, sharesOut, fee);
    }

    function routeTradeFixture(
        bytes32 marketId,
        address taker,
        bool isYesSide,
        uint128 totalCollateralIn,
        uint128 totalSharesOut,
        uint128 averagePrice,
        uint256 curveCount
    ) external {
        emit Events.TradeRouted(marketId, taker, isYesSide, totalCollateralIn, totalSharesOut, averagePrice, curveCount);
    }

    function creatorSettledFixture(bytes32 marketId, uint8 outcome) external {
        LibEveMarket.Resolution storage resolution = LibEveMarket.store().resolutions[marketId];
        resolution.marketId = marketId;
        resolution.proposedOutcome = outcome;
        resolution.proposedAt = uint64(block.timestamp);
        resolution.disputeDeadline = uint64(block.timestamp + LibEveMarket.store().config.disputeWindow);

        emit Events.CreatorSettled(marketId, outcome);
    }

    function openResolutionFixture(bytes32 marketId, address proposer, uint8 outcome) external {
        LibEveMarket.Resolution storage resolution = LibEveMarket.store().resolutions[marketId];
        resolution.marketId = marketId;
        resolution.proposer = proposer;
        resolution.proposedOutcome = outcome;
        resolution.escalationLevel = 1;
        resolution.proposedAt = uint64(block.timestamp);
        resolution.disputeDeadline = uint64(block.timestamp + LibEveMarket.store().config.disputeWindow);

        emit Events.OpenResolutionStarted(marketId, proposer, outcome);
    }

    function disputeResolutionFixture(bytes32 marketId, address disputer, uint8 counterOutcome, uint8 escalationLevel)
        external
    {
        LibEveMarket.Resolution storage resolution = LibEveMarket.store().resolutions[marketId];
        resolution.proposer = disputer;
        resolution.proposedOutcome = counterOutcome;
        resolution.escalationLevel = escalationLevel;
        resolution.disputed = true;
        resolution.disputeDeadline = uint64(block.timestamp + LibEveMarket.store().config.disputeWindow);

        emit Events.ResolutionDisputed(marketId, disputer, counterOutcome, escalationLevel);
    }

    function resolveMarketFixture(bytes32 marketId, uint8 outcome) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        uint256[] memory payouts = _payoutVector(outcome);
        LibCTF.reportOutcome(market.positionToken, market.resolutionId, payouts);

        market.outcome = LibEveMarket.MarketOutcome(outcome);
        market.state = LibEveMarket.MarketState.Resolved;
        market.resolutionTime = uint64(block.timestamp);

        emit Events.MarketResolved(marketId, outcome);
        emit Events.ResolutionFinalized(marketId, outcome);
        emit Events.PayoutReported(marketId, outcome, keccak256(abi.encode(payouts)));
        emit Events.MarketSettled(marketId);
    }

    function resolveParimutuelMarketFixture(bytes32 marketId, uint8 outcome) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.marketType != LibEveMarket.MarketType.PARIMUTUEL) {
            revert Errors.NotParimutuelMarket(marketId);
        }

        market.outcome = LibEveMarket.MarketOutcome(outcome);
        market.state = LibEveMarket.MarketState.Resolved;
        market.resolutionTime = uint64(block.timestamp);

        emit Events.ResolutionFinalized(marketId, outcome);
    }

    function payoutReportedFixture(bytes32 marketId, uint8 outcome, bytes32 payoutVectorHash) external {
        emit Events.PayoutReported(marketId, outcome, payoutVectorHash);
    }

    function bondSlashedFixture(bytes32 marketId, address slashedAddress, uint128 amount) external {
        emit Events.BondSlashed(marketId, slashedAddress, amount);
    }

    function creatorFeesForfeitedFixture(bytes32 marketId, uint128 amount) external {
        emit Events.CreatorFeesForfeited(marketId, amount);
    }

    function makerFeesClaimedFixture(bytes32 marketId, address maker, uint128 amount) external {
        emit Events.MakerFeesClaimed(marketId, maker, amount);
    }

    function creatorFeesClaimedFixture(bytes32 marketId, uint128 amount) external {
        emit Events.CreatorFeesClaimed(marketId, amount);
    }

    function getConfigAddresses()
        external
        view
        returns (address conditionalTokens, address collateralToken, address eveToken, address eveTreasury)
    {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        conditionalTokens = config.defaultConditionalTokens;
        collateralToken = config.collateralToken;
        eveToken = config.eveToken;
        eveTreasury = config.eveTreasury;
    }

    function getParimutuelConfigFixture()
        external
        view
        returns (address shareToken, uint16 entryFeeBps, uint128 minEntry)
    {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        shareToken = config.parimutuelShareToken;
        entryFeeBps = config.parimutuelFeeConfig.entryFeeBps;
        minEntry = config.parimutuelMinEntry;
    }

    function getStoredMarket(bytes32 marketId)
        external
        view
        returns (
            address collateralToken,
            address creator,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId,
            uint128 totalFeePool,
            uint128 totalQuoteVolume,
            uint8 outcome,
            uint8 state
        )
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        collateralToken = market.collateralToken;
        creator = market.creator;
        questionId = market.questionId;
        conditionId = market.conditionId;
        yesPositionId = market.yesPositionId;
        noPositionId = market.noPositionId;
        totalFeePool = market.totalFeePool;
        totalQuoteVolume = market.totalQuoteVolume;
        outcome = uint8(market.outcome);
        state = uint8(market.state);
    }

    function getStoredMarketCore(bytes32 marketId)
        external
        view
        returns (
            address collateralToken,
            address creator,
            bytes32 questionId,
            bytes32 conditionId,
            uint256 yesPositionId,
            uint256 noPositionId
        )
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        collateralToken = market.collateralToken;
        creator = market.creator;
        questionId = market.questionId;
        conditionId = market.conditionId;
        yesPositionId = market.yesPositionId;
        noPositionId = market.noPositionId;
    }

    function getStoredMarketAccounting(bytes32 marketId)
        external
        view
        returns (uint128 totalFeePool, uint128 totalQuoteVolume, uint8 outcome, uint8 state)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        totalFeePool = market.totalFeePool;
        totalQuoteVolume = market.totalQuoteVolume;
        outcome = uint8(market.outcome);
        state = uint8(market.state);
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

    function getStoredParimutuelPoolFixture(bytes32 marketId)
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

    function getStoredCurve(uint256 curveId)
        external
        view
        returns (
            uint256 packed,
            uint128 remainingVolume,
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
        generation = curve.generation;
        active = curve.active;
        isYesSide = curve.isYesSide;
        maker = curve.maker;
        marketId = LibEveMarket.store().books[curve.bookId].marketId;
    }

    function getStoredCurveState(uint256 curveId)
        external
        view
        returns (
            uint128 remainingVolume,
            uint32 generation,
            bool active,
            bool isYesSide,
            address maker,
            bytes32 marketId
        )
    {
        LibEveMarket.StoredCurve storage curve = LibEveMarket.store().curves[curveId];
        remainingVolume = curve.remainingVolume;
        generation = curve.generation;
        active = curve.active;
        isYesSide = curve.isYesSide;
        maker = curve.maker;
        marketId = LibEveMarket.store().books[curve.bookId].marketId;
    }

    function getStoredCurvePacked(uint256 curveId) external view returns (uint256 packed) {
        packed = LibEveMarket.store().curves[curveId].packed;
    }

    function _payoutVector(uint8 outcome) internal pure returns (uint256[] memory payouts) {
        payouts = new uint256[](2);

        if (outcome == 1) {
            payouts[0] = 1;
            payouts[1] = 0;
            return payouts;
        }

        if (outcome == 2) {
            payouts[0] = 0;
            payouts[1] = 1;
            return payouts;
        }

        payouts[0] = 1;
        payouts[1] = 1;
    }

    function _parimutuelYesPositionId(bytes32 marketId) internal view returns (uint256) {
        return LibMarketCreation.parimutuelPositionId(address(this), marketId, 1);
    }

    function _parimutuelNoPositionId(bytes32 marketId) internal view returns (uint256) {
        return LibMarketCreation.parimutuelPositionId(address(this), marketId, 2);
    }
}

abstract contract TestBase is Test, ERC1155ReceiverHarness {
    string internal constant DEFAULT_CATEGORY = "binary";
    uint16 internal constant DEFAULT_PARIMUTUEL_ENTRY_FEE_BPS = 250;
    uint128 internal constant DEFAULT_PARIMUTUEL_MIN_ENTRY = 1e6;

    address internal owner;
    address internal creator;
    address internal maker;
    address internal taker;
    address internal disputer;
    address internal treasury;

    MockDiamond internal diamond;
    TestStateFacet internal stateFacet;
    MockConditionalTokens internal conditionalTokens;
    MockUSDC internal usdc;
    MockEveToken internal eveToken;
    MockCurveProfile internal curveProfile;
    ParimutuelShareToken internal parimutuelShareToken;

    function setUp() public virtual {
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        disputer = makeAddr("disputer");
        treasury = makeAddr("treasury");

        conditionalTokens = new MockConditionalTokens();
        usdc = new MockUSDC();
        eveToken = new MockEveToken();
        curveProfile = new MockCurveProfile();

        diamond = new MockDiamond(owner);
        parimutuelShareToken = new ParimutuelShareToken(address(diamond), "uri://parimutuel/{id}");
        stateFacet = new TestStateFacet();

        bytes4[] memory selectors = new bytes4[](41);
        selectors[0] = ITestStateFacet.configure.selector;
        selectors[1] = ITestStateFacet.configureParimutuelFixture.selector;
        selectors[2] = ITestStateFacet.setSpotBookCreationFeeFixture.selector;
        selectors[3] = ITestStateFacet.spotBookCreationFeeFixture.selector;
        selectors[4] = ITestStateFacet.registerCurveProfileFixture.selector;
        selectors[5] = ITestStateFacet.createMarketFixture.selector;
        selectors[6] = ITestStateFacet.createParimutuelMarketFixture.selector;
        selectors[7] = ITestStateFacet.buySharesFixture.selector;
        selectors[8] = ITestStateFacet.postCurveFixture.selector;
        selectors[9] = ITestStateFacet.fillCurveFixture.selector;
        selectors[10] = ITestStateFacet.routeTradeFixture.selector;
        selectors[11] = ITestStateFacet.creatorSettledFixture.selector;
        selectors[12] = ITestStateFacet.openResolutionFixture.selector;
        selectors[13] = ITestStateFacet.disputeResolutionFixture.selector;
        selectors[14] = ITestStateFacet.resolveMarketFixture.selector;
        selectors[15] = ITestStateFacet.resolveParimutuelMarketFixture.selector;
        selectors[16] = ITestStateFacet.payoutReportedFixture.selector;
        selectors[17] = ITestStateFacet.bondSlashedFixture.selector;
        selectors[18] = ITestStateFacet.creatorFeesForfeitedFixture.selector;
        selectors[19] = ITestStateFacet.makerFeesClaimedFixture.selector;
        selectors[20] = ITestStateFacet.creatorFeesClaimedFixture.selector;
        selectors[21] = ITestStateFacet.getConfigAddresses.selector;
        selectors[22] = ITestStateFacet.getParimutuelConfigFixture.selector;
        selectors[23] = ITestStateFacet.getStoredMarket.selector;
        selectors[24] = ITestStateFacet.getStoredMarketCore.selector;
        selectors[25] = ITestStateFacet.getStoredMarketAccounting.selector;
        selectors[26] = ITestStateFacet.getStoredMarketTypeAndPositionToken.selector;
        selectors[27] = ITestStateFacet.getStoredParimutuelPoolFixture.selector;
        selectors[28] = ITestStateFacet.getStoredCurveState.selector;
        selectors[29] = ITestStateFacet.getStoredCurvePacked.selector;
        selectors[30] = ITestStateFacet.setBookPricingFixture.selector;
        selectors[31] = ITestStateFacet.setSpotFeeConfigFixture.selector;
        selectors[32] = ITestStateFacet.materializeMarketSideBookFixture.selector;
        selectors[33] = ITestStateFacet.setDelayedOrderConfigFixture.selector;
        selectors[34] = ITestStateFacet.setDelayedOrderProcessingFixture.selector;
        selectors[35] = ITestStateFacet.setDelayedOrderProtocolProcessorFixture.selector;
        selectors[36] = ITestStateFacet.setOrderbookFeeConfigFixture.selector;
        selectors[37] = ITestStateFacet.setMarketDelayedExecutionFixture.selector;
        selectors[38] = ITestStateFacet.setBookDelayedExecutionFixture.selector;
        selectors[39] = ITestStateFacet.getMarketDelayedExecutionFixture.selector;
        selectors[40] = ITestStateFacet.getBookDelayedExecutionFixture.selector;

        vm.prank(owner);
        diamond.registerFacet(address(stateFacet), selectors);

        vm.startPrank(owner);
        ITestStateFacet(address(diamond))
            .configure(address(conditionalTokens), address(usdc), address(eveToken), treasury);
        ITestStateFacet(address(diamond))
            .configureParimutuelFixture(
                address(parimutuelShareToken), DEFAULT_PARIMUTUEL_ENTRY_FEE_BPS, DEFAULT_PARIMUTUEL_MIN_ENTRY
            );
        ITestStateFacet(address(diamond)).registerCurveProfileFixture(3, address(curveProfile));
        vm.stopPrank();

        _seedBalances();
    }

    function _seedBalances() internal {
        usdc.mint(creator, 1_000_000e6);
        usdc.mint(maker, 1_000_000e6);
        usdc.mint(taker, 1_000_000e6);

        eveToken.mint(creator, 1_000_000e18);
        eveToken.mint(disputer, 1_000_000e18);
    }

    function _marketIdFor(string memory question, uint64 expiryTime) internal view returns (bytes32) {
        return LibMarketCreation.marketIdFor(
            question,
            DEFAULT_CATEGORY,
            uint64(block.timestamp),
            expiryTime,
            address(usdc),
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
    }

    function _parimutuelMarketIdFor(string memory question, uint64 expiryTime) internal view returns (bytes32) {
        return LibMarketCreation.marketIdFor(
            question,
            DEFAULT_CATEGORY,
            uint64(block.timestamp),
            expiryTime,
            address(usdc),
            LibEveMarket.MarketType.PARIMUTUEL,
            LibEveMarket.PositionTokenType.PARIMUTUEL
        );
    }

    function _createMarketFixture(string memory question, uint64 expiryTime)
        internal
        returns (bytes32 marketId, bytes32 conditionId)
    {
        marketId = _marketIdFor(question, expiryTime);
        (conditionId,,) = ITestStateFacet(address(diamond)).createMarketFixture(marketId, question, creator, expiryTime);
    }

    function _createParimutuelMarketFixture(string memory question, uint64 expiryTime)
        internal
        returns (bytes32 marketId, bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId)
    {
        marketId = _parimutuelMarketIdFor(question, expiryTime);
        (conditionId, yesPositionId, noPositionId) = ITestStateFacet(address(diamond))
            .createParimutuelMarketFixture(marketId, question, DEFAULT_CATEGORY, creator, expiryTime);
    }

    function _buySharesFixture(address buyer, bytes32 marketId, bool isYes, uint128 amount)
        internal
        returns (uint128 sharesMinted)
    {
        sharesMinted = _buySharesFixture(buyer, marketId, isYes, amount, buyer);
    }

    function _buySharesFixture(address buyer, bytes32 marketId, bool isYes, uint128 amount, address receiver)
        internal
        returns (uint128 sharesMinted)
    {
        vm.prank(buyer);
        usdc.approve(address(diamond), amount);

        sharesMinted = ITestStateFacet(address(diamond)).buySharesFixture(marketId, buyer, isYes, amount, receiver);
    }

    function _postCurveFixture(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId
    ) internal returns (uint256 curveId) {
        curveId = ITestStateFacet(address(diamond))
            .postCurveFixture(marketId, maker, isYesSide, volume, startPrice, endPrice, durationMinutes, profileId);
    }

    function _fillCurveFixture(uint256 curveId, uint128 collateralIn, uint128 sharesOut, uint128 fee) internal {
        ITestStateFacet(address(diamond)).fillCurveFixture(curveId, taker, collateralIn, sharesOut, fee);
    }

    function _resolveMarketFixture(bytes32 marketId, uint8 outcome) internal {
        ITestStateFacet(address(diamond)).resolveMarketFixture(marketId, outcome);
    }

    function _resolveParimutuelMarketFixture(bytes32 marketId, uint8 outcome) internal {
        ITestStateFacet(address(diamond)).resolveParimutuelMarketFixture(marketId, outcome);
    }
}
