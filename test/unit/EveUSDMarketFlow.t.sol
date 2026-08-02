// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {EveUSDRouter} from "../../src/EveUSDRouter.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ComboMarketFacet} from "../../src/facets/native/ComboMarketFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract EveUSDMarketFlowTest is SettlementFeeFixture {
    uint256 internal constant WETH_PROFILE = 1;
    uint8 internal constant EVE_USD_PROFILE_ID = 2;
    uint128 internal constant EVE_USD_PAYOUT_UNIT = 1 ether;
    uint256 internal constant ETH_USD_PRICE_WAD = 2_500e18;
    uint256 internal constant ORACLE_MAX_STALENESS = 1 hours;
    uint256 internal constant COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant RECOVERY_TRIGGER_BPS = 8_000;
    uint72 internal constant HALF_PRICE = 500_000_000;

    CanonicalWETH9 internal weth;
    EveUSD internal eveUSD;
    EveRiskShares internal evRisk;
    MockETHUSDOracle internal oracle;
    EveUSDPool internal pool;
    EveUSDRouter internal router;
    EvesPositionManager internal comboPositions;

    function setUp() public override {
        super.setUp();

        weth = new CanonicalWETH9();
        oracle = new MockETHUSDOracle(ETH_USD_PRICE_WAD, ORACLE_MAX_STALENESS);
        (eveUSD, evRisk, pool) = _deployPool(COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        router = new EveUSDRouter(address(pool), address(weth), address(eveUSD), address(evRisk), WETH_PROFILE);
        comboPositions = new EvesPositionManager(address(diamond), "");

        _addFacet(address(ownershipFacet), _evesPositionManagerSelector());
        _addFacet(address(new ComboMarketFacet()), _comboMarketSelectors());
        _registerEveUSDProfile();

        vm.deal(maker, 10 ether);
        vm.deal(taker, 10 ether);
    }

    function test_EveUSDProfileRegistersWithExpectedCollateralMetadata() public view {
        MarketFactoryTypes.CollateralProfileView memory profile =
            IMarketFactoryFacet(address(diamond)).getCollateralProfile(EVE_USD_PROFILE_ID);

        assertEq(profile.collateralToken, address(eveUSD));
        assertEq(profile.wrapperToken, address(0));
        assertEq(profile.payoutUnit, EVE_USD_PAYOUT_UNIT);
        assertEq(profile.marketCreationFee, 0);
        assertTrue(profile.enabled);
    }

    function test_EveUSDProfileMarketTradesResolvesAndRedeems() public {
        (bytes32 marketId, uint64 expiryTime) = _createEveUSDMarket("Will eveUSD launch flow settle?");
        _fundEveUSD(maker, 1 ether);
        _fundEveUSD(taker, 1 ether);

        uint128 makerInventory = 500e18;
        uint128 takerCollateral = 250e18;

        vm.startPrank(maker);
        eveUSD.approve(address(diamond), makerInventory);
        uint128 sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, makerInventory);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId, true, makerInventory, HALF_PRICE, HALF_PRICE, 180, 0, LibEveMarket.PositionTokenType.CTF
            );
        vm.stopPrank();

        assertEq(sharesMinted, makerInventory);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, takerCollateral);

        vm.startPrank(taker);
        eveUSD.approve(address(diamond), takerCollateral);
        uint128 sharesOut = ICurveTradeFacet(address(diamond))
            .fillCurve(curveId, takerCollateral, previewShares, generation, commitment);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);

        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        (address redemptionCollateral, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
        uint256 takerBalanceBefore = eveUSD.balanceOf(taker);

        vm.prank(taker);
        conditionalTokens.redeemPositions(IERC20(redemptionCollateral), bytes32(0), conditionId, indexSets);

        assertEq(redemptionCollateral, address(eveUSD));
        assertEq(eveUSD.balanceOf(taker), takerBalanceBefore + sharesOut);
    }

    function test_RevertWhen_EveUSDAndDefaultCollateralAreCombined() public {
        (bytes32 defaultMarketId,,) = _createTradingMarket("Will default collateral combo leg win?", "eveusd", 7 days);
        (bytes32 eveUSDMarketId,) = _createEveUSDMarket("Will eveUSD combo leg win?");

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setEvesPositionManager(address(comboPositions));

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ComboCollateralMismatch.selector, address(collateralToken), address(eveUSD))
        );
        IComboMarketFacet(address(diamond)).createComboMarket(_pair(defaultMarketId, eveUSDMarketId), _yesLegs());
    }

    function _registerEveUSDProfile() internal {
        vm.startPrank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(EVE_USD_PROFILE_ID, address(eveUSD), address(0), EVE_USD_PAYOUT_UNIT, 0, true);
        vm.stopPrank();
    }

    function _createEveUSDMarket(string memory question) internal returns (bytes32 marketId, uint64 expiryTime) {
        uint64 tradingStartTime = uint64(block.timestamp);
        expiryTime = tradingStartTime + 7 days;

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                EVE_USD_PROFILE_ID, question, "eveusd", DEFAULT_RESOLUTION_SOURCE, tradingStartTime, expiryTime, 0, true
            );

        bytes32 expectedMarketId = LibMarketCreation.profileMarketIdFor(
            question,
            "eveusd",
            tradingStartTime,
            expiryTime,
            address(eveUSD),
            EVE_USD_PROFILE_ID,
            EVE_USD_PAYOUT_UNIT,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        assertEq(marketId, expectedMarketId);

        (address storedCollateral,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        assertEq(storedCollateral, address(eveUSD));
    }

    function _fundEveUSD(address account, uint256 ethAmount) internal {
        vm.prank(account);
        router.depositETH{value: ethAmount}(account, account, 0, 0);
    }

    function _deployPool(uint256 collateralRatioBps, uint256 recoveryTriggerBps)
        internal
        returns (EveUSD deployedEveUSD, EveRiskShares deployedEvRisk, EveUSDPool deployedPool)
    {
        address predictedPool = _nextPoolAddress();
        deployedEveUSD = new EveUSD(predictedPool);
        deployedEvRisk = new EveRiskShares(predictedPool, "");
        deployedPool = new EveUSDPool(
            address(weth),
            address(deployedEveUSD),
            address(deployedEvRisk),
            address(oracle),
            owner,
            collateralRatioBps,
            recoveryTriggerBps
        );
        assertEq(address(deployedPool), predictedPool);
    }

    function _nextPoolAddress() internal view returns (address) {
        return vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
    }

    function _pair(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory marketIds) {
        marketIds = new bytes32[](2);
        marketIds[0] = first;
        marketIds[1] = second;
    }

    function _yesLegs() internal pure returns (bool[] memory yesLegs) {
        yesLegs = new bool[](2);
        yesLegs[0] = true;
        yesLegs[1] = true;
    }

    function _evesPositionManagerSelector() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = OwnershipFacet.setEvesPositionManager.selector;
    }

    function _comboMarketSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.computeComboBookId.selector;
        selectors[2] = IComboMarketFacet.getComboMarket.selector;
        selectors[3] = IComboMarketFacet.getComboBook.selector;
    }
}
