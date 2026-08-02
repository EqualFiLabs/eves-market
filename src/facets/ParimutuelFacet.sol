// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {ISeniorCapitalPool} from "../interfaces/ISeniorCapitalPool.sol";
import {IEvRiskStakingRewards} from "../interfaces/IEvRiskStakingRewards.sol";
import {IParimutuelFacet} from "../interfaces/IParimutuelFacet.sol";
import {IParimutuelShareToken} from "../interfaces/IParimutuelShareToken.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibCollateralProfile} from "../libraries/LibCollateralProfile.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibFeeRouting} from "../libraries/LibFeeRouting.sol";
import {LibMarketCreation} from "../libraries/LibMarketCreation.sol";
import {LibMarketMetadata} from "../libraries/LibMarketMetadata.sol";
import {LibParimutuel} from "../libraries/LibParimutuel.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibResolverRewards} from "../libraries/LibResolverRewards.sol";
import {LibSafeCast} from "../libraries/LibSafeCast.sol";
import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

contract ParimutuelFacet {
    using SafeERC20 for IERC20;
    using LibParimutuel for LibParimutuel.Storage;

    uint256 internal constant FEE_BPS_DENOMINATOR = 10_000;
    uint256 internal constant PROBABILITY_SCALE = 1e18;
    uint256 internal constant EPOCH_MULTIPLIER_SCALE = 10_000;
    uint256 internal constant EPOCH_COUNT = 8;
    uint128 internal constant DEFAULT_EVEUSDC_PAYOUT_UNIT = 1 ether;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    struct EntryFeeBreakdown {
        uint128 totalFee;
        uint128 creatorFee;
        uint128 protocolFee;
        uint128 seniorPoolFee;
        uint128 resolverFee;
        uint128 evRiskFee;
        uint128 netShares;
    }

    struct CreateParimutuelArgs {
        string question;
        string category;
        string resolutionSource;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint64 epochWindow;
        MarketFactoryTypes.MarketDisplayInput display;
        MarketFactoryTypes.ExternalMarketRefInput externalRef;
    }

    struct ParimutuelCollateralContext {
        uint8 profileId;
        address collateralToken;
        uint128 payoutUnit;
        uint128 creationSeedAmount;
        bool emitProfileEvent;
    }

    function createParimutuelMarket(IParimutuelFacet.CreateParimutuelMarketParams calldata params)
        external
        nonReentrant
        returns (bytes32 marketId)
    {
        marketId = _createParimutuelMarket(_createParimutuelArgs(params));
    }

    function createParimutuelMarket(
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint64 epochWindow
    ) external nonReentrant returns (bytes32 marketId) {
        marketId = _createParimutuelMarket(
            CreateParimutuelArgs({
                question: question,
                category: category,
                resolutionSource: resolutionSource,
                tradingStartTime: tradingStartTime,
                expiryTime: expiryTime,
                epochWindow: epochWindow,
                display: LibMarketMetadata.emptyDisplayInput(),
                externalRef: LibMarketMetadata.emptyExternalRefInput()
            })
        );
    }

    function createParimutuelMarketWithCollateralProfile(
        uint8 profileId,
        IParimutuelFacet.CreateParimutuelMarketParams calldata params
    ) external nonReentrant returns (bytes32 marketId) {
        marketId = _createProfileParimutuelMarket(profileId, _createParimutuelArgs(params));
    }

    function createParimutuelMarketWithCollateralProfile(
        uint8 profileId,
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint64 epochWindow
    ) external nonReentrant returns (bytes32 marketId) {
        marketId = _createProfileParimutuelMarket(
            profileId,
            CreateParimutuelArgs({
                question: question,
                category: category,
                resolutionSource: resolutionSource,
                tradingStartTime: tradingStartTime,
                expiryTime: expiryTime,
                epochWindow: epochWindow,
                display: LibMarketMetadata.emptyDisplayInput(),
                externalRef: LibMarketMetadata.emptyExternalRefInput()
            })
        );
    }

    function _createParimutuelArgs(IParimutuelFacet.CreateParimutuelMarketParams calldata params)
        internal
        pure
        returns (CreateParimutuelArgs memory args)
    {
        args = CreateParimutuelArgs({
            question: params.question,
            category: params.category,
            resolutionSource: params.resolutionSource,
            tradingStartTime: params.tradingStartTime,
            expiryTime: params.expiryTime,
            epochWindow: params.epochWindow,
            display: params.display,
            externalRef: params.externalRef
        });
    }

    function _createProfileParimutuelMarket(uint8 profileId, CreateParimutuelArgs memory args)
        internal
        returns (bytes32 marketId)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.CollateralProfile storage profile = LibCollateralProfile.requireEnabled(state, profileId);

        marketId = _createParimutuelMarket(
            args,
            ParimutuelCollateralContext({
                profileId: profileId,
                collateralToken: profile.collateralToken,
                payoutUnit: profile.payoutUnit,
                creationSeedAmount: state.parimutuelProfileCreationSeedAmount[profileId],
                emitProfileEvent: true
            })
        );
    }

    function _createParimutuelMarket(CreateParimutuelArgs memory args) internal returns (bytes32 marketId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MarketConfig storage config = state.config;

        marketId = _createParimutuelMarket(
            args,
            ParimutuelCollateralContext({
                profileId: 0,
                collateralToken: config.collateralToken,
                payoutUnit: DEFAULT_EVEUSDC_PAYOUT_UNIT,
                creationSeedAmount: config.parimutuelCreationSeedAmount,
                emitProfileEvent: false
            })
        );
    }

    function _createParimutuelMarket(
        CreateParimutuelArgs memory args,
        ParimutuelCollateralContext memory collateralContext
    ) internal returns (bytes32 marketId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MarketConfig storage config = state.config;

        if (config.parimutuelShareToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibMarketCreation.CreationInput memory creation;
        (creation.creationFee, creation.creationBond) = LibMarketCreation.parimutuelCreationCostsForCaller(
            config.permissionlessCreationEnabled, collateralContext.creationSeedAmount, config.marketCreationBond
        );
        creation.currentTimestamp = LibMarketCreation.validateSchedule(
            args.tradingStartTime, args.expiryTime, config.minMarketDuration, config.maxMarketDuration
        );
        creation.tradingStartTime = args.tradingStartTime;
        creation.expiryTime = args.expiryTime;
        _validateParimutuelEpochWindow(config, creation.tradingStartTime, creation.expiryTime, args.epochWindow);

        marketId = collateralContext.emitProfileEvent
            ? LibMarketCreation.profileMarketIdFor(
                args.question,
                args.category,
                args.tradingStartTime,
                args.expiryTime,
                collateralContext.collateralToken,
                collateralContext.profileId,
                collateralContext.payoutUnit,
                LibEveMarket.MarketType.PARIMUTUEL,
                LibEveMarket.PositionTokenType.PARIMUTUEL
            )
            : LibMarketCreation.marketIdFor(
                args.question,
                args.category,
                args.tradingStartTime,
                args.expiryTime,
                collateralContext.collateralToken,
                LibEveMarket.MarketType.PARIMUTUEL,
                LibEveMarket.PositionTokenType.PARIMUTUEL
            );
        if (state.markets[marketId].marketId != bytes32(0)) {
            revert Errors.MarketAlreadyExists(marketId);
        }

        LibMarketCreation.validateFunding(
            IERC20(collateralContext.collateralToken),
            IERC20(config.bondToken),
            msg.sender,
            creation.creationFee,
            creation.creationBond,
            0
        );

        LibMarketCreation.CreationDetails memory details = LibMarketCreation.prepareParimutuelCreationDetails(
            args.question, args.category, creation.tradingStartTime, creation.expiryTime, marketId
        );

        LibEveMarket.Market storage market = state.markets[marketId];
        LibMarketCreation.storeMarket(
            market,
            marketId,
            LibEveMarket.MarketType.PARIMUTUEL,
            LibEveMarket.PositionTokenType.PARIMUTUEL,
            config.parimutuelShareToken,
            collateralContext.collateralToken,
            msg.sender,
            details,
            creation
        );
        market.collateralProfileId = collateralContext.profileId;
        market.payoutUnit = collateralContext.payoutUnit;
        market.parimutuelEpochWindow = args.epochWindow;
        LibCLOBBook.setMarketBookIds(market);
        LibMarketMetadata.registerMarketMetadata(market, args.question, args.category, args.resolutionSource);
        bytes32 externalRefHash = LibMarketMetadata.registerMarketExternalReference(marketId, args.externalRef);
        LibMarketMetadata.registerMarketDisplayMetadata(marketId, args.display, externalRefHash);

        _seedParimutuelPool(collateralContext.collateralToken, marketId, msg.sender, creation.creationFee);
        LibMarketCreation.collectCreationBond(config.bondToken, marketId, msg.sender, creation.creationBond);

        _emitParimutuelMarketCreated(market, args.question);
        if (collateralContext.emitProfileEvent) {
            emit Events.MarketCollateralProfile(
                marketId,
                collateralContext.profileId,
                collateralContext.collateralToken,
                collateralContext.payoutUnit,
                creation.creationFee
            );
        }
        if (creation.creationFee != 0) {
            emit Events.ParimutuelCreationSeeded(marketId, msg.sender, creation.creationFee);
        }
    }

    function buyShares(bytes32 marketId, bool isYes, uint128 amount, address receiver, uint128 minSharesOut)
        external
        nonReentrant
        returns (uint128 sharesMinted)
    {
        LibParimutuel.Storage storage parimutuel = LibParimutuel.store();
        sharesMinted = _buyShares(LibEveMarket.store(), parimutuel, marketId, isYes, amount, receiver, minSharesOut);
    }

    function buySharesBatch(
        bytes32[] calldata marketIds,
        bool[] calldata isYes,
        uint128[] calldata amounts,
        uint128[] calldata minSharesOut,
        address receiver
    ) external nonReentrant returns (uint128[] memory sharesMinted) {
        uint256 length = marketIds.length;
        if (isYes.length != length) {
            revert Errors.ArrayLengthMismatch(length, isYes.length);
        }
        if (amounts.length != length) {
            revert Errors.ArrayLengthMismatch(length, amounts.length);
        }
        if (minSharesOut.length != length) {
            revert Errors.ArrayLengthMismatch(length, minSharesOut.length);
        }

        sharesMinted = new uint128[](length);
        for (uint256 index = 0; index < length; ++index) {
            sharesMinted[index] = _buyShares(
                LibEveMarket.store(),
                LibParimutuel.store(),
                marketIds[index],
                isYes[index],
                amounts[index],
                receiver,
                minSharesOut[index]
            );
        }
    }

    function claimPayout(bytes32 marketId) external nonReentrant returns (uint128 payout) {
        LibParimutuel.Storage storage parimutuel = LibParimutuel.store();
        payout = _claimPayout(LibEveMarket.store(), parimutuel, marketId);
    }

    function sweepParimutuelDust(bytes32 marketId) external nonReentrant returns (uint128 swept) {
        LibParimutuel.Storage storage parimutuel = LibParimutuel.store();
        swept = _sweepParimutuelDust(LibEveMarket.store(), parimutuel, marketId);
    }

    function _buyShares(
        LibEveMarket.EveMarketStorage storage state,
        LibParimutuel.Storage storage parimutuel,
        bytes32 marketId,
        bool isYes,
        uint128 amount,
        address receiver,
        uint128 minSharesOut
    ) internal returns (uint128 sharesMinted) {
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.Market storage market = _requireTradingParimutuelMarket(state, marketId);
        LibEveMarket.MarketConfig storage config = state.config;

        if (amount < _parimutuelMinEntryFor(state, market)) {
            revert Errors.InvalidAmount(amount);
        }

        EntryFeeBreakdown memory fees = _entryFeeBreakdown(market, config, amount);
        uint128 netCollateral = fees.netShares;

        uint256 multiplierBps = _epochMultiplier(market.tradingStartTime, market.parimutuelEpochWindow);
        uint256 computedShares = (uint256(netCollateral) * multiplierBps) / EPOCH_MULTIPLIER_SCALE;
        if (computedShares == 0) {
            revert Errors.ParimutuelSharesWouldRoundToZero(marketId, netCollateral, multiplierBps);
        }
        sharesMinted = LibSafeCast.toUint128(computedShares);
        if (sharesMinted < minSharesOut) {
            revert Errors.SlippageExceeded(sharesMinted, minSharesOut);
        }

        LibParimutuel.Pool storage pool = parimutuel.pools[marketId];
        pool.payoutPool += netCollateral;
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
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        if (fees.protocolFee != 0) {
            collateralToken.safeTransfer(config.eveTreasury, fees.protocolFee);
        }
        if (fees.seniorPoolFee != 0) {
            collateralToken.forceApprove(config.seniorCapitalPool, fees.seniorPoolFee);
            ISeniorCapitalPool(config.seniorCapitalPool).notifyRevenue(market.collateralToken, fees.seniorPoolFee);
        }
        if (fees.evRiskFee != 0) {
            collateralToken.forceApprove(config.evRiskStakingRewards, fees.evRiskFee);
            IEvRiskStakingRewards(config.evRiskStakingRewards).notifyReward(market.collateralToken, fees.evRiskFee);
        }
        LibResolverRewards.accrueTradingFee(market.collateralToken, fees.resolverFee);

        IParimutuelShareToken(market.positionToken)
            .mint(receiver, isYes ? market.yesPositionId : market.noPositionId, sharesMinted);

        _emitSharesBought(marketId, receiver, isYes, amount, sharesMinted, fees.totalFee);
    }

    function _emitParimutuelMarketCreated(LibEveMarket.Market storage market, string memory question) internal {
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

    function _emitSharesBought(
        bytes32 marketId,
        address receiver,
        bool isYes,
        uint128 amount,
        uint128 sharesMinted,
        uint128 totalFee
    ) internal {
        emit Events.ParimutuelSharesBought(marketId, msg.sender, receiver, isYes, amount, sharesMinted, totalFee);
    }

    function _seedParimutuelPool(address collateralToken, bytes32 marketId, address creator, uint128 seedAmount)
        internal
    {
        if (seedAmount == 0) {
            return;
        }

        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        pool.payoutPool += seedAmount;
        IERC20(collateralToken).safeTransferFrom(creator, address(this), seedAmount);
    }

    function _claimPayout(
        LibEveMarket.EveMarketStorage storage state,
        LibParimutuel.Storage storage parimutuel,
        bytes32 marketId
    ) internal returns (uint128 payout) {
        LibEveMarket.Market storage market = _requireResolvedParimutuelMarket(state, marketId);
        LibParimutuel.Pool storage pool = parimutuel.pools[marketId];
        LibParimutuel.requireFinalized(pool, marketId);
        LibEveMarket.MarketOutcome payoutOutcome = pool.effectivePayoutOutcome;

        if (payoutOutcome == LibEveMarket.MarketOutcome.Yes) {
            payout = _claimWinningSide(market, pool, market.yesPositionId, pool.totalClaimableSharesAtResolution);
        } else if (payoutOutcome == LibEveMarket.MarketOutcome.No) {
            payout = _claimWinningSide(market, pool, market.noPositionId, pool.totalClaimableSharesAtResolution);
        } else {
            payout = _claimInvalid(market, pool);
        }

        if (payout != 0) {
            IERC20(market.collateralToken).safeTransfer(msg.sender, payout);
        }
    }

    function _claimWinningSide(
        LibEveMarket.Market storage market,
        LibParimutuel.Pool storage pool,
        uint256 positionId,
        uint128 totalWinningShares
    ) internal returns (uint128 payout) {
        uint256 shares = IERC1155(market.positionToken).balanceOf(msg.sender, positionId);
        if (shares == 0) {
            revert Errors.NoWinningShares(market.marketId, msg.sender);
        }

        uint128 sharesBurned = LibSafeCast.toUint128(shares);
        payout = uint128((uint256(sharesBurned) * pool.payoutPoolAtResolution) / totalWinningShares);

        pool.claimedClaimableShares += sharesBurned;
        pool.claimedPayout += payout;

        IParimutuelShareToken(market.positionToken).burn(msg.sender, positionId, sharesBurned);

        emit Events.ParimutuelPayoutClaimed(market.marketId, msg.sender, positionId, sharesBurned, payout);
    }

    function _claimInvalid(LibEveMarket.Market storage market, LibParimutuel.Pool storage pool)
        internal
        returns (uint128 payout)
    {
        (uint256 yesShares, uint256 noShares) = _balances(market, msg.sender);
        if (yesShares == 0 && noShares == 0) {
            revert Errors.NoWinningShares(market.marketId, msg.sender);
        }

        uint128 yesSharesBurned = LibSafeCast.toUint128(yesShares);
        uint128 noSharesBurned = LibSafeCast.toUint128(noShares);
        uint128 totalSharesBurned = yesSharesBurned + noSharesBurned;

        payout =
            uint128((uint256(totalSharesBurned) * pool.payoutPoolAtResolution) / pool.totalClaimableSharesAtResolution);
        pool.claimedClaimableShares += totalSharesBurned;
        pool.claimedPayout += payout;

        IParimutuelShareToken shareToken = IParimutuelShareToken(market.positionToken);
        if (yesSharesBurned != 0) {
            shareToken.burn(msg.sender, market.yesPositionId, yesSharesBurned);
            emit Events.ParimutuelPayoutClaimed(
                market.marketId, msg.sender, market.yesPositionId, yesSharesBurned, payout
            );
        }
        if (noSharesBurned != 0) {
            shareToken.burn(msg.sender, market.noPositionId, noSharesBurned);
            if (yesSharesBurned == 0) {
                emit Events.ParimutuelPayoutClaimed(
                    market.marketId, msg.sender, market.noPositionId, noSharesBurned, payout
                );
            }
        }
    }

    function _sweepParimutuelDust(
        LibEveMarket.EveMarketStorage storage state,
        LibParimutuel.Storage storage parimutuel,
        bytes32 marketId
    ) internal returns (uint128 swept) {
        LibEveMarket.Market storage market = _requireResolvedParimutuelMarket(state, marketId);
        LibParimutuel.Pool storage pool = parimutuel.pools[marketId];

        if (pool.dustSwept) {
            revert Errors.AlreadyClaimed(marketId, msg.sender);
        }

        uint256 remainingShares = _remainingClaimableShares(pool, marketId);
        if (remainingShares != 0) {
            revert Errors.ClaimableSharesRemain(marketId, remainingShares);
        }

        swept = pool.payoutPoolAtResolution - pool.claimedPayout;
        pool.dustSwept = true;

        address recipient = market.creatorFeeEligible ? market.creator : state.config.eveTreasury;
        if (swept != 0) {
            IERC20(market.collateralToken).safeTransfer(recipient, swept);
        }

        emit Events.ParimutuelDustSwept(marketId, recipient, swept);
    }

    function _entryFeeBreakdown(
        LibEveMarket.Market storage market,
        LibEveMarket.MarketConfig storage config,
        uint128 amount
    ) internal view returns (EntryFeeBreakdown memory fees) {
        LibEveMarket.ParimutuelFeeConfig storage feeConfig = market.parimutuelFeeConfig;
        if (
            uint256(feeConfig.creatorFeeBps) + feeConfig.protocolFeeBps + feeConfig.resolverFeeBps
                    + feeConfig.evRiskFeeBps
                > FEE_BPS_DENOMINATOR
        ) {
            revert Errors.FeeSplitExceedsDenominator(feeConfig.creatorFeeBps, feeConfig.protocolFeeBps);
        }
        uint256 splitTotal = uint256(feeConfig.creatorFeeBps) + feeConfig.protocolFeeBps + feeConfig.vaultFeeBps
            + feeConfig.resolverFeeBps + feeConfig.evRiskFeeBps;
        if (splitTotal != FEE_BPS_DENOMINATOR) {
            revert Errors.InvalidFeeSplit(splitTotal);
        }

        fees.totalFee = uint128((uint256(amount) * feeConfig.entryFeeBps) / FEE_BPS_DENOMINATOR);
        if (fees.totalFee >= amount) {
            revert Errors.FeeExceedsAmount(amount, fees.totalFee);
        }

        fees.creatorFee = uint128((uint256(fees.totalFee) * feeConfig.creatorFeeBps) / FEE_BPS_DENOMINATOR);
        fees.protocolFee = uint128((uint256(fees.totalFee) * feeConfig.protocolFeeBps) / FEE_BPS_DENOMINATOR);
        fees.resolverFee = uint128((uint256(fees.totalFee) * feeConfig.resolverFeeBps) / FEE_BPS_DENOMINATOR);
        fees.evRiskFee = uint128((uint256(fees.totalFee) * feeConfig.evRiskFeeBps) / FEE_BPS_DENOMINATOR);
        uint128 rawSeniorPoolFee = fees.totalFee - fees.creatorFee - fees.protocolFee - fees.resolverFee
            - fees.evRiskFee;
        fees.netShares = amount - fees.totalFee;

        if (!config.permissionlessCreationEnabled) {
            fees.protocolFee += fees.creatorFee;
            fees.creatorFee = 0;
        }

        LibFeeRouting.SeniorPoolFeeRoute memory route =
            LibFeeRouting.previewSeniorPoolFeeRoute(config.seniorCapitalPool, market.collateralToken, rawSeniorPoolFee);
        fees.seniorPoolFee = uint128(route.seniorPoolAmount);
        fees.protocolFee += uint128(route.treasuryAmount);

        LibFeeRouting.EvRiskFeeRoute memory evRiskRoute =
            LibFeeRouting.previewEvRiskFeeRoute(config.evRiskStakingRewards, fees.evRiskFee);
        fees.evRiskFee = uint128(evRiskRoute.evRiskAmount);
        fees.protocolFee += uint128(evRiskRoute.treasuryAmount);
    }

    function _remainingClaimableShares(LibParimutuel.Pool storage pool, bytes32 marketId)
        internal
        view
        returns (uint256 remainingShares)
    {
        LibParimutuel.requireFinalized(pool, marketId);
        remainingShares = pool.totalClaimableSharesAtResolution - pool.claimedClaimableShares;
    }

    function _requireParimutuelMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.marketType != LibEveMarket.MarketType.PARIMUTUEL) {
            revert Errors.NotParimutuelMarket(marketId);
        }
    }

    function _requireTradingParimutuelMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = _requireParimutuelMarket(state, marketId);
        if (!_marketEntriesOpen(market)) {
            revert Errors.MarketNotTrading(marketId);
        }
    }

    function _marketEntriesOpen(LibEveMarket.Market storage market) internal view returns (bool) {
        return (market.state == LibEveMarket.MarketState.Trading || market.state == LibEveMarket.MarketState.Scheduled)
            && block.timestamp >= market.tradingStartTime && block.timestamp < market.expiryTime;
    }

    function _requireResolvedParimutuelMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = _requireParimutuelMarket(state, marketId);
        if (market.state != LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketNotResolved(marketId);
        }
    }

    function _parimutuelMinEntryFor(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Market storage market)
        internal
        view
        returns (uint128 minEntry)
    {
        if (market.collateralProfileId == 0) {
            return state.config.parimutuelMinEntry;
        }
        return state.parimutuelProfileMinEntry[market.collateralProfileId];
    }

    function _balances(LibEveMarket.Market storage market, address user)
        internal
        view
        returns (uint256 yesShares, uint256 noShares)
    {
        IERC1155 positionToken = IERC1155(market.positionToken);
        yesShares = positionToken.balanceOf(user, market.yesPositionId);
        noShares = positionToken.balanceOf(user, market.noPositionId);
    }

    function _epochMultiplier(uint64 tradingStartTime, uint64 epochWindow) internal view returns (uint256) {
        return _parimutuelMultiplierBps(_currentEpoch(tradingStartTime, epochWindow));
    }

    function _currentEpoch(uint64 tradingStartTime, uint64 epochWindow) internal view returns (uint256 epoch) {
        uint256 elapsed = block.timestamp > tradingStartTime ? block.timestamp - tradingStartTime : 0;
        epoch = elapsed >= epochWindow ? EPOCH_COUNT - 1 : (elapsed * EPOCH_COUNT) / epochWindow;
    }

    function _validateParimutuelEpochWindow(
        LibEveMarket.MarketConfig storage config,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint64 epochWindow
    ) internal view {
        uint64 duration = expiryTime - tradingStartTime;
        uint64 cap = config.parimutuelEpochWindowCap;
        uint64 maxEpochWindow = cap < duration ? cap : duration;
        if (epochWindow == 0 || epochWindow > cap || epochWindow > duration) {
            revert Errors.InvalidParimutuelEpochWindow(epochWindow, maxEpochWindow);
        }
    }

    function _parimutuelMultiplierBps(uint256 epoch) internal view returns (uint16) {
        uint256 boundedEpoch = epoch >= EPOCH_COUNT ? EPOCH_COUNT - 1 : epoch;
        uint16 configured = LibEveMarket.store().config.parimutuelEpochMultipliersBps[boundedEpoch];

        return configured == 0 ? _defaultParimutuelMultiplierBps(boundedEpoch) : configured;
    }

    function _defaultParimutuelMultiplierBps(uint256 epoch) internal pure returns (uint16) {
        if (epoch == 0) return 20_000; // 2.0x
        if (epoch == 1) return 15_000; // 1.5x
        if (epoch == 2) return 11_500; // 1.15x
        if (epoch == 3) return 10_000; // 1.0x
        if (epoch == 4) return 8_500; // 0.85x
        if (epoch == 5) return 7_000; // 0.7x
        if (epoch == 6) return 5_500; // 0.55x
        return 4_000; // 0.4x
    }

    function _parimutuelYesPositionId(bytes32 marketId) internal view returns (uint256) {
        return LibMarketCreation.parimutuelPositionId(marketId, 1);
    }

    function _parimutuelNoPositionId(bytes32 marketId) internal view returns (uint256) {
        return LibMarketCreation.parimutuelPositionId(marketId, 2);
    }
}
