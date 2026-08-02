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
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibMarketCreation} from "../libraries/LibMarketCreation.sol";
import {LibMarketMetadata} from "../libraries/LibMarketMetadata.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

contract MarketFactoryFacet is MarketFactoryTypes {
    using SafeERC20 for IERC20;

    uint128 internal constant DEFAULT_EVEUSDC_PAYOUT_UNIT = 1 ether;
    uint72 internal constant FIFTY_FIFTY_PRICE = 500_000_000;
    uint8 internal constant LINEAR_PROFILE_ID = 0;
    uint256 internal constant MAX_GROUP_TITLE_BYTES = 512;

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

    function createMarketGroup(MarketGroupCreationParams calldata params)
        external
        nonReentrant
        returns (bytes32 groupId, bytes32[] memory marketIds)
    {
        uint256 length = params.markets.length;
        _requireMarketCreationBatchLength(LibEveMarket.store().config, length);
        _requireGroupTitle(params.display.title);

        marketIds = _createGroupMarkets(params.markets, length);
        bytes32 titleHash = keccak256(bytes(params.display.title));
        groupId = keccak256(abi.encodePacked("EVE_MARKET_GROUP", msg.sender, titleHash, marketIds[0], length));

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibMarketMetadata.registerMarketGroup(groupId, msg.sender, params.display);
        state.marketGroupMarketIds[groupId] = marketIds;
        LibMarketMetadata.registerMarketExternalReference(groupId, params.display.externalRef);

        emit Events.MarketGroupCreated(groupId, msg.sender, titleHash, params.display.title, length);
        for (uint256 index = 0; index < length; ++index) {
            emit Events.MarketGroupMarketAdded(groupId, marketIds[index], index);
            LibMarketMetadata.registerGroupMarketDisplay(
                groupId, marketIds[index], _checkedSortOrder(index), params.markets[index].display
            );
        }
    }

    function createMarketGroup(string calldata title, MarketCreationParams[] calldata params)
        external
        nonReentrant
        returns (bytes32 groupId, bytes32[] memory marketIds)
    {
        uint256 length = params.length;
        _requireMarketCreationBatchLength(LibEveMarket.store().config, length);
        _requireGroupTitle(title);

        marketIds = _createMarkets(params, length);
        bytes32 titleHash = keccak256(bytes(title));
        groupId = keccak256(abi.encodePacked("EVE_MARKET_GROUP", msg.sender, titleHash, marketIds[0], length));

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        MarketGroupCreationParams memory groupParams;
        groupParams.display.title = title;
        LibMarketMetadata.registerMarketGroup(groupId, msg.sender, groupParams.display);
        state.marketGroupMarketIds[groupId] = marketIds;

        emit Events.MarketGroupCreated(groupId, msg.sender, titleHash, title, length);
        for (uint256 index = 0; index < length; ++index) {
            emit Events.MarketGroupMarketAdded(groupId, marketIds[index], index);
            LibMarketMetadata.registerGroupMarketDisplay(
                groupId, marketIds[index], _checkedSortOrder(index), LibMarketMetadata.emptyGroupMarketDisplayInput()
            );
        }
    }

    function createMarketGroupFromExisting(ExistingMarketGroupCreationParams calldata params)
        external
        nonReentrant
        returns (bytes32 groupId)
    {
        uint256 length = params.markets.length;
        _requireMarketCreationBatchLength(LibEveMarket.store().config, length);
        _requireGroupTitle(params.display.title);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        bytes32[] memory marketIds = _existingGroupMarketIds(state, params.markets, msg.sender, bytes32(0));
        groupId = _existingMarketGroupId(msg.sender, params.display, marketIds);
        if (state.marketGroups[groupId].exists) {
            revert Errors.MarketGroupAlreadyExists(groupId);
        }

        bytes32 titleHash = keccak256(bytes(params.display.title));
        LibMarketMetadata.registerMarketGroup(groupId, msg.sender, params.display);
        LibMarketMetadata.registerMarketExternalReference(groupId, params.display.externalRef);
        emit Events.MarketGroupCreated(groupId, msg.sender, titleHash, params.display.title, length);

        _appendExistingMarketsToGroup(state, groupId, params.markets, marketIds, 0);
    }

    function addMarketsToGroup(bytes32 groupId, ExistingGroupMarketParam[] calldata markets) external nonReentrant {
        uint256 length = markets.length;
        _requireMarketCreationBatchLength(LibEveMarket.store().config, length);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MarketGroupMetadata storage group = state.marketGroups[groupId];
        if (!group.exists) {
            revert Errors.MarketGroupNotFound(groupId);
        }
        if (group.creator != msg.sender) {
            revert Errors.NotMarketCreator(msg.sender, group.creator);
        }

        uint256 startIndex = state.marketGroupMarketIds[groupId].length;
        bytes32[] memory marketIds = _existingGroupMarketIds(state, markets, msg.sender, groupId);
        _appendExistingMarketsToGroup(state, groupId, markets, marketIds, startIndex);
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

    function _createGroupMarkets(GroupMarketCreationParam[] calldata params, uint256 length)
        internal
        returns (bytes32[] memory marketIds)
    {
        marketIds = new bytes32[](length);
        for (uint256 index = 0; index < length; ++index) {
            marketIds[index] = _createMarket(_createMarketArgs(params[index].market));
        }
    }

    function _existingGroupMarketIds(
        LibEveMarket.EveMarketStorage storage state,
        ExistingGroupMarketParam[] calldata params,
        address creator,
        bytes32 groupId
    ) internal view returns (bytes32[] memory marketIds) {
        uint256 length = params.length;
        marketIds = new bytes32[](length);
        for (uint256 index = 0; index < length; ++index) {
            bytes32 marketId = params[index].marketId;
            _requireExistingGroupMarket(state, groupId, marketId, creator);
            for (uint256 previous = 0; previous < index; ++previous) {
                if (marketIds[previous] == marketId) {
                    revert Errors.DuplicateGroupMarket(groupId, marketId);
                }
            }
            marketIds[index] = marketId;
        }
    }

    function _requireExistingGroupMarket(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 groupId,
        bytes32 marketId,
        address creator
    ) internal view {
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId == bytes32(0)) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.creator != creator) {
            revert Errors.NotMarketCreator(creator, market.creator);
        }
        if (groupId != bytes32(0) && state.groupMarketDisplays[groupId][marketId].exists) {
            revert Errors.DuplicateGroupMarket(groupId, marketId);
        }
    }

    function _appendExistingMarketsToGroup(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 groupId,
        ExistingGroupMarketParam[] calldata params,
        bytes32[] memory marketIds,
        uint256 startIndex
    ) internal {
        for (uint256 index = 0; index < marketIds.length; ++index) {
            state.marketGroupMarketIds[groupId].push(marketIds[index]);
            uint256 sortOrder = startIndex + index;
            emit Events.MarketGroupMarketAdded(groupId, marketIds[index], sortOrder);
            LibMarketMetadata.registerGroupMarketDisplay(
                groupId, marketIds[index], _checkedSortOrder(sortOrder), params[index].display
            );
        }
    }

    function _existingMarketGroupId(address creator, GroupDisplayInput calldata display, bytes32[] memory marketIds)
        internal
        pure
        returns (bytes32 groupId)
    {
        groupId = keccak256(
            abi.encode(
                "EVE_EXISTING_MARKET_GROUP",
                creator,
                keccak256(bytes(display.title)),
                display.externalRef.snapshotHash,
                keccak256(abi.encode(marketIds))
            )
        );
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

    function _requireGroupTitle(string calldata title) internal pure {
        uint256 titleLength = bytes(title).length;
        if (titleLength == 0 || titleLength > MAX_GROUP_TITLE_BYTES) {
            revert Errors.InvalidAmount(titleLength);
        }
    }

    function _requireMarketCreationBatchLength(LibEveMarket.MarketConfig storage config, uint256 length) internal view {
        if (length == 0 || length > config.marketCreationBatchCap) {
            revert Errors.InvalidAmount(length);
        }
    }

    function _checkedSortOrder(uint256 index) internal pure returns (uint16 sortOrder) {
        if (index > type(uint16).max) {
            revert Errors.InvalidAmount(index);
        }
        sortOrder = uint16(index);
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
        market.payoutUnit = DEFAULT_EVEUSDC_PAYOUT_UNIT;

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
