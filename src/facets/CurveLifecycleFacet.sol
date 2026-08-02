// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {IEveUSDC} from "../interfaces/IEveUSDC.sol";
import {LibBookAccess} from "../libraries/LibBookAccess.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibCurveMath} from "../libraries/LibCurveMath.sol";
import {LibCurveLifecycle} from "../libraries/LibCurveLifecycle.sol";
import {LibCTF} from "../libraries/LibCTF.sol";
import {LibCurveEscrow} from "../libraries/LibCurveEscrow.sol";
import {LibEveUSDCUnits} from "../libraries/LibEveUSDCUnits.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibSafeCast} from "../libraries/LibSafeCast.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract CurveLifecycleFacet is CurveCLOBTypes {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    event BidCurvePostedWithUSDC(
        address indexed maker,
        bytes32 indexed marketId,
        bool isYesSide,
        uint256 curveId,
        uint128 usdcEscrowed,
        uint128 eveUsdcEscrowed
    );

    function postCurve(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        LibEveMarket.PositionTokenType positionTokenType
    ) external nonReentrant returns (uint256 curveId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, marketId);
        LibMarketAccess.requirePositionTokenType(market, positionTokenType);
        LibCLOBBook.ensureMarketSideBook(state, market, isYesSide);
        curveId = LibCurveLifecycle.postCurve(
            state,
            LibBookAccess.marketSideBookId(market, isYesSide),
            LibEveMarket.CurveSide.ASK,
            CurveCreationParams({
                isYesSide: isYesSide,
                volume: volume,
                startPrice: startPrice,
                endPrice: endPrice,
                durationMinutes: durationMinutes,
                profileId: profileId,
                tickPresetId: 0
            }),
            msg.sender
        );
    }

    function postBidCurve(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        LibEveMarket.PositionTokenType positionTokenType
    ) external nonReentrant returns (uint256 curveId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, marketId);
        LibMarketAccess.requirePositionTokenType(market, positionTokenType);
        LibCLOBBook.ensureMarketSideBook(state, market, isYesSide);
        curveId = LibCurveLifecycle.postCurve(
            state,
            LibBookAccess.marketSideBookId(market, isYesSide),
            LibEveMarket.CurveSide.BID,
            CurveCreationParams({
                isYesSide: isYesSide,
                volume: volume,
                startPrice: startPrice,
                endPrice: endPrice,
                durationMinutes: durationMinutes,
                profileId: profileId,
                tickPresetId: 0
            }),
            msg.sender
        );
    }

    function postBidCurveWithUSDC(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        LibEveMarket.PositionTokenType positionTokenType
    ) external nonReentrant returns (uint256 curveId, uint128 usdcEscrowed) {
        CurveCreationParams memory params = CurveCreationParams({
            isYesSide: isYesSide,
            volume: volume,
            startPrice: startPrice,
            endPrice: endPrice,
            durationMinutes: durationMinutes,
            profileId: profileId,
            tickPresetId: 0
        });
        (curveId, usdcEscrowed) = _postBidCurveWithUSDC(marketId, positionTokenType, params);
    }

    function _postBidCurveWithUSDC(
        bytes32 marketId,
        LibEveMarket.PositionTokenType positionTokenType,
        CurveCreationParams memory params
    ) internal returns (uint256 curveId, uint128 usdcEscrowed) {
        if (params.volume == 0) {
            revert Errors.InvalidAmount(params.volume);
        }
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, marketId);
        LibMarketAccess.requirePositionTokenType(market, positionTokenType);
        _requireDefaultCollateralForUSDCPath(state, market);
        LibCLOBBook.ensureMarketSideBook(state, market, params.isYesSide);

        bytes32 bookId = LibBookAccess.marketSideBookId(market, params.isYesSide);
        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, bookId);
        uint256 packed = LibCurveLifecycle.packCurve(
            state,
            book,
            params.startPrice,
            params.endPrice,
            params.durationMinutes,
            params.profileId,
            params.tickPresetId
        );
        LibCurveLifecycle.validatePackedCurve(state, bookId, packed);
        uint128 quoteEscrow = LibCurveMath.quoteEscrowRequiredForPacked(book, params.volume, packed);
        uint256 dust = LibEveUSDCUnits.eveUSDCDust(quoteEscrow);
        if (dust != 0) {
            revert Errors.InvalidAmount(dust);
        }

        usdcEscrowed = LibSafeCast.toUint128(quoteEscrow / LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE);
        _wrapUSDCForBidEscrow(market.collateralToken, usdcEscrowed, quoteEscrow);

        curveId = LibCurveLifecycle.storeWrappedBidCurve(state, bookId, msg.sender, params.volume, quoteEscrow, packed);

        emit BidCurvePostedWithUSDC(msg.sender, marketId, params.isYesSide, curveId, usdcEscrowed, quoteEscrow);
    }

    function _requireDefaultCollateralForUSDCPath(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market
    ) internal view {
        address expectedCollateral = state.config.collateralToken;
        if (market.collateralToken != expectedCollateral) {
            revert Errors.UnsupportedCollateralToken(expectedCollateral, market.collateralToken);
        }
    }

    function _wrapUSDCForBidEscrow(address eveUSDC, uint128 usdcEscrowed, uint128 quoteEscrow) internal {
        address usdc = IEveUSDC(eveUSDC).usdc();
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(address(this));
        uint256 eveUsdcBalanceBefore = IERC20(eveUSDC).balanceOf(address(this));

        if (usdcEscrowed != 0) {
            IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcEscrowed);
            IERC20(usdc).forceApprove(eveUSDC, usdcEscrowed);
            uint256 wrapped = IEveUSDC(eveUSDC).wrap(usdcEscrowed, address(this));
            IERC20(usdc).forceApprove(eveUSDC, 0);
            if (wrapped != quoteEscrow) {
                revert Errors.BaseTransferDeltaMismatch(eveUSDC, quoteEscrow, wrapped);
            }
        }

        uint256 eveUsdcBalanceAfter = IERC20(eveUSDC).balanceOf(address(this));
        if (eveUsdcBalanceAfter != eveUsdcBalanceBefore + quoteEscrow) {
            revert Errors.BaseTransferDeltaMismatch(eveUSDC, eveUsdcBalanceBefore + quoteEscrow, eveUsdcBalanceAfter);
        }
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(address(this));
        if (usdcBalanceAfter != usdcBalanceBefore) {
            revert Errors.BaseTransferDeltaMismatch(usdc, usdcBalanceBefore, usdcBalanceAfter);
        }
    }

    function postCurvesBatch(
        bytes32 marketId,
        LibEveMarket.PositionTokenType positionTokenType,
        CurveCreationParams[] calldata params
    ) external nonReentrant returns (uint256[] memory curveIds) {
        LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(LibEveMarket.store(), marketId);
        LibMarketAccess.requirePositionTokenType(market, positionTokenType);
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        _ensureMarketSideBooksForParams(state, market, params);
        curveIds =
            LibCurveLifecycle.postMarketCurvesBatch(state, market, LibEveMarket.CurveSide.ASK, params, msg.sender);
    }

    function postBidCurvesBatch(
        bytes32 marketId,
        LibEveMarket.PositionTokenType positionTokenType,
        CurveCreationParams[] calldata params
    ) external nonReentrant returns (uint256[] memory curveIds) {
        LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(LibEveMarket.store(), marketId);
        LibMarketAccess.requirePositionTokenType(market, positionTokenType);
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        _ensureMarketSideBooksForParams(state, market, params);
        curveIds =
            LibCurveLifecycle.postMarketCurvesBatch(state, market, LibEveMarket.CurveSide.BID, params, msg.sender);
    }

    function postCurvesMultiMarket(MarketCurvePostParams[] calldata batches)
        external
        nonReentrant
        returns (uint256[][] memory curveIds)
    {
        curveIds = _postCurvesMultiMarket(batches, LibEveMarket.CurveSide.ASK);
    }

    function postBidCurvesMultiMarket(MarketCurvePostParams[] calldata batches)
        external
        nonReentrant
        returns (uint256[][] memory curveIds)
    {
        curveIds = _postCurvesMultiMarket(batches, LibEveMarket.CurveSide.BID);
    }

    function _postCurvesMultiMarket(MarketCurvePostParams[] calldata batches, LibEveMarket.CurveSide curveSide)
        internal
        returns (uint256[][] memory curveIds)
    {
        uint256 length = batches.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        curveIds = new uint256[][](length);
        for (uint256 index = 0; index < length; ++index) {
            MarketCurvePostParams calldata batch = batches[index];
            LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, batch.marketId);
            LibMarketAccess.requirePositionTokenType(market, batch.positionTokenType);
            _ensureMarketSideBooksForParams(state, market, batch.params);
            curveIds[index] =
                LibCurveLifecycle.postMarketCurvesBatch(state, market, curveSide, batch.params, msg.sender);
        }
    }

    function _ensureMarketSideBooksForParams(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        CurveCreationParams[] calldata params
    ) internal {
        bool yesSideReady;
        bool noSideReady;
        uint256 length = params.length;

        for (uint256 index = 0; index < length; ++index) {
            if (params[index].isYesSide) {
                if (!yesSideReady) {
                    LibCLOBBook.ensureMarketSideBook(state, market, true);
                    yesSideReady = true;
                }
            } else if (!noSideReady) {
                LibCLOBBook.ensureMarketSideBook(state, market, false);
                noSideReady = true;
            }

            if (yesSideReady && noSideReady) {
                return;
            }
        }
    }

    function updateCurve(uint256 curveId, uint256 newPacked, uint32 expectedGeneration) external nonReentrant {
        LibCurveLifecycle.updateCurve(
            LibEveMarket.store(), curveId, newPacked, expectedGeneration, bytes32(0), false, false, msg.sender
        );
    }

    function updateCurvesBatch(CurveUpdateParams[] calldata params) external nonReentrant {
        _updateCurvesBatch(params, false);
    }

    function updateCurveFromNow(uint256 curveId, uint256 newPacked, uint32 expectedGeneration) external nonReentrant {
        LibCurveLifecycle.updateCurve(
            LibEveMarket.store(), curveId, newPacked, expectedGeneration, bytes32(0), false, true, msg.sender
        );
    }

    function updateCurvesFromNowBatch(CurveUpdateParams[] calldata params) external nonReentrant {
        _updateCurvesBatch(params, true);
    }

    function _updateCurvesBatch(CurveUpdateParams[] calldata params, bool resetStartTime) internal {
        uint256 length = params.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        bytes32 cachedMarketId;
        bool hasCachedMarket;

        for (uint256 index = 0; index < length; ++index) {
            (cachedMarketId, hasCachedMarket) = LibCurveLifecycle.updateCurve(
                state,
                params[index].curveId,
                params[index].newPacked,
                params[index].expectedGeneration,
                cachedMarketId,
                hasCachedMarket,
                resetStartTime,
                msg.sender
            );
        }
    }

    function topUpCurvesBatch(bytes32 marketId, CurveTopUpParams[] calldata params) external nonReentrant {
        uint256 length = params.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, marketId);

        (uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow) =
            LibCurveLifecycle.prepareCurveTopUpsBatch(state, marketId, params, msg.sender);

        IERC1155 positionToken = IERC1155(market.positionToken);
        LibCurveEscrow.escrowPostedInventory(
            positionToken, msg.sender, market.yesPositionId, LibSafeCast.toUint128(totalYesVolume)
        );
        LibCurveEscrow.escrowPostedInventory(
            positionToken, msg.sender, market.noPositionId, LibSafeCast.toUint128(totalNoVolume)
        );
        if (totalQuoteEscrow != 0) {
            LibCurveEscrow.transferExactERC20From(
                market.collateralToken, msg.sender, address(this), LibSafeCast.toUint128(totalQuoteEscrow)
            );
        }

        LibCurveLifecycle.applyCurveTopUpsBatch(state, marketId, params, msg.sender);
    }

    function topUpCurvesMultiMarket(MarketCurveTopUpParams[] calldata batches) external nonReentrant {
        uint256 length = batches.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();

        for (uint256 index = 0; index < length; ++index) {
            MarketCurveTopUpParams calldata batch = batches[index];
            uint256 batchLength = batch.params.length;
            if (batchLength == 0) {
                revert Errors.InvalidAmount(batchLength);
            }

            LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, batch.marketId);

            (uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow) =
                LibCurveLifecycle.prepareCurveTopUpsBatch(state, batch.marketId, batch.params, msg.sender);

            IERC1155 positionToken = IERC1155(market.positionToken);
            LibCurveEscrow.escrowPostedInventory(
                positionToken, msg.sender, market.yesPositionId, LibSafeCast.toUint128(totalYesVolume)
            );
            LibCurveEscrow.escrowPostedInventory(
                positionToken, msg.sender, market.noPositionId, LibSafeCast.toUint128(totalNoVolume)
            );
            if (totalQuoteEscrow != 0) {
                LibCurveEscrow.transferExactERC20From(
                    market.collateralToken, msg.sender, address(this), LibSafeCast.toUint128(totalQuoteEscrow)
                );
            }

            LibCurveLifecycle.applyCurveTopUpsBatch(state, batch.marketId, batch.params, msg.sender);
        }
    }

    function splitAndTopUpCurvesBatch(bytes32 marketId, CurveTopUpParams[] calldata params)
        external
        nonReentrant
        returns (uint128 sharesMinted)
    {
        uint256 length = params.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, marketId);
        LibMarketAccess.requirePositionTokenType(market, LibEveMarket.PositionTokenType.CTF);
        LibMarketAccess.validatePositionIds(market);

        (uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow) =
            LibCurveLifecycle.prepareCurveTopUpsBatch(state, marketId, params, msg.sender);
        if (totalQuoteEscrow != 0) {
            revert Errors.InvalidAmount(totalQuoteEscrow);
        }
        if (totalYesVolume != totalNoVolume) {
            revert Errors.CurveTopUpVolumeMismatch(totalYesVolume, totalNoVolume);
        }

        sharesMinted = LibSafeCast.toUint128(totalYesVolume);

        IERC20 collateralToken = IERC20(market.collateralToken);
        LibCTF.prepareMarketCondition(market.positionToken, market.resolutionId);
        collateralToken.safeTransferFrom(msg.sender, address(this), sharesMinted);
        collateralToken.forceApprove(market.positionToken, sharesMinted);

        LibCTF.splitCollateral(market.positionToken, market.collateralToken, market.conditionId, sharesMinted);

        LibCurveLifecycle.applyCurveTopUpsBatch(state, marketId, params, msg.sender);
    }

    function splitAndTopUpCurvesMultiMarket(MarketCurveTopUpParams[] calldata batches)
        external
        nonReentrant
        returns (uint128[] memory sharesMinted)
    {
        uint256 length = batches.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        sharesMinted = new uint128[](length);

        for (uint256 index = 0; index < length; ++index) {
            MarketCurveTopUpParams calldata batch = batches[index];
            uint256 batchLength = batch.params.length;
            if (batchLength == 0) {
                revert Errors.InvalidAmount(batchLength);
            }

            LibEveMarket.Market storage market = LibMarketAccess.requirePostableMarket(state, batch.marketId);
            LibMarketAccess.requirePositionTokenType(market, LibEveMarket.PositionTokenType.CTF);
            LibMarketAccess.validatePositionIds(market);

            (uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow) =
                LibCurveLifecycle.prepareCurveTopUpsBatch(state, batch.marketId, batch.params, msg.sender);
            if (totalQuoteEscrow != 0) {
                revert Errors.InvalidAmount(totalQuoteEscrow);
            }
            if (totalYesVolume != totalNoVolume) {
                revert Errors.CurveTopUpVolumeMismatch(totalYesVolume, totalNoVolume);
            }

            sharesMinted[index] = LibSafeCast.toUint128(totalYesVolume);

            IERC20 collateralToken = IERC20(market.collateralToken);
            LibCTF.prepareMarketCondition(market.positionToken, market.resolutionId);
            collateralToken.safeTransferFrom(msg.sender, address(this), sharesMinted[index]);
            collateralToken.forceApprove(market.positionToken, sharesMinted[index]);

            LibCTF.splitCollateral(
                market.positionToken, market.collateralToken, market.conditionId, sharesMinted[index]
            );

            LibCurveLifecycle.applyCurveTopUpsBatch(state, batch.marketId, batch.params, msg.sender);
        }
    }

    function cancelCurve(uint256 curveId) external nonReentrant {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibCurveLifecycle.CancelCache memory cache;
        LibCurveLifecycle.cancelCurve(state, curveId, msg.sender, cache);
    }

    function cancelCurvesBatch(uint256[] calldata curveIds) external nonReentrant {
        uint256 length = curveIds.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibCurveLifecycle.CancelCache memory cache;

        for (uint256 index = 0; index < length; ++index) {
            cache = LibCurveLifecycle.cancelCurve(state, curveIds[index], msg.sender, cache);
        }
    }
}
