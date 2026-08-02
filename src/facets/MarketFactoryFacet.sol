// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibCTF} from "../libraries/LibCTF.sol";
import {LibCollateralProfile} from "../libraries/LibCollateralProfile.sol";
import {LibCurvePacking} from "../libraries/LibCurvePacking.sol";
import {LibCurveIndex} from "../libraries/LibCurveIndex.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibMarketCreation} from "../libraries/LibMarketCreation.sol";
import {LibMarketMetadata} from "../libraries/LibMarketMetadata.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

contract MarketFactoryFacet is MarketFactoryTypes {
    using SafeERC20 for IERC20;

    uint128 internal constant DEFAULT_COLLATERAL_PAYOUT_UNIT = 1 ether;
    uint72 internal constant FIFTY_FIFTY_PRICE = 500_000_000;
    uint8 internal constant LINEAR_PROFILE_ID = 0;

    struct CreateMarketArgs {
        string question;
        string category;
        string resolutionSource;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint128 initialVolume;
        bool initialDirection;
        MarketDisplayInput display;
        ExternalMarketRefInput externalRef;
    }

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function createMarket(MarketCreationParams calldata params) external nonReentrant returns (bytes32 marketId) {
        marketId = _createMarket(_createMarketArgs(params));
    }

    function createMarket(
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint128 initialVolume,
        bool initialDirection
    ) external nonReentrant returns (bytes32 marketId) {
        marketId = _createMarket(
            CreateMarketArgs({
                question: question,
                category: category,
                resolutionSource: resolutionSource,
                tradingStartTime: tradingStartTime,
                expiryTime: expiryTime,
                initialVolume: initialVolume,
                initialDirection: initialDirection,
                display: LibMarketMetadata.emptyDisplayInput(),
                externalRef: LibMarketMetadata.emptyExternalRefInput()
            })
        );
    }

    function createMarketWithCollateralProfile(uint8 profileId, MarketCreationParams calldata params)
        external
        nonReentrant
        returns (bytes32 marketId)
    {
        marketId = _createProfileMarket(profileId, _createMarketArgs(params));
    }

    function createMarketWithCollateralProfile(
        uint8 profileId,
        string calldata question,
        string calldata category,
        string calldata resolutionSource,
        uint64 tradingStartTime,
        uint64 expiryTime,
        uint128 initialVolume,
        bool initialDirection
    ) external nonReentrant returns (bytes32 marketId) {
        marketId = _createProfileMarket(
            profileId,
            CreateMarketArgs({
                question: question,
                category: category,
                resolutionSource: resolutionSource,
                tradingStartTime: tradingStartTime,
                expiryTime: expiryTime,
                initialVolume: initialVolume,
                initialDirection: initialDirection,
                display: LibMarketMetadata.emptyDisplayInput(),
                externalRef: LibMarketMetadata.emptyExternalRefInput()
            })
        );
    }

    function createMarkets(MarketCreationParams[] calldata params)
        external
        nonReentrant
        returns (bytes32[] memory marketIds)
    {
        uint256 length = params.length;
        _requireMarketCreationBatchLength(LibEveMarket.store().config, length);

        marketIds = _createMarkets(params, length);
    }

    function _createMarkets(MarketCreationParams[] calldata params, uint256 length)
        internal
        returns (bytes32[] memory marketIds)
    {
        marketIds = new bytes32[](length);
        for (uint256 index = 0; index < length; ++index) {
            MarketCreationParams calldata input = params[index];
            marketIds[index] = _createMarket(_createMarketArgs(input));
        }
    }

    function _createMarketArgs(MarketCreationParams calldata input)
        internal
        pure
        returns (CreateMarketArgs memory args)
    {
        args = CreateMarketArgs({
            question: input.question,
            category: input.category,
            resolutionSource: input.resolutionSource,
            tradingStartTime: input.tradingStartTime,
            expiryTime: input.expiryTime,
            initialVolume: input.initialVolume,
            initialDirection: input.initialDirection,
            display: input.display,
            externalRef: input.externalRef
        });
    }

    function _requireMarketCreationBatchLength(LibEveMarket.MarketConfig storage config, uint256 length) internal view {
        if (length == 0 || length > config.marketCreationBatchCap) {
            revert Errors.InvalidAmount(length);
        }
    }

    function _createMarket(CreateMarketArgs memory args) internal returns (bytes32 marketId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibMarketCreation.CreationInput memory creation =
            LibMarketCreation.creationInputForCaller(state.config, args.tradingStartTime, args.expiryTime);

        marketId = LibMarketCreation.marketIdFor(
            args.question,
            args.category,
            args.tradingStartTime,
            args.expiryTime,
            state.config.collateralToken,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        if (state.markets[marketId].marketId != bytes32(0)) {
            revert Errors.MarketAlreadyExists(marketId);
        }

        LibMarketCreation.validateFunding(
            IERC20(state.config.collateralToken),
            IERC20(state.config.bondToken),
            msg.sender,
            creation.creationFee,
            creation.creationBond,
            args.initialVolume
        );

        LibEveMarket.Market storage market = _initializeMarket(state, marketId, args.question, args.category, creation);
        market.payoutUnit = DEFAULT_COLLATERAL_PAYOUT_UNIT;

        LibMarketMetadata.registerMarketMetadata(market, args.question, args.category, args.resolutionSource);
        bytes32 externalRefHash = LibMarketMetadata.registerMarketExternalReference(marketId, args.externalRef);
        LibMarketMetadata.registerMarketDisplayMetadata(marketId, args.display, externalRefHash);
        LibMarketCreation.collectCreationFee(
            state.config.collateralToken, state.config.eveTreasury, msg.sender, creation.creationFee
        );
        LibMarketCreation.collectCreationBond(state.config.bondToken, marketId, msg.sender, creation.creationBond);

        _emitMarketCreated(market, args.question);

        if (args.initialVolume > 0) {
            _seedInitialCurveAndEmit(
                state,
                market,
                state.config.collateralToken,
                creation.currentTimestamp,
                args.initialVolume,
                args.initialDirection
            );
        }
    }

    function _createProfileMarket(uint8 profileId, CreateMarketArgs memory args) internal returns (bytes32 marketId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.CollateralProfile storage profile = LibCollateralProfile.requireEnabled(state, profileId);
        LibMarketCreation.CreationInput memory creation = LibMarketCreation.profileCreationInputForCaller(
            state.config, profile.marketCreationFee, args.tradingStartTime, args.expiryTime
        );

        marketId = LibMarketCreation.profileMarketIdFor(
            args.question,
            args.category,
            args.tradingStartTime,
            args.expiryTime,
            profile.collateralToken,
            profileId,
            profile.payoutUnit,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        if (state.markets[marketId].marketId != bytes32(0)) {
            revert Errors.MarketAlreadyExists(marketId);
        }

        LibMarketCreation.validateFunding(
            IERC20(profile.collateralToken),
            IERC20(state.config.bondToken),
            msg.sender,
            creation.creationFee,
            creation.creationBond,
            args.initialVolume
        );

        LibEveMarket.Market storage market =
            _initializeProfileMarket(state, marketId, profileId, profile, args.question, args.category, creation);

        LibMarketMetadata.registerMarketMetadata(market, args.question, args.category, args.resolutionSource);
        bytes32 externalRefHash = LibMarketMetadata.registerMarketExternalReference(marketId, args.externalRef);
        LibMarketMetadata.registerMarketDisplayMetadata(marketId, args.display, externalRefHash);
        LibMarketCreation.collectCreationFee(
            profile.collateralToken, state.config.eveTreasury, msg.sender, creation.creationFee
        );
        LibMarketCreation.collectCreationBond(state.config.bondToken, marketId, msg.sender, creation.creationBond);

        _emitMarketCreated(market, args.question);
        emit Events.MarketCollateralProfile(
            market.marketId, profileId, profile.collateralToken, profile.payoutUnit, creation.creationFee
        );

        if (args.initialVolume > 0) {
            _seedInitialCurveAndEmit(
                state,
                market,
                profile.collateralToken,
                creation.currentTimestamp,
                args.initialVolume,
                args.initialDirection
            );
        }
    }

    function syncMarketState(bytes32 marketId) external returns (uint8 state_) {
        state_ = LibMarketMetadata.syncExpiredMarket(LibEveMarket.store().markets[marketId]);
    }

    function _initializeMarket(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        string memory question,
        string memory category,
        LibMarketCreation.CreationInput memory creation
    ) internal returns (LibEveMarket.Market storage market) {
        LibMarketCreation.CreationDetails memory details =
            LibMarketCreation.prepareCLOBCreationDetails(
                state.config.defaultConditionalTokens,
                state.config.collateralToken,
                question,
                category,
                creation.tradingStartTime,
                creation.expiryTime,
                marketId
            );

        market = state.markets[marketId];
        LibMarketCreation.storeMarket(
            market,
            marketId,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF,
            state.config.defaultConditionalTokens,
            state.config.collateralToken,
            msg.sender,
            details,
            creation
        );
        LibCLOBBook.setMarketBookIds(market);
    }

    function _initializeProfileMarket(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint8 profileId,
        LibEveMarket.CollateralProfile storage profile,
        string memory question,
        string memory category,
        LibMarketCreation.CreationInput memory creation
    ) internal returns (LibEveMarket.Market storage market) {
        LibMarketCreation.CreationDetails memory details =
            LibMarketCreation.prepareProfileCLOBCreationDetails(
                state.config.defaultConditionalTokens,
                profile.collateralToken,
                question,
                category,
                creation.tradingStartTime,
                creation.expiryTime
            );

        market = state.markets[marketId];
        LibMarketCreation.storeMarket(
            market,
            marketId,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF,
            state.config.defaultConditionalTokens,
            profile.collateralToken,
            msg.sender,
            details,
            creation
        );
        market.collateralProfileId = profileId;
        market.payoutUnit = profile.payoutUnit;
        LibCLOBBook.setMarketBookIds(market);
    }

    function _emitMarketCreated(LibEveMarket.Market storage market, string memory question) internal {
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

    function _seedInitialCurve(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        IERC20 collateralToken,
        uint64 currentTimestamp,
        uint128 initialVolume,
        bool initialDirection
    ) internal returns (uint256 curveId) {
        IGnosisConditionalTokens ctf = IGnosisConditionalTokens(market.positionToken);

        LibCTF.prepareMarketCondition(market.positionToken, market.resolutionId);
        collateralToken.safeTransferFrom(msg.sender, address(this), initialVolume);
        collateralToken.forceApprove(market.positionToken, initialVolume);
        ctf.splitPosition(collateralToken, bytes32(0), market.conditionId, LibCTF.binaryPartition(), initialVolume);
        collateralToken.forceApprove(market.positionToken, 0);

        uint256 quotedPositionId = initialDirection ? market.yesPositionId : market.noPositionId;
        uint256 oppositePositionId = initialDirection ? market.noPositionId : market.yesPositionId;
        LibEveMarket.Book storage book = LibCLOBBook.ensureMarketSideBook(state, market, initialDirection);

        ctf.safeTransferFrom(address(this), msg.sender, oppositePositionId, initialVolume, "");

        curveId = state.nextCurveId++;

        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.packed = LibCurvePacking.pack(
            FIFTY_FIFTY_PRICE,
            FIFTY_FIFTY_PRICE,
            _durationMinutesUntil(market.expiryTime, currentTimestamp),
            LINEAR_PROFILE_ID
        );
        curve.remainingVolume = initialVolume;
        curve.createdAt = currentTimestamp < market.tradingStartTime ? market.tradingStartTime : currentTimestamp;
        curve.generation = 1;
        curve.active = true;
        curve.isYesSide = initialDirection;
        curve.maker = msg.sender;
        curve.curveSide = LibEveMarket.CurveSide.ASK;
        curve.bookId = book.bookId;
        state.bookCurveIds[book.bookId].push(curveId);
        LibCurveIndex.registerCreatedCurve(state, curveId);

        market.curveCount += 1;
        book.curveCount += 1;

        // Keep the quoted side escrowed in the Diamond and return the opposite side to the creator.
        if (ctf.balanceOf(address(this), quotedPositionId) < initialVolume) {
            revert Errors.PositionIdMismatch(quotedPositionId, oppositePositionId);
        }
    }

    function _seedInitialCurveAndEmit(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        address collateralToken,
        uint64 currentTimestamp,
        uint128 initialVolume,
        bool initialDirection
    ) internal {
        uint256 curveId = _seedInitialCurve(
            state, market, IERC20(collateralToken), currentTimestamp, initialVolume, initialDirection
        );

        emit Events.CurvePosted(market.marketId, curveId, msg.sender, initialDirection, state.curves[curveId].packed);
        emit Events.BookCurvePosted(
            state.curves[curveId].bookId,
            market.marketId,
            curveId,
            msg.sender,
            initialDirection,
            uint8(LibEveMarket.CurveSide.ASK),
            state.curves[curveId].packed
        );
    }

    function _durationMinutesUntil(uint64 expiryTime, uint64 currentTimestamp)
        internal
        pure
        returns (uint24 minutesUntilExpiry)
    {
        uint256 secondsRemaining = uint256(expiryTime) - uint256(currentTimestamp);
        uint256 roundedMinutes = secondsRemaining / 60;

        if (secondsRemaining % 60 != 0) {
            roundedMinutes += 1;
        }
        if (roundedMinutes > type(uint24).max) {
            roundedMinutes = type(uint24).max;
        }

        minutesUntilExpiry = uint24(roundedMinutes);
    }
}
