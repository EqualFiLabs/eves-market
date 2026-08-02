// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {DeployScript} from "./Deploy.s.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "../src/interfaces/IConditionalTokens.sol";
import {IBookAdminFacet} from "../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../src/types/CurveCLOBTypes.sol";
import {IEveUSDC} from "../src/interfaces/IEveUSDC.sol";
import {IMarketFactoryFacet} from "../src/interfaces/IMarketFactoryFacet.sol";
import {LibCurvePacking} from "../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../src/libraries/LibEveMarket.sol";
import {MockUSDC} from "../test/helpers/MockUSDC.sol";

contract GasBench is DeployScript {
    uint128 internal constant CURVE_VOLUME = 1e6;
    uint72 internal constant START_PRICE = 5 * 1e8;
    uint72 internal constant END_PRICE = 5 * 1e8;
    uint24 internal constant DURATION_MIN = 60 * 24;
    uint8 internal constant LINEAR = 0;

    uint256 internal constant CURVES_PER_SIDE = 25;
    uint256 internal constant MARKET_COUNT = 3;
    uint256 internal constant BATCH = 10;

    address internal _diamond;
    address internal _ctf;

    function bench() external returns (FullDeployment memory d) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);
        d = deployFullStack(_benchConfig(deployer), deployer);
        _diamond = d.market.diamond;
        _ctf = d.market.conditionalTokens;

        _fund(d, deployer);
        bytes32[] memory marketIds = _createMarkets();
        uint256[] memory ids0 = _seedCurves(marketIds[0]);

        console2.log("=== eve-predict CurveCLOB gas benchmark ===");
        console2.log("Markets created:", MARKET_COUNT);
        console2.log("Curves pre-posted on test market (both sides):", CURVES_PER_SIDE * 2);
        console2.log("");

        _runBench(marketIds[0], ids0);
        vm.stopBroadcast();
    }

    function _fund(FullDeployment memory d, address deployer) internal {
        uint256 funding = 1_000_000e6;
        MockUSDC(d.usdcToken).mint(deployer, funding);
        IERC20(d.usdcToken).approve(d.eveUSDC, type(uint256).max);
        IEveUSDC(d.eveUSDC).wrap(funding, deployer);
        IERC20(d.eveUSDC).approve(d.market.diamond, type(uint256).max);
        IConditionalTokens(d.market.conditionalTokens).setApprovalForAll(d.market.diamond, true);
    }

    function _createMarkets() internal returns (bytes32[] memory ids) {
        ids = new bytes32[](MARKET_COUNT);
        for (uint256 i = 0; i < MARKET_COUNT; ++i) {
            ids[i] = IMarketFactoryFacet(_diamond)
                .createMarket(
                    string.concat("bench market ", _u2s(i)),
                    "bench",
                    "Benchmark settlement rules published in the test harness.",
                    uint64(block.timestamp),
                    uint64(block.timestamp + 30 days),
                    0,
                    true
                );
            ICurveInventoryFacet(_diamond).splitInventory(ids[i], uint128(CURVE_VOLUME * (CURVES_PER_SIDE * 2 + 64)));
        }
    }

    function _seedCurves(bytes32 mkt) internal returns (uint256[] memory ids) {
        ids = new uint256[](CURVES_PER_SIDE * 2);
        for (uint256 i = 0; i < CURVES_PER_SIDE * 2; ++i) {
            bool isYes = i < CURVES_PER_SIDE;
            ids[i] = ICurveLifecycleFacet(_diamond)
                .postCurve(
                    mkt,
                    isYes,
                    CURVE_VOLUME,
                    START_PRICE,
                    END_PRICE,
                    DURATION_MIN,
                    LINEAR,
                    LibEveMarket.PositionTokenType.CTF
                );
        }
    }

    function _runBench(bytes32 mkt, uint256[] memory ids) internal {
        uint256 g;

        g = _benchPostSingle(mkt);
        console2.log("postCurve (single):    ", g);

        uint256 gB = _benchPostBatch(mkt);
        console2.log("postCurvesBatch (10):  ", gB);
        console2.log("  per-curve in batch:  ", gB / BATCH);

        uint256 gU = _benchUpdateSingle(ids[0]);
        console2.log("updateCurve (single):  ", gU);

        uint256 gUB = _benchUpdateBatch(ids);
        console2.log("updateCurvesBatch (10):", gUB);
        console2.log("  per-curve in batch:  ", gUB / BATCH);

        uint256 gC = _benchCancelSingle(ids[11]);
        console2.log("cancelCurve (single):  ", gC);

        uint256 gCB = _benchCancelBatch(ids);
        console2.log("cancelCurvesBatch (10):", gCB);
        console2.log("  per-curve in batch:  ", gCB / BATCH);
    }

    function _benchPostSingle(bytes32 mkt) internal returns (uint256 used) {
        uint256 g0 = gasleft();
        ICurveLifecycleFacet(_diamond)
            .postCurve(
                mkt,
                true,
                CURVE_VOLUME,
                START_PRICE,
                END_PRICE,
                DURATION_MIN,
                LINEAR,
                LibEveMarket.PositionTokenType.CTF
            );
        used = g0 - gasleft();
    }

    function _benchPostBatch(bytes32 mkt) internal returns (uint256 used) {
        CurveCLOBTypes.CurveCreationParams[] memory p = new CurveCLOBTypes.CurveCreationParams[](BATCH);
        for (uint256 i = 0; i < BATCH; ++i) {
            p[i] = CurveCLOBTypes.CurveCreationParams({
                isYesSide: i % 2 == 0,
                volume: CURVE_VOLUME,
                startPrice: START_PRICE,
                endPrice: END_PRICE,
                durationMinutes: DURATION_MIN,
                profileId: LINEAR,
                tickPresetId: 0
            });
        }
        uint256 g0 = gasleft();
        ICurveLifecycleFacet(_diamond).postCurvesBatch(mkt, LibEveMarket.PositionTokenType.CTF, p);
        used = g0 - gasleft();
    }

    function _benchUpdateSingle(uint256 curveId) internal returns (uint256 used) {
        uint256 packed = LibCurvePacking.pack(uint72(START_PRICE + 1), END_PRICE, DURATION_MIN, LINEAR);
        uint256 g0 = gasleft();
        ICurveLifecycleFacet(_diamond).updateCurve(curveId, packed, 1);
        used = g0 - gasleft();
    }

    function _benchUpdateBatch(uint256[] memory ids) internal returns (uint256 used) {
        CurveCLOBTypes.CurveUpdateParams[] memory p = new CurveCLOBTypes.CurveUpdateParams[](BATCH);
        for (uint256 i = 0; i < BATCH; ++i) {
            p[i] = CurveCLOBTypes.CurveUpdateParams({
                curveId: ids[1 + i],
                newPacked: LibCurvePacking.pack(uint72(START_PRICE + 2 + uint72(i)), END_PRICE, DURATION_MIN, LINEAR),
                expectedGeneration: 1
            });
        }
        uint256 g0 = gasleft();
        ICurveLifecycleFacet(_diamond).updateCurvesBatch(p);
        used = g0 - gasleft();
    }

    function _benchCancelSingle(uint256 curveId) internal returns (uint256 used) {
        uint256 g0 = gasleft();
        ICurveLifecycleFacet(_diamond).cancelCurve(curveId);
        used = g0 - gasleft();
    }

    function _benchCancelBatch(uint256[] memory ids) internal returns (uint256 used) {
        uint256[] memory arr = new uint256[](BATCH);
        for (uint256 i = 0; i < BATCH; ++i) {
            arr[i] = ids[12 + i];
        }
        uint256 g0 = gasleft();
        ICurveLifecycleFacet(_diamond).cancelCurvesBatch(arr);
        used = g0 - gasleft();
    }

    function _benchConfig(address owner) internal pure returns (FullDeploymentConfig memory c) {
        c.market.owner = owner;
        c.market.eveTreasury = owner;
        c.market.orderbookEntryFeeBps = 0;
        c.market.orderbookMakerFeeBps = 8500;
        c.market.orderbookCreatorFeeBps = 400;
        c.market.orderbookProtocolFeeBps = 1000;
        c.market.orderbookVaultFeeBps = 100;
        c.market.spotTradeFeeBps = 0;
        c.market.spotMakerFeeBps = 8500;
        c.market.spotProtocolFeeBps = 1500;
        c.market.spotVaultFeeBps = 0;
        c.market.parimutuelEntryFeeBps = 250;
        c.market.parimutuelCreatorFeeBps = 500;
        c.market.parimutuelProtocolFeeBps = 9500;
        c.market.parimutuelVaultFeeBps = 0;
        c.market.parimutuelMinEntry = 1e6;
        c.market.marketCreationFee = 0;
        c.market.spotBookCreationFee = 0;
        c.market.marketCreationBond = 0;
        c.market.bondToken = c.market.eveToken;
        c.market.resolutionBondL1 = 0;
        c.market.resolutionBondL2 = 0;
        c.market.minMarketDuration = 60;
        c.market.maxMarketDuration = 365 days;
        c.market.disputeWindow = 1 hours;
        c.market.creatorSettleGrace = 1 hours;
        c.market.openResolutionTimeout = 1 days;
        c.market.maxEscalation = 2;
        c.market.permissionlessCreationEnabled = true;

        c.aumFeeBps = 200;
        c.lendingMaxLtvBps = 9500;
        c.lendingOriginationFeeBps = 100;
        c.lendingExtensionFeeBps = 50;
        c.lendingFeeRecipientBps = 0;
        c.lendingMinDurationSeconds = uint32(1 days);
        c.lendingMaxDurationSeconds = uint32(400 days);
        c.lendingGracePeriodSeconds = uint32(1 days);
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

    function _u2s(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory buf = new bytes(78);
        uint256 i = 0;
        while (v != 0) {
            buf[i++] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        bytes memory out = new bytes(i);
        for (uint256 j = 0; j < i; ++j) {
            out[j] = buf[i - 1 - j];
        }
        return string(out);
    }
}
