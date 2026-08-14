// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {CollateralTradeExecutionFacet} from "../../src/facets/CollateralTradeExecutionFacet.sol";
import {StaticsDollarTradeRouterFacet} from "../../src/facets/StaticsDollarTradeRouterFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {ICollateralTradeExecution} from "../../src/interfaces/ICollateralTradeExecution.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

import {StaticsDollar} from "@statics/dollar/StaticsDollar.sol";
import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";
import {IStaticsDollarCoreTypes} from "@statics/dollar/interfaces/IStaticsDollarCoreTypes.sol";
import {IStaticsDollarGateway} from "@statics/dollar/interfaces/IStaticsDollarGateway.sol";
import {IERC20Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {CollateralRouterFixture} from "../helpers/DiamondFixtures.sol";
import {StaticsDollarCoreFixture} from "../helpers/StaticsDollarCoreFixture.sol";

interface IRobinhoodUSDG is IERC20Metadata, IERC20Permit {
    function PERMIT_TYPEHASH() external view returns (bytes32);
}

contract RobinhoodStaticsDollarLifecycleForkTest is CollateralRouterFixture, StaticsDollarCoreFixture {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 internal constant ROBINHOOD_CHAIN_ID = 4663;
    uint256 internal constant ROBINHOOD_FORK_BLOCK = 14_498_238;
    address internal constant ROBINHOOD_USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    bytes32 internal constant ROBINHOOD_USDG_CODEHASH =
        0x864cc9ad53b338b82da1f7cab85ab0b3d5c8861acb422b6fec63cf36234f36a6;
    address internal constant ROBINHOOD_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    bytes32 internal constant ROBINHOOD_POOL_MANAGER_CODEHASH =
        0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626;

    function setUp() public override {}

    function test_RobinhoodForkMintsStaticsDollarAndBuysEvePosition() public {
        if (!_selectRobinhoodFork()) return;
        super.setUp();
        uint256 makerPrivateKey;
        uint256 takerPrivateKey;
        (maker, makerPrivateKey) = makeAddrAndKey("robinhoodMaker");
        (taker, takerPrivateKey) = makeAddrAndKey("robinhoodTaker");
        IRobinhoodUSDG usdg = IRobinhoodUSDG(ROBINHOOD_USDG);
        assertEq(address(usdg).codehash, ROBINHOOD_USDG_CODEHASH);
        assertEq(usdg.symbol(), "USDG");
        assertEq(usdg.decimals(), 6);
        assertEq(usdg.PERMIT_TYPEHASH(), PERMIT_TYPEHASH);

        StaticsDollarTradeRouterFacet routerFacet = new StaticsDollarTradeRouterFacet();
        CollateralTradeExecutionFacet executionFacet = new CollateralTradeExecutionFacet();
        _addFacet(address(routerFacet), _staticsDollarRouterSelectors());
        _addFacet(address(executionFacet), _collateralExecutionSelectors());

        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, usdg);
        IStaticsDollarCore core = IStaticsDollarCore(active.deployment.core);
        IStaticsDollarGateway gateway = IStaticsDollarGateway(active.deployment.diamond);
        StaticsDollar staticsDollar = StaticsDollar(active.deployment.staticsDollar);

        assertEq(core.periphery(), active.deployment.diamond);
        assertEq(core.positionNFT(), active.deployment.diamond);
        assertEq(gateway.pool(), active.deployment.core);
        assertEq(gateway.staticsDollar(), address(staticsDollar));
        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(ITradeRouter.mintAndBuyWithUSDC.selector),
            address(routerFacet)
        );
        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(ITradeRouter.mintAndBuyWithUSDCPermit.selector),
            address(routerFacet)
        );

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(address(staticsDollar));
        OwnershipFacet(address(diamond)).setStaticsDollarRail(active.deployment.core, active.profileId, address(usdg));
        vm.stopPrank();

        MarketFactoryTypes.MarketConfigView memory configured = IMarketFactoryFacet(address(diamond)).getMarketConfig();
        assertEq(configured.staticsDollarCore, active.deployment.core);
        assertEq(configured.staticsDiamond, active.deployment.diamond);
        assertEq(configured.collateralToken, address(staticsDollar));
        assertEq(configured.usdcToken, address(usdg));
        assertEq(configured.peggedProfileId, active.profileId);

        IStaticsDollarCoreTypes.PeggedMintPreview memory makerPreview = core.previewPeggedMint(active.profileId, 10e18);
        deal(address(usdg), maker, makerPreview.totalCollateralIn, false);
        IStaticsDollarGateway.PermitSignature memory makerPermit =
            _gatewayPermit(usdg, maker, makerPrivateKey, address(gateway), makerPreview.totalCollateralIn);
        vm.prank(maker);
        gateway.mintPeggedWithPermit(active.profileId, 10e18, makerPreview.totalCollateralIn, maker, makerPermit);
        vm.startPrank(maker);
        staticsDollar.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        (bytes32 marketId, ExpectedMarketData memory expected) =
            _createTradingMarket("Robinhood Statics Dollar", 7 days);
        vm.prank(maker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint128 staticsDollarAmount = 5e18;
        IStaticsDollarCoreTypes.PeggedMintPreview memory takerPreview =
            gateway.previewPeggedMint(active.profileId, staticsDollarAmount);
        deal(address(usdg), taker, takerPreview.totalCollateralIn, false);
        ITradeRouter.PermitSignature memory takerPermit =
            _routerPermit(usdg, taker, takerPrivateKey, address(diamond), takerPreview.totalCollateralIn);

        uint256 liabilitiesBefore = core.seniorLiabilities();
        uint256 supplyBefore = staticsDollar.totalSupply();
        uint256 coreCollateralBefore = usdg.balanceOf(address(core));
        uint256 protocolRevenueBefore = usdg.balanceOf(active.deployment.diamond);
        uint256 takerCollateralBefore = usdg.balanceOf(taker);

        ITradeRouter.BuyWithUSDCParams memory request = ITradeRouter.BuyWithUSDCParams({
            order: _singleCurveBuyParams(marketId, curveId, generation, commitment, staticsDollarAmount),
            maxUsdcIn: takerPreview.totalCollateralIn
        });
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result =
            ITradeRouter(address(diamond)).mintAndBuyWithUSDCPermit(request, takerPermit);

        assertGt(result.sharesOut, 0);
        assertEq(core.seniorLiabilities(), liabilitiesBefore + staticsDollarAmount);
        assertEq(staticsDollar.totalSupply(), supplyBefore + staticsDollarAmount);
        assertEq(usdg.balanceOf(address(core)), coreCollateralBefore + takerPreview.principalCollateral);
        assertEq(usdg.balanceOf(active.deployment.diamond), protocolRevenueBefore + takerPreview.feeAmount);
        assertEq(usdg.balanceOf(taker), takerCollateralBefore - takerPreview.totalCollateralIn);
        assertEq(usdg.nonces(taker), 1);
        assertEq(usdg.allowance(taker, address(diamond)), 0);
        assertEq(staticsDollar.balanceOf(taker), result.unfilledCollateral);
        assertEq(staticsDollar.balanceOf(address(diamond)), 0);
        assertEq(staticsDollar.allowance(address(diamond), active.deployment.diamond), 0);
        assertEq(conditionalTokens.balanceOf(taker, expected.yesPositionId), result.sharesOut);
    }

    function _gatewayPermit(IERC20Permit token, address signer, uint256 signerKey, address spender, uint256 amount)
        private
        view
        returns (IStaticsDollarGateway.PermitSignature memory signature)
    {
        signature.value = amount;
        (signature.deadline, signature.v, signature.r, signature.s) =
            _signPermit(token, signer, signerKey, spender, amount);
    }

    function _routerPermit(IERC20Permit token, address signer, uint256 signerKey, address spender, uint256 amount)
        private
        view
        returns (ITradeRouter.PermitSignature memory signature)
    {
        (signature.deadline, signature.v, signature.r, signature.s) =
            _signPermit(token, signer, signerKey, spender, amount);
    }

    function _signPermit(IERC20Permit token, address signer, uint256 signerKey, address spender, uint256 amount)
        private
        view
        returns (uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    {
        deadline = block.timestamp + 20 minutes;
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer, spender, amount, token.nonces(signer), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(signerKey, digest);
    }

    function _singleCurveBuyParams(
        bytes32 marketId,
        uint256 curveId,
        uint32 generation,
        bytes32 commitment,
        uint128 maxCollateralIn
    ) internal view returns (CurveCLOBTypes.FillBestParams memory params) {
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;
        uint32[] memory generations = new uint32[](1);
        generations[0] = generation;
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = commitment;
        params = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: true,
            maxCollateralIn: maxCollateralIn,
            minSharesOut: 0,
            maxAveragePrice: type(uint128).max,
            curveIds: curveIds,
            expectedGenerations: generations,
            expectedCommitments: commitments,
            payer: taker,
            receiver: taker
        });
    }

    function _staticsDollarRouterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.mintAndBuyWithUSDC.selector;
        selectors[1] = ITradeRouter.mintAndBuyWithUSDCPermit.selector;
    }

    function _collateralExecutionSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICollateralTradeExecution.executeCollateralBuy.selector;
    }

    function _selectRobinhoodFork() private returns (bool selected) {
        uint256 forkBlock = vm.envOr("ROBINHOOD_FORK_BLOCK", ROBINHOOD_FORK_BLOCK);
        assertEq(forkBlock, ROBINHOOD_FORK_BLOCK, "fork block differs from pinned deployment manifest");

        string memory rpcUrl = vm.envOr("ROBINHOOD_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) rpcUrl = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpcUrl).length == 0) {
            if (vm.envOr("REQUIRE_ROBINHOOD_FORK", false)) fail("Robinhood fork required");
            vm.skip(true, "Robinhood RPC is not configured");
            return false;
        }

        vm.createSelectFork(rpcUrl, forkBlock);
        assertEq(block.chainid, ROBINHOOD_CHAIN_ID);
        assertEq(block.number, ROBINHOOD_FORK_BLOCK);
        assertEq(ROBINHOOD_POOL_MANAGER.codehash, ROBINHOOD_POOL_MANAGER_CODEHASH);
        return true;
    }
}
