// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "../../lib/forge-std/src/console2.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DeployScript} from "../Deploy.s.sol";
import {EveUSDC} from "../../src/EveUSDC.sol";
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
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {INativeBinaryPositionFacet} from "../../src/interfaces/INativeBinaryPositionFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {MockUSDC} from "../../test/helpers/MockUSDC.sol";

contract NativeComboSmoke is DeployScript {
    uint256 internal constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant DEFAULT_ANVIL_TAKER_PRIVATE_KEY =
        0x59c6995e998f97a5a0044976f76b6fdae9a4c9d54c638f5f6d5f2d3d2e1f9c62;

    uint128 internal constant BINARY_SMOKE_AMOUNT = 1e18;
    uint128 internal constant COMBO_SPLIT_AMOUNT = 14e18;
    uint128 internal constant ASK_AMOUNT = 10e18;
    uint128 internal constant BID_AMOUNT = 4e18;
    uint128 internal constant FINAL_COMBO_AMOUNT = ASK_AMOUNT - BID_AMOUNT;
    uint128 internal constant GAS_SPLIT_AMOUNT = 1e18;
    uint72 internal constant HALF_PRICE = 500_000_000;

    struct SmokeResult {
        address diamond;
        address eveUSDC;
        address evesPositionManager;
        address maker;
        address taker;
        bytes32 marketA;
        bytes32 marketB;
        bytes32 marketC;
        bytes32 comboConditionId;
        uint256 comboYes;
        uint256 comboNo;
        uint256 reducedComboYes;
        bytes32 yesBookId;
        bytes32 noBookId;
        uint256 askCurveId;
        uint256 bidCurveId;
        uint128 collateralOut;
        uint256 prepareTenLegGas;
        uint256 splitTenLegGas;
        uint256 prepareFiftyLegGas;
        uint256 splitFiftyLegGas;
    }

    function smoke() external returns (SmokeResult memory result) {
        uint256 makerPrivateKey = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_PRIVATE_KEY);
        uint256 takerPrivateKey = vm.envOr("TAKER_PRIVATE_KEY", DEFAULT_ANVIL_TAKER_PRIVATE_KEY);
        address maker = vm.addr(makerPrivateKey);
        address taker = vm.addr(takerPrivateKey);
        require(maker != taker, "maker and taker must differ");

        vm.startBroadcast(makerPrivateKey);
        FullDeployment memory deployment = deployFullStack(_smokeConfig(maker), maker);
        _fundAndApprove(deployment, maker, 100e6);
        result = _openComboAsk(deployment, maker, taker);
        _measureComboGas(deployment, result, maker);
        vm.stopBroadcast();

        vm.startBroadcast(takerPrivateKey);
        _fundAndApprove(deployment, taker, 25e6);
        _fillComboAsk(deployment, result, taker);
        vm.stopBroadcast();

        vm.startBroadcast(makerPrivateKey);
        _resolveYes(deployment.market.diamond, result.marketA);
        vm.stopBroadcast();

        vm.startBroadcast(takerPrivateKey);
        result.reducedComboYes = _compressCombo(deployment, result, taker);
        vm.stopBroadcast();

        vm.startBroadcast(makerPrivateKey);
        _resolveYes(deployment.market.diamond, result.marketB);
        _resolveYes(deployment.market.diamond, result.marketC);
        vm.stopBroadcast();

        vm.startBroadcast(takerPrivateKey);
        result.collateralOut = _redeemCombo(deployment, result, taker);
        vm.stopBroadcast();

        _logResult(result);
    }

    function _openComboAsk(FullDeployment memory deployment, address maker, address taker)
        internal
        returns (SmokeResult memory result)
    {
        address diamond = deployment.market.diamond;
        result.diamond = diamond;
        result.eveUSDC = deployment.eveUSDC;
        result.evesPositionManager = deployment.market.evesPositionManager;
        result.maker = maker;
        result.taker = taker;

        result.marketA = _createSmokeMarket(diamond, 0, 2 days);
        result.marketB = _createSmokeMarket(diamond, 1, 3 days);
        result.marketC = _createSmokeMarket(diamond, 2, 4 days);

        INativeBinaryPositionFacet.BinaryPositionIds memory legA =
            INativeBinaryPositionFacet(diamond).prepareNativeBinaryCondition(result.marketA);
        INativeBinaryPositionFacet.BinaryPositionIds memory legB =
            INativeBinaryPositionFacet(diamond).prepareNativeBinaryCondition(result.marketB);
        INativeBinaryPositionFacet.BinaryPositionIds memory legC =
            INativeBinaryPositionFacet(diamond).prepareNativeBinaryCondition(result.marketC);

        _smokeNativeBinarySplitMerge(deployment, maker, result.marketA, legA);

        bytes32[] memory comboMarkets = new bytes32[](3);
        comboMarkets[0] = result.marketA;
        comboMarkets[1] = result.marketB;
        comboMarkets[2] = result.marketC;
        bool[] memory comboYesLegs = new bool[](3);
        comboYesLegs[0] = true;
        comboYesLegs[1] = true;
        comboYesLegs[2] = true;
        IComboMarketFacet.ComboMarketPreparation memory comboMarket =
            IComboMarketFacet(diamond).createComboMarket(comboMarkets, comboYesLegs);
        result.comboConditionId = comboMarket.conditionId;
        result.comboYes = comboMarket.yesPositionId;
        result.comboNo = comboMarket.noPositionId;
        result.yesBookId = comboMarket.yesBookId;
        result.noBookId = comboMarket.noBookId;
        IComboCoreFacet(diamond).splitCombo(result.comboConditionId, COMBO_SPLIT_AMOUNT, maker, maker);

        EvesPositionManager positions = EvesPositionManager(deployment.market.evesPositionManager);
        require(positions.balanceOf(maker, result.comboYes) == COMBO_SPLIT_AMOUNT, "maker combo balance mismatch");
        positions.setApprovalForAll(diamond, true);

        result.askCurveId = IBookOrderFacet(diamond)
            .postBookCurve(result.yesBookId, LibEveMarket.CurveSide.ASK, ASK_AMOUNT, HALF_PRICE, HALF_PRICE, 30, 0, 0);
        result.bidCurveId = IBookOrderFacet(diamond)
            .postBookCurve(result.yesBookId, LibEveMarket.CurveSide.BID, BID_AMOUNT, HALF_PRICE, HALF_PRICE, 30, 0, 0);
    }

    function _measureComboGas(FullDeployment memory deployment, SmokeResult memory result, address maker) internal {
        uint256[] memory fiftyLegs = _prepareGasLegs(deployment.market.diamond);
        uint256[] memory tenLegs = new uint256[](10);
        for (uint256 index; index < tenLegs.length; ++index) {
            tenLegs[index] = fiftyLegs[index];
        }

        uint256 gasBefore = gasleft();
        (bytes32 tenConditionId,,) = IComboCoreFacet(result.diamond).prepareComboCondition(tenLegs);
        result.prepareTenLegGas = gasBefore - gasleft();

        gasBefore = gasleft();
        IComboCoreFacet(result.diamond).splitCombo(tenConditionId, GAS_SPLIT_AMOUNT, maker, maker);
        result.splitTenLegGas = gasBefore - gasleft();

        gasBefore = gasleft();
        (bytes32 fiftyConditionId,,) = IComboCoreFacet(result.diamond).prepareComboCondition(fiftyLegs);
        result.prepareFiftyLegGas = gasBefore - gasleft();

        gasBefore = gasleft();
        IComboCoreFacet(result.diamond).splitCombo(fiftyConditionId, GAS_SPLIT_AMOUNT, maker, maker);
        result.splitFiftyLegGas = gasBefore - gasleft();
    }

    function _prepareGasLegs(address diamond) internal returns (uint256[] memory legs) {
        legs = new uint256[](50);
        for (uint256 index; index < legs.length; ++index) {
            bytes32 marketId = _createSmokeMarket(diamond, index + 100, 10 days + index * 1 days);
            INativeBinaryPositionFacet.BinaryPositionIds memory leg =
                INativeBinaryPositionFacet(diamond).prepareNativeBinaryCondition(marketId);
            legs[index] = leg.yesPositionId;
        }
        _sortInPlace(legs);
    }

    function _fillComboAsk(FullDeployment memory deployment, SmokeResult memory result, address taker) internal {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(result.diamond).getCurveCommitment(result.askCurveId);

        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = result.askCurveId;
        uint32[] memory generations = new uint32[](1);
        generations[0] = generation;
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = commitment;

        IBookTradeFacet(result.diamond)
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: result.yesBookId,
                    maxQuoteIn: 6e18,
                    minBaseOut: ASK_AMOUNT,
                    maxAveragePrice: HALF_PRICE,
                    curveIds: curveIds,
                    expectedGenerations: generations,
                    expectedCommitments: commitments,
                    payer: taker,
                    receiver: taker
                })
            );

        uint256 balance = EvesPositionManager(deployment.market.evesPositionManager).balanceOf(taker, result.comboYes);
        require(balance == ASK_AMOUNT, "taker combo balance mismatch");

        (generation, commitment) = ICurveViewFacet(result.diamond).getCurveCommitment(result.bidCurveId);
        curveIds[0] = result.bidCurveId;
        generations[0] = generation;
        commitments[0] = commitment;

        EvesPositionManager(deployment.market.evesPositionManager).setApprovalForAll(result.diamond, true);
        IBookTradeFacet(result.diamond)
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: result.yesBookId,
                    maxBaseIn: BID_AMOUNT,
                    minQuoteOut: 1e18,
                    curveIds: curveIds,
                    expectedGenerations: generations,
                    expectedCommitments: commitments,
                    receiver: taker
                })
            );

        balance = EvesPositionManager(deployment.market.evesPositionManager).balanceOf(taker, result.comboYes);
        require(balance == FINAL_COMBO_AMOUNT, "taker post-bid combo balance mismatch");
    }

    function _compressCombo(FullDeployment memory deployment, SmokeResult memory result, address taker)
        internal
        returns (uint256 reducedComboYes)
    {
        NativePositionTypes.CompressionResult memory compression =
            IComboSettlementFacet(result.diamond).compressCombo(result.comboYes, FINAL_COMBO_AMOUNT, taker);
        require(compression.newPositionId != 0, "missing reduced combo");
        require(compression.positionAmount == FINAL_COMBO_AMOUNT, "bad compressed amount");
        require(compression.collateralOut == 0, "unexpected compression collateral");

        EvesPositionManager positions = EvesPositionManager(deployment.market.evesPositionManager);
        require(positions.balanceOf(taker, result.comboYes) == 0, "old combo not burned");
        require(positions.balanceOf(taker, compression.newPositionId) == FINAL_COMBO_AMOUNT, "reduced combo not minted");

        reducedComboYes = compression.newPositionId;
    }

    function _redeemCombo(FullDeployment memory deployment, SmokeResult memory result, address taker)
        internal
        returns (uint128 collateralOut)
    {
        uint256 balanceBefore = IERC20(deployment.eveUSDC).balanceOf(taker);
        collateralOut =
            IComboSettlementFacet(result.diamond).redeemCombo(result.reducedComboYes, FINAL_COMBO_AMOUNT, taker);
        require(collateralOut == FINAL_COMBO_AMOUNT, "bad redemption amount");
        require(
            IERC20(deployment.eveUSDC).balanceOf(taker) == balanceBefore + FINAL_COMBO_AMOUNT, "bad taker collateral"
        );
        require(
            EvesPositionManager(deployment.market.evesPositionManager).balanceOf(taker, result.reducedComboYes) == 0,
            "reduced combo not burned"
        );
    }

    function _smokeNativeBinarySplitMerge(
        FullDeployment memory deployment,
        address maker,
        bytes32 marketId,
        INativeBinaryPositionFacet.BinaryPositionIds memory leg
    ) internal {
        INativeBinaryPositionFacet(deployment.market.diamond).splitNativeBinary(marketId, BINARY_SMOKE_AMOUNT, maker);

        EvesPositionManager positions = EvesPositionManager(deployment.market.evesPositionManager);
        require(positions.balanceOf(maker, leg.yesPositionId) == BINARY_SMOKE_AMOUNT, "native yes split failed");
        require(positions.balanceOf(maker, leg.noPositionId) == BINARY_SMOKE_AMOUNT, "native no split failed");

        INativeBinaryPositionFacet(deployment.market.diamond).mergeNativeBinary(marketId, BINARY_SMOKE_AMOUNT, maker);
        require(positions.balanceOf(maker, leg.yesPositionId) == 0, "native yes merge failed");
        require(positions.balanceOf(maker, leg.noPositionId) == 0, "native no merge failed");
    }

    function _createSmokeMarket(address diamond, uint256 index, uint256 duration) internal returns (bytes32 marketId) {
        marketId = IMarketFactoryFacet(diamond)
            .createMarket(
                string.concat("Native combo smoke leg ", _u2s(index + 1)),
                "combo-smoke",
                "Local smoke test source; creator finalizes all legs as YES.",
                uint64(block.timestamp),
                uint64(block.timestamp + duration),
                0,
                true
            );
    }

    function _resolveYes(address diamond, bytes32 marketId) internal {
        IOBRResolutionFacet(diamond).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        vm.warp(block.timestamp + 2);
        IOBRResolutionFacet(diamond).finalizeResolution(marketId);
    }

    function _fundAndApprove(FullDeployment memory deployment, address account, uint256 usdcAmount) internal {
        MockUSDC(deployment.usdcToken).mint(account, usdcAmount);
        IERC20(deployment.usdcToken).approve(deployment.eveUSDC, usdcAmount);
        EveUSDC(deployment.eveUSDC).wrap(usdcAmount, account);
        IERC20(deployment.eveUSDC).approve(deployment.market.diamond, type(uint256).max);
    }

    function _smokeConfig(address owner) internal pure returns (FullDeploymentConfig memory c) {
        c.market.owner = owner;
        c.market.eveTreasury = owner;
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
        c.market.parimutuelMinEntry = 1e18;
        c.market.parimutuelEpochWindowCap = 30 days;
        c.market.marketCreationBatchCap = 30;
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
        c.market.parlayVaultFeeBps = 0;
        c.market.parlayFeeRecipientBps = 10_000;

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
        c.faucetUsdcEnabled = true;
        c.faucetEveEnabled = true;
        c.faucetUsdcClaimAmount = 1_000e6;
        c.faucetEveClaimAmount = 10_000e18;
        c.faucetUsdcFundAmount = 0;
        c.faucetEveFundAmount = 0;
    }

    function _sorted(uint256 first, uint256 second, uint256 third) internal pure returns (uint256[] memory legs) {
        legs = new uint256[](3);
        legs[0] = first;
        legs[1] = second;
        legs[2] = third;
        for (uint256 outer; outer < legs.length; ++outer) {
            for (uint256 inner = outer + 1; inner < legs.length; ++inner) {
                if (legs[inner] < legs[outer]) {
                    uint256 tmp = legs[outer];
                    legs[outer] = legs[inner];
                    legs[inner] = tmp;
                }
            }
        }
    }

    function _logResult(SmokeResult memory result) internal pure {
        console2.log("native combo smoke passed");
        console2.log("diamond", result.diamond);
        console2.log("eveUSDC", result.eveUSDC);
        console2.log("evesPositionManager", result.evesPositionManager);
        console2.log("yesBookId");
        console2.logBytes32(result.yesBookId);
        console2.log("noBookId");
        console2.logBytes32(result.noBookId);
        console2.log("comboYes", result.comboYes);
        console2.log("comboNo", result.comboNo);
        console2.log("reducedComboYes", result.reducedComboYes);
        console2.log("askCurveId", result.askCurveId);
        console2.log("bidCurveId", result.bidCurveId);
        console2.log("collateralOut", result.collateralOut);
        console2.log("prepareComboCondition 10-leg gas", result.prepareTenLegGas);
        console2.log("splitCombo 10-leg gas", result.splitTenLegGas);
        console2.log("prepareComboCondition 50-leg gas", result.prepareFiftyLegGas);
        console2.log("splitCombo 50-leg gas", result.splitFiftyLegGas);
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

    function _sortInPlace(uint256[] memory legs) internal pure {
        for (uint256 outer; outer < legs.length; ++outer) {
            for (uint256 inner = outer + 1; inner < legs.length; ++inner) {
                if (legs[inner] < legs[outer]) {
                    uint256 tmp = legs[outer];
                    legs[outer] = legs[inner];
                    legs[inner] = tmp;
                }
            }
        }
    }
}
