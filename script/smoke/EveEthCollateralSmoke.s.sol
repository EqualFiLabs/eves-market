// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "../../lib/forge-std/src/console2.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DeployScript} from "../Deploy.s.sol";
import {EveUSDC} from "../../src/EveUSDC.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {IComboCoreFacet} from "../../src/interfaces/IComboCoreFacet.sol";
import {IComboSettlementFacet} from "../../src/interfaces/IComboSettlementFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMultiOutcomeOrderbookFacet} from "../../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {INativeBinaryPositionFacet} from "../../src/interfaces/INativeBinaryPositionFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {IParlayFacet} from "../../src/interfaces/IParlayFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {ParlayTypes} from "../../src/types/ParlayTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {MockUSDC} from "../../test/helpers/MockUSDC.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract EveEthCollateralSmoke is DeployScript {
    uint256 internal constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant DEFAULT_ANVIL_TAKER_PRIVATE_KEY =
        0x59c6995e998f97a5a0044976f76b6fdae9a4c9d54c638f5f6d5f2d3d2e1f9c62;

    uint72 internal constant HALF_PRICE = 500_000_000;
    uint128 internal constant USD_BINARY_AMOUNT = 1e18;
    uint128 internal constant USD_MULTI_INVENTORY = 2e18;
    uint128 internal constant USD_MULTI_QUOTE = 1e18;
    uint128 internal constant USD_PARIMUTUEL_ENTRY = 1e18;
    uint128 internal constant EVE_ETH_PAYOUT_UNIT = 0.0005 ether;
    uint128 internal constant EVE_ETH_BINARY_AMOUNT = 0.001 ether;
    uint128 internal constant EVE_ETH_MULTI_INVENTORY = 0.002 ether;
    uint128 internal constant EVE_ETH_MULTI_QUOTE = 0.001 ether;
    uint128 internal constant EVE_ETH_PARIMUTUEL_ENTRY = 0.001 ether;
    uint128 internal constant EVE_ETH_PARLAY_PREMIUM = 0.0001 ether;
    uint128 internal constant EVE_ETH_PARLAY_PAYOUT = 0.001 ether;
    uint128 internal constant EVE_ETH_PARLAY_FEE = 0.0002 ether;

    struct CreatedMarkets {
        bytes32 usdBinary;
        bytes32 ethBinaryA;
        bytes32 ethBinaryB;
        bytes32 usdParimutuel;
        bytes32 ethParimutuel;
        bytes32 usdMulti;
        bytes32 ethMulti;
    }

    struct BookAsk {
        bytes32 marketId;
        bytes32 bookId;
        uint256 positionId;
        uint256 curveId;
        uint128 quoteIn;
        uint128 sharesOut;
    }

    struct ComboAsk {
        bytes32 marketId;
        bytes32 conditionId;
        bytes32 bookId;
        uint256 positionId;
        uint256 curveId;
        uint128 sharesOut;
    }

    struct ParlayFlow {
        uint256 offerId;
        uint256 ticketId;
    }

    struct SmokeResult {
        address diamond;
        address eveUSDC;
        address eveETH;
        bytes32 usdBinary;
        bytes32 ethBinaryA;
        bytes32 ethBinaryB;
        bytes32 usdParimutuel;
        bytes32 ethParimutuel;
        bytes32 usdMulti;
        bytes32 ethMulti;
        bytes32 ethCombo;
        uint256 parlayOfferId;
        uint256 parlayTicketId;
        uint128 usdOutcomeShares;
        uint128 ethOutcomeShares;
        uint128 ethComboShares;
    }

    function smoke() external returns (SmokeResult memory result) {
        uint256 makerPrivateKey = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_PRIVATE_KEY);
        uint256 takerPrivateKey = vm.envOr("TAKER_PRIVATE_KEY", DEFAULT_ANVIL_TAKER_PRIVATE_KEY);
        address maker = vm.addr(makerPrivateKey);
        address taker = vm.addr(takerPrivateKey);
        require(maker != taker, "maker and taker must differ");

        CreatedMarkets memory markets;
        BookAsk memory usdOutcomeAsk;
        BookAsk memory ethOutcomeAsk;
        ComboAsk memory comboAsk;
        ParlayFlow memory parlay;
        FullDeployment memory deployment;

        vm.startBroadcast(makerPrivateKey);
        deployment = deployFullStack(_smokeConfig(maker), maker);
        _fundEveUSDC(deployment, maker, 200e6);
        _fundEveETH(deployment, maker, 0.05 ether);
        markets = _createMarkets(deployment.market.diamond);
        _smokeNativeBinarySplits(deployment, markets, maker);
        _buyParimutuelEntries(deployment, markets, maker);
        usdOutcomeAsk = _openOutcomeAsk(deployment, markets.usdMulti, 1, USD_MULTI_INVENTORY, USD_MULTI_QUOTE, maker);
        ethOutcomeAsk =
            _openOutcomeAsk(deployment, markets.ethMulti, 1, EVE_ETH_MULTI_INVENTORY, EVE_ETH_MULTI_QUOTE, maker);
        comboAsk = _openEveEthComboAsk(deployment, markets.ethBinaryA, markets.ethBinaryB, maker);
        _assertMixedComboRejected(deployment.market.diamond, markets.usdBinary, markets.ethBinaryA);
        parlay.offerId = _postMixedLegParlay(deployment.market.diamond, markets, maker);
        vm.stopBroadcast();

        vm.startBroadcast(takerPrivateKey);
        _fundEveUSDC(deployment, taker, 25e6);
        _fundEveETH(deployment, taker, 0.01 ether);
        usdOutcomeAsk.sharesOut = _fillBookAsk(deployment, usdOutcomeAsk, taker);
        ethOutcomeAsk.sharesOut = _fillBookAsk(deployment, ethOutcomeAsk, taker);
        comboAsk.sharesOut = _fillComboAsk(deployment, comboAsk, taker);
        parlay.ticketId = IParlayFacet(deployment.market.diamond).fillParlayOffer(parlay.offerId, 1, taker);
        vm.stopBroadcast();

        vm.startBroadcast(makerPrivateKey);
        _resolveYes(deployment.market.diamond, markets.usdBinary);
        _resolveYes(deployment.market.diamond, markets.ethBinaryA);
        _resolveYes(deployment.market.diamond, markets.ethBinaryB);
        _resolveYes(deployment.market.diamond, markets.usdParimutuel);
        _resolveYes(deployment.market.diamond, markets.ethParimutuel);
        _resolveConcrete(deployment.market.diamond, markets.usdMulti, 1);
        _resolveConcrete(deployment.market.diamond, markets.ethMulti, 1);
        _claimParimutuelPayouts(deployment, markets, maker);
        vm.stopBroadcast();

        vm.startBroadcast(takerPrivateKey);
        _redeemOutcomeAsk(deployment, usdOutcomeAsk, taker);
        _redeemOutcomeAsk(deployment, ethOutcomeAsk, taker);
        _redeemComboAsk(deployment, comboAsk, taker);
        require(
            IParlayFacet(deployment.market.diamond).finalizeParlayTicketBucket(parlay.ticketId)
                == EVE_ETH_PARLAY_PAYOUT,
            "bad parlay payout"
        );
        uint256 parlayBalanceBefore = IERC20(deployment.eveETH).balanceOf(taker);
        require(
            IParlayFacet(deployment.market.diamond).claimParlayTicket(parlay.ticketId, 1, taker)
                == EVE_ETH_PARLAY_PAYOUT,
            "bad parlay claim"
        );
        require(
            IERC20(deployment.eveETH).balanceOf(taker) == parlayBalanceBefore + EVE_ETH_PARLAY_PAYOUT,
            "parlay collateral mismatch"
        );
        vm.stopBroadcast();

        result = SmokeResult({
            diamond: deployment.market.diamond,
            eveUSDC: deployment.eveUSDC,
            eveETH: deployment.eveETH,
            usdBinary: markets.usdBinary,
            ethBinaryA: markets.ethBinaryA,
            ethBinaryB: markets.ethBinaryB,
            usdParimutuel: markets.usdParimutuel,
            ethParimutuel: markets.ethParimutuel,
            usdMulti: markets.usdMulti,
            ethMulti: markets.ethMulti,
            ethCombo: comboAsk.marketId,
            parlayOfferId: parlay.offerId,
            parlayTicketId: parlay.ticketId,
            usdOutcomeShares: usdOutcomeAsk.sharesOut,
            ethOutcomeShares: ethOutcomeAsk.sharesOut,
            ethComboShares: comboAsk.sharesOut
        });
        _logResult(result);
    }

    function _createMarkets(address diamond) internal returns (CreatedMarkets memory markets) {
        markets.usdBinary = _createBinaryMarket(diamond, 0, false);
        markets.ethBinaryA = _createBinaryMarket(diamond, 1, true);
        markets.ethBinaryB = _createBinaryMarket(diamond, 2, true);
        markets.usdParimutuel = _createParimutuelMarket(diamond, 0, false);
        markets.ethParimutuel = _createParimutuelMarket(diamond, 1, true);
        markets.usdMulti = _createMultiOutcomeMarket(diamond, 0, false);
        markets.ethMulti = _createMultiOutcomeMarket(diamond, 1, true);
    }

    function _smokeNativeBinarySplits(FullDeployment memory deployment, CreatedMarkets memory markets, address maker)
        internal
    {
        _splitAndMergeNativeBinary(deployment, markets.usdBinary, USD_BINARY_AMOUNT, maker);
        _splitAndMergeNativeBinary(deployment, markets.ethBinaryA, EVE_ETH_BINARY_AMOUNT, maker);
        _splitAndMergeNativeBinary(deployment, markets.ethBinaryB, EVE_ETH_BINARY_AMOUNT, maker);
    }

    function _splitAndMergeNativeBinary(
        FullDeployment memory deployment,
        bytes32 marketId,
        uint128 amount,
        address maker
    ) internal {
        address diamond = deployment.market.diamond;
        INativeBinaryPositionFacet.BinaryPositionIds memory ids =
            INativeBinaryPositionFacet(diamond).prepareNativeBinaryCondition(marketId);
        INativeBinaryPositionFacet(diamond).splitNativeBinary(marketId, amount, maker);

        EvesPositionManager positions = EvesPositionManager(deployment.market.evesPositionManager);
        require(positions.balanceOf(maker, ids.yesPositionId) == amount, "native yes split mismatch");
        require(positions.balanceOf(maker, ids.noPositionId) == amount, "native no split mismatch");
        positions.setApprovalForAll(diamond, true);
        require(
            INativeBinaryPositionFacet(diamond).mergeNativeBinary(marketId, amount, maker) == amount,
            "native merge mismatch"
        );
    }

    function _buyParimutuelEntries(FullDeployment memory deployment, CreatedMarkets memory markets, address maker)
        internal
    {
        address diamond = deployment.market.diamond;
        require(
            IParimutuelFacet(diamond).buyShares(markets.usdParimutuel, true, USD_PARIMUTUEL_ENTRY, maker, 1) != 0,
            "usd parimutuel entry failed"
        );
        require(
            IParimutuelFacet(diamond).buyShares(markets.ethParimutuel, true, EVE_ETH_PARIMUTUEL_ENTRY, maker, 1) != 0,
            "eveETH parimutuel entry failed"
        );
    }

    function _openOutcomeAsk(
        FullDeployment memory deployment,
        bytes32 marketId,
        uint8 outcome,
        uint128 makerInventory,
        uint128 quoteIn,
        address maker
    ) internal returns (BookAsk memory ask) {
        address diamond = deployment.market.diamond;
        IMultiOutcomeOrderbookFacet(diamond).splitOutcomeSet(marketId, makerInventory, maker);
        EvesPositionManager(deployment.market.evesPositionManager).setApprovalForAll(diamond, true);

        bytes32[] memory books = IMultiOutcomeOrderbookFacet(diamond).getMultiOutcomeBooks(marketId);
        ask = BookAsk({
            marketId: marketId,
            bookId: books[outcome],
            positionId: IMultiOutcomeOrderbookFacet(diamond).getOutcomePositionId(marketId, outcome),
            curveId: IBookOrderFacet(diamond)
                .postBookCurve(
                    books[outcome], LibEveMarket.CurveSide.ASK, makerInventory, HALF_PRICE, HALF_PRICE, 60, 0, 0
                ),
            quoteIn: quoteIn,
            sharesOut: 0
        });
    }

    function _openEveEthComboAsk(
        FullDeployment memory deployment,
        bytes32 firstMarketId,
        bytes32 secondMarketId,
        address maker
    ) internal returns (ComboAsk memory ask) {
        address diamond = deployment.market.diamond;
        IComboMarketFacet.ComboMarketPreparation memory preparation =
            IComboMarketFacet(diamond).createComboMarket(_pair(firstMarketId, secondMarketId), _yesLegs());
        IComboCoreFacet(diamond).splitCombo(preparation.conditionId, EVE_ETH_MULTI_INVENTORY, maker, maker);
        EvesPositionManager(deployment.market.evesPositionManager).setApprovalForAll(diamond, true);

        ask = ComboAsk({
            marketId: preparation.marketId,
            conditionId: preparation.conditionId,
            bookId: preparation.yesBookId,
            positionId: preparation.yesPositionId,
            curveId: IBookOrderFacet(diamond)
                .postBookCurve(
                    preparation.yesBookId,
                    LibEveMarket.CurveSide.ASK,
                    EVE_ETH_MULTI_INVENTORY,
                    HALF_PRICE,
                    HALF_PRICE,
                    60,
                    0,
                    0
                ),
            sharesOut: 0
        });
    }

    function _fillBookAsk(FullDeployment memory deployment, BookAsk memory ask, address taker)
        internal
        returns (uint128 sharesOut)
    {
        (uint32 generation, bytes32 commitment) =
            ICurveViewFacet(deployment.market.diamond).getCurveCommitment(ask.curveId);
        (uint128 previewShares,,,) =
            ICurveViewFacet(deployment.market.diamond).previewCurveQuote(ask.curveId, ask.quoteIn);
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(deployment.market.diamond)
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: ask.bookId,
                    maxQuoteIn: ask.quoteIn,
                    minBaseOut: previewShares,
                    maxAveragePrice: type(uint128).max,
                    curveIds: _singleCurveId(ask.curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    payer: taker,
                    receiver: taker
                })
            );
        sharesOut = result.sharesOut;
        require(sharesOut == previewShares, "outcome fill mismatch");
        require(
            EvesPositionManager(deployment.market.evesPositionManager).balanceOf(taker, ask.positionId) == sharesOut,
            "outcome balance mismatch"
        );
    }

    function _fillComboAsk(FullDeployment memory deployment, ComboAsk memory ask, address taker)
        internal
        returns (uint128 sharesOut)
    {
        (uint32 generation, bytes32 commitment) =
            ICurveViewFacet(deployment.market.diamond).getCurveCommitment(ask.curveId);
        (uint128 previewShares,,,) =
            ICurveViewFacet(deployment.market.diamond).previewCurveQuote(ask.curveId, EVE_ETH_MULTI_QUOTE);
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(deployment.market.diamond)
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: ask.bookId,
                    maxQuoteIn: EVE_ETH_MULTI_QUOTE,
                    minBaseOut: previewShares,
                    maxAveragePrice: type(uint128).max,
                    curveIds: _singleCurveId(ask.curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    payer: taker,
                    receiver: taker
                })
            );
        sharesOut = result.sharesOut;
        require(sharesOut == previewShares, "combo fill mismatch");
        require(
            EvesPositionManager(deployment.market.evesPositionManager).balanceOf(taker, ask.positionId) == sharesOut,
            "combo balance mismatch"
        );
    }

    function _redeemOutcomeAsk(FullDeployment memory deployment, BookAsk memory ask, address taker) internal {
        address collateral = IMarketFactoryFacet(deployment.market.diamond).getMarketInfo(ask.marketId).collateralToken;
        uint256 balanceBefore = IERC20(collateral).balanceOf(taker);
        require(
            IMultiOutcomeOrderbookFacet(deployment.market.diamond).redeemOutcome(ask.marketId, 1, ask.sharesOut, taker)
                == ask.sharesOut,
            "outcome redeem mismatch"
        );
        require(IERC20(collateral).balanceOf(taker) == balanceBefore + ask.sharesOut, "outcome collateral mismatch");
    }

    function _redeemComboAsk(FullDeployment memory deployment, ComboAsk memory ask, address taker) internal {
        uint256 balanceBefore = IERC20(deployment.eveETH).balanceOf(taker);
        require(
            IComboSettlementFacet(deployment.market.diamond).redeemCombo(ask.positionId, ask.sharesOut, taker)
                == ask.sharesOut,
            "combo redeem mismatch"
        );
        require(
            IERC20(deployment.eveETH).balanceOf(taker) == balanceBefore + ask.sharesOut, "combo collateral mismatch"
        );
    }

    function _claimParimutuelPayouts(FullDeployment memory deployment, CreatedMarkets memory markets, address maker)
        internal
    {
        uint256 usdBefore = IERC20(deployment.eveUSDC).balanceOf(maker);
        uint128 usdPayout = IParimutuelFacet(deployment.market.diamond).claimPayout(markets.usdParimutuel);
        require(usdPayout != 0, "missing usd parimutuel payout");
        require(IERC20(deployment.eveUSDC).balanceOf(maker) == usdBefore + usdPayout, "bad usd parimutuel payout");

        uint256 ethBefore = IERC20(deployment.eveETH).balanceOf(maker);
        uint128 ethPayout = IParimutuelFacet(deployment.market.diamond).claimPayout(markets.ethParimutuel);
        require(ethPayout != 0, "missing eveETH parimutuel payout");
        require(IERC20(deployment.eveETH).balanceOf(maker) == ethBefore + ethPayout, "bad eveETH parimutuel payout");
    }

    function _postMixedLegParlay(address diamond, CreatedMarkets memory markets, address maker)
        internal
        returns (uint256 offerId)
    {
        ParlayTypes.ParlayLeg[] memory legs =
            _sortedLegs(markets.usdBinary, 1, markets.ethParimutuel, 1, markets.ethMulti, 1);
        ParlayTypes.PayoutTier[] memory tiers = new ParlayTypes.PayoutTier[](1);
        tiers[0] = ParlayTypes.PayoutTier({minHits: 3, payout: EVE_ETH_PARLAY_PAYOUT});

        offerId = IParlayFacet(diamond)
            .postParlayOfferWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                ParlayTypes.QuoteOfferPost({
                    legs: legs,
                    payoutTiers: tiers,
                    invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                    metadataHint: "ipfs://eveeth-smoke-mixed-leg-parlay",
                    premiumPerUnit: EVE_ETH_PARLAY_PREMIUM,
                    maxPayoutPerUnit: EVE_ETH_PARLAY_PAYOUT,
                    units: 1,
                    fillDeadline: uint64(block.timestamp + 1 days)
                })
            );
        ParlayTypes.ParlayOfferView memory offer = IParlayFacet(diamond).getParlayOffer(offerId);
        require(offer.maker == maker, "bad parlay maker");
        require(offer.collateralProfileId == EVE_ETH_PROFILE_ID, "bad parlay profile");
        require(offer.escrowRemaining == EVE_ETH_PARLAY_PAYOUT, "bad parlay escrow");
    }

    function _assertMixedComboRejected(address diamond, bytes32 usdMarketId, bytes32 ethMarketId) internal {
        try IComboMarketFacet(diamond).createComboMarket(_pair(usdMarketId, ethMarketId), _yesLegs()) {
            revert("mixed combo allowed");
        } catch {}
    }

    function _createBinaryMarket(address diamond, uint256 index, bool useEveEth) internal returns (bytes32 marketId) {
        if (useEveEth) {
            return IMarketFactoryFacet(diamond)
                .createMarketWithCollateralProfile(
                    EVE_ETH_PROFILE_ID,
                    string.concat("eveETH binary smoke ", _u2s(index)),
                    "smoke",
                    "Local smoke source; creator finalizes the market.",
                    uint64(block.timestamp),
                    uint64(block.timestamp + 7 days + index),
                    0,
                    true
                );
        }

        marketId = IMarketFactoryFacet(diamond)
            .createMarket(
                string.concat("eveUSDC binary smoke ", _u2s(index)),
                "smoke",
                "Local smoke source; creator finalizes the market.",
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days + index),
                0,
                true
            );
    }

    function _createParimutuelMarket(address diamond, uint256 index, bool useEveEth)
        internal
        returns (bytes32 marketId)
    {
        if (useEveEth) {
            return IParimutuelFacet(diamond)
                .createParimutuelMarketWithCollateralProfile(
                    EVE_ETH_PROFILE_ID,
                    string.concat("eveETH parimutuel smoke ", _u2s(index)),
                    "smoke",
                    "Local smoke source; creator finalizes the pool.",
                    uint64(block.timestamp),
                    uint64(block.timestamp + 7 days + index),
                    1 hours
                );
        }

        marketId = IParimutuelFacet(diamond)
            .createParimutuelMarket(
                string.concat("eveUSDC parimutuel smoke ", _u2s(index)),
                "smoke",
                "Local smoke source; creator finalizes the pool.",
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days + index),
                1 hours
            );
    }

    function _createMultiOutcomeMarket(address diamond, uint256 index, bool useEveEth)
        internal
        returns (bytes32 marketId)
    {
        IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams memory params =
            IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                question: string.concat(useEveEth ? "eveETH" : "eveUSDC", " multi-outcome smoke ", _u2s(index)),
                category: "smoke",
                resolutionSource: "Local smoke source; creator finalizes outcome B.",
                tradingStartTime: uint64(block.timestamp),
                expiryTime: uint64(block.timestamp + 7 days + index),
                outcomes: _outcomes(),
                display: _emptyMultiOutcomeDisplay(),
                externalRef: _emptyMultiOutcomeExternalRef(),
                outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
            });
        if (useEveEth) {
            return IMultiOutcomeOrderbookFacet(diamond)
                .createMultiOutcomeMarketWithCollateralProfile(EVE_ETH_PROFILE_ID, params);
        }

        marketId = IMultiOutcomeOrderbookFacet(diamond).createMultiOutcomeMarket(params);
    }

    function _emptyMultiOutcomeDisplay() internal pure returns (MarketFactoryTypes.MarketDisplayInput memory display) {}

    function _emptyMultiOutcomeExternalRef()
        internal
        pure
        returns (MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
    {}

    function _resolveYes(address diamond, bytes32 marketId) internal {
        IOBRResolutionFacet(diamond).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        vm.warp(block.timestamp + 2);
        IOBRResolutionFacet(diamond).finalizeResolution(marketId);
    }

    function _resolveConcrete(address diamond, bytes32 marketId, uint8 outcome) internal {
        IOBRResolutionFacet(diamond).settleMarketEarly(marketId, outcome);
        vm.warp(block.timestamp + 2);
        IOBRResolutionFacet(diamond).finalizeResolution(marketId);
    }

    function _fundEveUSDC(FullDeployment memory deployment, address account, uint256 usdcAmount) internal {
        MockUSDC(deployment.usdcToken).mint(account, usdcAmount);
        IERC20(deployment.usdcToken).approve(deployment.eveUSDC, usdcAmount);
        EveUSDC(deployment.eveUSDC).wrap(usdcAmount, account);
        IERC20(deployment.eveUSDC).approve(deployment.market.diamond, type(uint256).max);
    }

    function _fundEveETH(FullDeployment memory deployment, address account, uint256 amount) internal {
        if (account.balance < amount) {
            vm.deal(account, amount);
        }
        CanonicalWETH9(payable(deployment.wethToken)).deposit{value: amount}();
        IERC20(deployment.wethToken).approve(deployment.eveETH, amount);
        EveETHLike(deployment.eveETH).wrap(amount, account);
        IERC20(deployment.eveETH).approve(deployment.market.diamond, type(uint256).max);
    }

    function _smokeConfig(address owner) internal pure returns (FullDeploymentConfig memory c) {
        c.market.owner = owner;
        c.market.eveTreasury = owner;
        c.market.parlayFeeRecipient = owner;
        c.market.parlayUnderwritingFee = 0;
        c.market.parlayVaultFeeBps = 0;
        c.market.parlayFeeRecipientBps = 10_000;
        c.market.orderbookEntryFeeBps = 0;
        c.market.orderbookMakerFeeBps = 10_000;
        c.market.orderbookCreatorFeeBps = 0;
        c.market.orderbookProtocolFeeBps = 0;
        c.market.orderbookVaultFeeBps = 0;
        c.market.spotTradeFeeBps = 0;
        c.market.spotMakerFeeBps = 10_000;
        c.market.spotProtocolFeeBps = 0;
        c.market.spotVaultFeeBps = 0;
        c.market.comboTradeFeeBps = 0;
        c.market.comboMakerFeeBps = 10_000;
        c.market.comboCreatorFeeBps = 0;
        c.market.comboProtocolFeeBps = 0;
        c.market.comboVaultFeeBps = 0;
        c.market.parimutuelEntryFeeBps = 0;
        c.market.parimutuelCreatorFeeBps = 0;
        c.market.parimutuelProtocolFeeBps = 10_000;
        c.market.parimutuelVaultFeeBps = 0;
        c.market.parimutuelMinEntry = USD_PARIMUTUEL_ENTRY;
        c.market.parimutuelEpochWindowCap = 30 days;
        c.market.marketCreationBatchCap = 30;
        c.market.parimutuelCreationSeedAmount = 0;
        c.market.marketCreationFee = 0;
        c.market.spotBookCreationFee = 0;
        c.market.comboMarketCreationFee = 0;
        c.market.marketCreationBond = 0;
        c.market.bondToken = c.market.eveToken;
        c.market.resolutionBondL1 = 0;
        c.market.resolutionBondL2 = 0;
        c.market.minMarketDuration = 60;
        c.market.maxMarketDuration = 365 days;
        c.market.disputeWindow = 1;
        c.market.creatorSettleGrace = 1 hours;
        c.market.openResolutionTimeout = 1 hours;
        c.market.maxEscalation = 2;
        c.market.permissionlessCreationEnabled = true;

        c.aumFeeBps = 0;
        c.lendingMaxLtvBps = 9_500;
        c.lendingOriginationFeeBps = 0;
        c.lendingExtensionFeeBps = 0;
        c.lendingFeeRecipientBps = 0;
        c.lendingMinDurationSeconds = uint32(5 minutes);
        c.lendingMaxDurationSeconds = uint32(365 days);
        c.lendingGracePeriodSeconds = uint32(12 hours);
        c.initialUsdcMint = 0;
        c.initialEveMint = 1_000_000e18;
        c.faucetOwner = owner;
        c.wethToken = address(0);
        c.eveETH = address(0);
        c.eveEthPayoutUnit = EVE_ETH_PAYOUT_UNIT;
        c.eveEthMarketCreationFee = 0;
        c.eveEthParimutuelCreationSeedAmount = 0.0003 ether;
        c.eveEthParimutuelMinEntry = 0.0001 ether;
        c.eveEthParlayUnderwritingFee = EVE_ETH_PARLAY_FEE;
        c.faucetUsdcEnabled = true;
        c.faucetEveEnabled = true;
        c.deployMockWeth = true;
        c.deployEveETH = true;
        c.enableEveEthMarkets = true;
        c.faucetUsdcClaimAmount = 1_000e6;
        c.faucetEveClaimAmount = 10_000e18;
        c.faucetUsdcFundAmount = 0;
        c.faucetEveFundAmount = 0;
    }

    function _sortedLegs(bytes32 a, uint8 aOutcome, bytes32 b, uint8 bOutcome, bytes32 c, uint8 cOutcome)
        internal
        pure
        returns (ParlayTypes.ParlayLeg[] memory legs)
    {
        legs = new ParlayTypes.ParlayLeg[](3);
        legs[0] = ParlayTypes.ParlayLeg({marketId: a, requiredOutcome: aOutcome});
        legs[1] = ParlayTypes.ParlayLeg({marketId: b, requiredOutcome: bOutcome});
        legs[2] = ParlayTypes.ParlayLeg({marketId: c, requiredOutcome: cOutcome});
        for (uint256 outer; outer < legs.length; ++outer) {
            for (uint256 inner = outer + 1; inner < legs.length; ++inner) {
                if (uint256(legs[inner].marketId) < uint256(legs[outer].marketId)) {
                    ParlayTypes.ParlayLeg memory tmp = legs[outer];
                    legs[outer] = legs[inner];
                    legs[inner] = tmp;
                }
            }
        }
    }

    function _pair(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](2);
        values[0] = first;
        values[1] = second;
    }

    function _yesLegs() internal pure returns (bool[] memory values) {
        values = new bool[](2);
        values[0] = true;
        values[1] = true;
    }

    function _outcomes() internal pure returns (string[] memory outcomes) {
        outcomes = new string[](3);
        outcomes[0] = "A";
        outcomes[1] = "B";
        outcomes[2] = "C";
    }

    function _singleCurveId(uint256 curveId) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = curveId;
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory values) {
        values = new uint32[](1);
        values[0] = generation;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = commitment;
    }

    function _logResult(SmokeResult memory result) internal pure {
        console2.log("eveETH collateral smoke passed");
        console2.log("diamond", result.diamond);
        console2.log("eveUSDC", result.eveUSDC);
        console2.log("eveETH", result.eveETH);
        console2.log("usdBinary");
        console2.logBytes32(result.usdBinary);
        console2.log("ethBinaryA");
        console2.logBytes32(result.ethBinaryA);
        console2.log("ethBinaryB");
        console2.logBytes32(result.ethBinaryB);
        console2.log("usdParimutuel");
        console2.logBytes32(result.usdParimutuel);
        console2.log("ethParimutuel");
        console2.logBytes32(result.ethParimutuel);
        console2.log("usdMulti");
        console2.logBytes32(result.usdMulti);
        console2.log("ethMulti");
        console2.logBytes32(result.ethMulti);
        console2.log("ethCombo");
        console2.logBytes32(result.ethCombo);
        console2.log("parlayOfferId", result.parlayOfferId);
        console2.log("parlayTicketId", result.parlayTicketId);
        console2.log("usdOutcomeShares", result.usdOutcomeShares);
        console2.log("ethOutcomeShares", result.ethOutcomeShares);
        console2.log("ethComboShares", result.ethComboShares);
    }

    function _u2s(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        bytes memory buffer = new bytes(78);
        uint256 length;
        while (value != 0) {
            buffer[length++] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        bytes memory output = new bytes(length);
        for (uint256 index; index < length; ++index) {
            output[index] = buffer[length - 1 - index];
        }
        return string(output);
    }
}

interface EveETHLike {
    function wrap(uint256 amount, address to) external returns (uint256 eveETHMinted);
}
