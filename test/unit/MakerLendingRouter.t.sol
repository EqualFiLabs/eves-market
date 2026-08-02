// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import {MakerLendingRouter} from "../../src/MakerLendingRouter.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMakerLendingRouter} from "../../src/interfaces/IMakerLendingRouter.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {ResolutionHarnessFacet} from "../helpers/DiamondFixtures.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {RouterTestBase} from "../helpers/RouterTestBase.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract MakerLendingRouterTest is RouterTestBase {
    uint16 internal constant PARIMUTUEL_ENTRY_FEE_BPS = 250;
    uint128 internal constant PARIMUTUEL_MIN_ENTRY = 1e6;

    event Onramped(
        address indexed caller,
        address indexed borrower,
        bytes32 indexed marketId,
        uint256 usdcAmount,
        uint256 netBorrowed,
        uint256 debtPrincipal,
        uint256 originationFee,
        uint256 loanId,
        uint128 positionSharesMinted,
        address receiver
    );
    event OfframpedToShares(
        address indexed caller,
        address indexed borrower,
        uint256 loanId,
        bytes32 indexed marketId,
        uint128 positionSharesMerged,
        uint256 mergeEveUSDCOut,
        uint256 debtRepaid,
        uint256 excessEveUSDC
    );
    event OfframpedToUSDC(
        address indexed caller,
        address indexed borrower,
        uint256 loanId,
        bytes32 indexed marketId,
        uint128 positionSharesMerged,
        uint256 mergeEveUSDCOut,
        uint256 debtRepaid,
        uint256 redeemedCollateralEveUSDC,
        uint256 usdcAmount,
        address receiver
    );
    event ParimutuelOnramped(
        address indexed caller,
        address indexed borrower,
        bytes32 indexed marketId,
        bool isYes,
        uint256 usdcAmount,
        uint256 netBorrowed,
        uint256 debtPrincipal,
        uint256 originationFee,
        uint256 loanId,
        uint128 sharesMinted,
        address receiver
    );
    event ERC20Rescued(address indexed token, address indexed receiver, uint256 amount);
    event ERC1155Rescued(address indexed token, uint256 indexed id, address indexed receiver, uint256 amount);

    ParimutuelShareToken internal parimutuelShareToken;

    function setUp() public override {
        super.setUp();
        _addFacet(address(new ResolutionHarnessFacet()), _resolutionHarnessSelectors());
        _addFacet(address(new ParimutuelFacet()), _parimutuelSelectors());

        parimutuelShareToken = new ParimutuelShareToken(address(diamond), "uri://parimutuel/{id}");

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(500, 1_000, 8_500);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        OwnershipFacet(address(diamond))
            .setParimutuelConfig(address(parimutuelShareToken), PARIMUTUEL_ENTRY_FEE_BPS, PARIMUTUEL_MIN_ENTRY);
        vm.stopPrank();
    }

    function test_BasicOnrampCreatesLoanAndDeliversPositions() public {
        uint256 usdcAmount = 500e6;
        uint256 borrowAmount = 200e6;

        uint256 expectedVaultShares = vault.previewDeposit(usdcAmount * 1e12);
        (uint256 loanId, uint128 positionSharesMinted) =
            _onramp(borrower, usdcAmount, borrowAmount, 7 days, marketIdA, routerReceiver);

        ISEveUSDCLending.Loan memory loan = _loanState(loanId);
        (uint256 yesBalance, uint256 noBalance) = _positionBalances(routerReceiver, marketIdA);

        assertEq(loan.borrower, borrower);
        assertEq(uint256(loan.collateralShares), expectedVaultShares);
        assertEq(uint256(loan.debtPrincipal), borrowAmount);
        assertEq(positionSharesMinted, loan.netBorrowed);
        assertEq(yesBalance, positionSharesMinted);
        assertEq(noBalance, positionSharesMinted);
        _assertRouterClean(marketIdA);
    }

    function test_OnrampUsesStoredPositionTokenAfterDefaultChange() public {
        MockConditionalTokens replacementDefault = new MockConditionalTokens();

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(replacementDefault));

        (, uint128 positionSharesMinted) = _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, routerReceiver);
        MarketFactoryTypes.MarketInfo memory market = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketIdA);

        assertEq(conditionalTokens.balanceOf(routerReceiver, market.yesPositionId), positionSharesMinted);
        assertEq(conditionalTokens.balanceOf(routerReceiver, market.noPositionId), positionSharesMinted);
        assertEq(replacementDefault.balanceOf(routerReceiver, market.yesPositionId), 0);
        assertEq(replacementDefault.balanceOf(routerReceiver, market.noPositionId), 0);
        _assertRouterClean(marketIdA);
    }

    function test_OnrampToleratesPreExistingDustAndOwnerCanRescue() public {
        MarketFactoryTypes.MarketInfo memory market = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketIdA);

        usdc.mint(address(router), 1);
        _seedEveUSDC(address(router), 2);
        _mintMatchedPositions(borrower, marketIdA, 10e6);

        vm.prank(borrower);
        conditionalTokens.safeTransferFrom(borrower, address(router), market.yesPositionId, 1, "");

        _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, borrower);

        assertEq(usdc.balanceOf(address(router)), 1);
        assertEq(eveUSDC.balanceOf(address(router)), 2);
        assertEq(conditionalTokens.balanceOf(address(router), market.yesPositionId), 1);
        assertEq(conditionalTokens.balanceOf(address(router), market.noPositionId), 0);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(IMakerLendingRouter.NotOwner.selector, borrower));
        router.rescueERC20(address(usdc), alternateReceiver, 1);

        vm.expectEmit(true, true, false, true, address(router));
        emit ERC20Rescued(address(usdc), alternateReceiver, 1);
        router.rescueERC20(address(usdc), alternateReceiver, 1);

        vm.expectEmit(true, true, true, true, address(router));
        emit ERC1155Rescued(address(conditionalTokens), market.yesPositionId, alternateReceiver, 1);
        router.rescueERC1155(address(conditionalTokens), market.yesPositionId, alternateReceiver, 1);

        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(conditionalTokens.balanceOf(address(router), market.yesPositionId), 0);
    }

    function test_OfframpToUsdcDoesNotUnwrapPreExistingEveUSDCDust() public {
        (uint256 loanId, uint128 initialShares) = _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 7);
        _approveRouterPositions(borrower);
        _notifyRevenue(80e6);
        _seedEveUSDC(address(router), 3);

        uint256 routerDustBefore = eveUSDC.balanceOf(address(router));
        uint256 receiverBefore = usdc.balanceOf(alternateReceiver);
        (,,, uint256 expectedUsdcOut) = router.previewOfframpToUSDC(loanId, marketIdA, positionShareAmount);

        uint256 usdcOut = _offrampToUSDC(borrower, loanId, marketIdA, positionShareAmount, alternateReceiver);

        assertEq(usdcOut, expectedUsdcOut);
        assertEq(usdc.balanceOf(alternateReceiver) - receiverBefore, expectedUsdcOut);
        assertEq(eveUSDC.balanceOf(address(router)), routerDustBefore);
    }

    function test_OnrampHonorsSubMaxExactBorrowAmount() public {
        uint256 usdcAmount = 1_000e6;
        uint256 borrowAmount = 123e6;
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);

        assertGt(maxBorrow, borrowAmount);

        (uint256 loanId, uint128 positionSharesMinted) =
            _onramp(borrower, usdcAmount, borrowAmount, 30 days, marketIdA, borrower);

        ISEveUSDCLending.Loan memory loan = _loanState(loanId);
        assertEq(uint256(loan.debtPrincipal), borrowAmount);
        assertEq(positionSharesMinted, loan.netBorrowed);
        assertLt(uint256(loan.debtPrincipal), maxBorrow + 1);
    }

    function test_ParimutuelOnrampCreatesLoanAndBuysSelectedSide() public {
        bytes32 parimutuelMarketId = _createParimutuelMarket("router parimutuel onramp");
        uint256 usdcAmount = 500e6;
        uint256 borrowAmount = 200e6;

        (
            uint256 expectedVaultShares,
            uint128 expectedSharesMinted,
            uint128 expectedEntryFee,
            uint256 expectedOriginationFee,
            uint256 expectedDebtPrincipal
        ) = router.previewParimutuelOnramp(usdcAmount, borrowAmount, parimutuelMarketId);

        _seedUsdcAndApproveRouter(borrower, usdcAmount);
        vm.prank(borrower);
        (uint256 loanId, uint128 sharesMinted) = router.onrampParimutuel(
            usdcAmount, borrowAmount, 7 days, parimutuelMarketId, true, expectedSharesMinted, routerReceiver
        );

        ISEveUSDCLending.Loan memory loan = _loanState(loanId);
        MarketFactoryTypes.MarketInfo memory market =
            IMarketFactoryFacet(address(diamond)).getMarketInfo(parimutuelMarketId);
        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(parimutuelMarketId);

        assertEq(loan.borrower, borrower);
        assertEq(uint256(loan.collateralShares), expectedVaultShares);
        assertEq(uint256(loan.netBorrowed), expectedDebtPrincipal - expectedOriginationFee);
        assertEq(uint256(loan.debtPrincipal), expectedDebtPrincipal);
        assertEq(uint256(loan.debtPrincipal), borrowAmount);
        assertEq(expectedOriginationFee, uint256(loan.originationFeeCharged));
        assertEq(sharesMinted, expectedSharesMinted);
        assertEq(parimutuelShareToken.balanceOf(routerReceiver, market.yesPositionId), sharesMinted);
        assertEq(parimutuelShareToken.balanceOf(routerReceiver, market.noPositionId), 0);
        assertEq(pool.totalYesShares, sharesMinted);
        assertEq(pool.totalNoShares, 0);
        // payoutPool tracks collateral (net borrowed - entry fee), not inflated shares
        assertEq(pool.payoutPool, uint256(loan.netBorrowed) - expectedEntryFee);
        _assertRouterClean(parimutuelMarketId);
    }

    function test_ParimutuelOnrampCanBuyNoSideAndEmitEvent() public {
        bytes32 parimutuelMarketId = _createParimutuelMarket("router parimutuel no onramp");
        uint256 usdcAmount = 500e6;
        uint256 borrowAmount = 200e6;
        (uint256 expectedDebtPrincipal, uint256 expectedOriginationFee) =
            lending.previewBorrowTerms(vault.previewDeposit(usdcAmount * USDC_TO_EVEUSDC_SCALE), borrowAmount);
        uint256 expectedNetBorrowed = expectedDebtPrincipal - expectedOriginationFee;
        // previewParimutuelOnramp already accounts for epoch multiplier
        (, uint128 expectedSharesMinted,,,) =
            router.previewParimutuelOnramp(usdcAmount, borrowAmount, parimutuelMarketId);

        _seedUsdcAndApproveRouter(borrower, usdcAmount);
        vm.prank(borrower);
        vm.expectEmit(true, true, true, true, address(router));
        emit ParimutuelOnramped(
            borrower,
            borrower,
            parimutuelMarketId,
            false,
            usdcAmount,
            expectedNetBorrowed,
            expectedDebtPrincipal,
            expectedOriginationFee,
            1,
            expectedSharesMinted,
            routerReceiver
        );
        (uint256 loanId, uint128 sharesMinted) = router.onrampParimutuel(
            usdcAmount, borrowAmount, 7 days, parimutuelMarketId, false, expectedSharesMinted, routerReceiver
        );

        MarketFactoryTypes.MarketInfo memory market =
            IMarketFactoryFacet(address(diamond)).getMarketInfo(parimutuelMarketId);
        assertEq(loanId, 1);
        assertEq(sharesMinted, expectedSharesMinted);
        assertEq(parimutuelShareToken.balanceOf(routerReceiver, market.yesPositionId), 0);
        assertEq(parimutuelShareToken.balanceOf(routerReceiver, market.noPositionId), sharesMinted);
        _assertRouterClean(parimutuelMarketId);
    }

    function test_RevertWhen_ParimutuelOnrampSlippageOrInvalidInputs() public {
        bytes32 parimutuelMarketId = _createParimutuelMarket("router parimutuel slippage");
        uint256 usdcAmount = 500e6;
        uint256 borrowAmount = 200e6;
        (, uint128 expectedSharesMinted,,,) =
            router.previewParimutuelOnramp(usdcAmount, borrowAmount, parimutuelMarketId);

        _seedUsdcAndApproveRouter(borrower, usdcAmount * 4);

        vm.prank(borrower);
        vm.expectRevert(IMakerLendingRouter.ZeroAmount.selector);
        router.onrampParimutuel(0, borrowAmount, 7 days, parimutuelMarketId, true, 0, routerReceiver);

        vm.prank(borrower);
        vm.expectRevert(IMakerLendingRouter.ZeroAmount.selector);
        router.onrampParimutuel(usdcAmount, 0, 7 days, parimutuelMarketId, true, 0, routerReceiver);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(IMakerLendingRouter.InvalidReceiver.selector, address(0)));
        router.onrampParimutuel(usdcAmount, borrowAmount, 7 days, parimutuelMarketId, true, 0, address(0));

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SlippageExceeded.selector, expectedSharesMinted, expectedSharesMinted + 1)
        );
        router.onrampParimutuel(
            usdcAmount, borrowAmount, 7 days, parimutuelMarketId, true, expectedSharesMinted + 1, routerReceiver
        );
    }

    function test_RevertWhen_ParimutuelOnrampTargetsCTFMarket() public {
        _seedUsdcAndApproveRouter(borrower, 500e6);

        vm.expectRevert(_positionTokenTypeMismatch(marketIdA, LibEveMarket.PositionTokenType.PARIMUTUEL));
        router.previewParimutuelOnramp(500e6, 200e6, marketIdA);

        vm.prank(borrower);
        vm.expectRevert(_positionTokenTypeMismatch(marketIdA, LibEveMarket.PositionTokenType.PARIMUTUEL));
        router.onrampParimutuel(500e6, 200e6, 7 days, marketIdA, true, 0, borrower);
    }

    function test_RevertWhen_ZeroAmountsOrZeroReceiversProvided() public {
        _seedUsdcAndApproveRouter(borrower, 500e6);

        vm.prank(borrower);
        vm.expectRevert(IMakerLendingRouter.ZeroAmount.selector);
        router.onramp(0, 100e6, 7 days, marketIdA, borrower);

        vm.prank(borrower);
        vm.expectRevert(IMakerLendingRouter.ZeroAmount.selector);
        router.onramp(100e6, 0, 7 days, marketIdA, borrower);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(IMakerLendingRouter.InvalidReceiver.selector, address(0)));
        router.onramp(100e6, 50e6, 7 days, marketIdA, address(0));

        (uint256 loanId, uint128 initialShares) = _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 1);
        _approveRouterPositions(borrower);

        vm.prank(borrower);
        vm.expectRevert(IMakerLendingRouter.ZeroAmount.selector);
        router.offrampToShares(loanId, marketIdA, 0);

        vm.prank(borrower);
        vm.expectRevert(IMakerLendingRouter.ZeroAmount.selector);
        router.offrampToUSDC(loanId, marketIdA, 0, alternateReceiver);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(IMakerLendingRouter.InvalidReceiver.selector, address(0)));
        router.offrampToUSDC(loanId, marketIdA, positionShareAmount, address(0));
    }

    function test_RevertWhen_InvalidMarketOrInvalidCollateralUsed() public {
        bytes32 missingMarketId = keccak256("missing-market");
        _seedUsdcAndApproveRouter(borrower, 500e6);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotFound.selector, missingMarketId));
        router.onramp(500e6, 200e6, 7 days, missingMarketId, borrower);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(address(usdc));
        bytes32 usdcMarketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "usdc-market",
                "router",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 9 days),
                0,
                true
            );
        OwnershipFacet(address(diamond)).setCollateralToken(address(eveUSDC));
        vm.stopPrank();

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(IMakerLendingRouter.InvalidMarketCollateral.selector, address(usdc), address(eveUSDC))
        );
        router.onramp(500e6, 200e6, 7 days, usdcMarketId, borrower);

        CanonicalWETH9 weth = new CanonicalWETH9();
        EveETH eveETH = new EveETH(address(weth));

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralProfile(1, address(eveETH), address(weth), 0.0005 ether, 0, true);
        bytes32 eveEthMarketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                1,
                "eveeth-market",
                "router",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 9 days),
                0,
                true
            );
        vm.stopPrank();

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMakerLendingRouter.InvalidMarketCollateral.selector, address(eveETH), address(eveUSDC)
            )
        );
        router.onramp(500e6, 200e6, 7 days, eveEthMarketId, borrower);
    }

    function test_RevertWhen_MakerLendingRouterTargetsParimutuelMarket() public {
        (uint256 loanId, uint128 initialShares) = _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 1);
        _approveRouterPositions(borrower);

        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketIdA, uint8(LibEveMarket.MarketType.PARIMUTUEL), address(conditionalTokens)
            );

        vm.expectRevert(_positionTokenTypeMismatch(marketIdA));
        router.previewOfframpToShares(loanId, marketIdA, positionShareAmount);

        vm.expectRevert(_positionTokenTypeMismatch(marketIdA));
        router.previewOfframpToUSDC(loanId, marketIdA, positionShareAmount);

        vm.expectRevert(_positionTokenTypeMismatch(marketIdA));
        vm.prank(borrower);
        router.offrampToShares(loanId, marketIdA, positionShareAmount);

        vm.expectRevert(_positionTokenTypeMismatch(marketIdA));
        vm.prank(borrower);
        router.offrampToUSDC(loanId, marketIdA, positionShareAmount, alternateReceiver);

        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketIdB, uint8(LibEveMarket.MarketType.PARIMUTUEL), address(conditionalTokens)
            );

        vm.expectRevert(_positionTokenTypeMismatch(marketIdB));
        router.previewOnramp(500e6, 200e6, marketIdB);

        _seedUsdcAndApproveRouter(secondBorrower, 500e6);

        vm.expectRevert(_positionTokenTypeMismatch(marketIdB));
        vm.prank(secondBorrower);
        router.onramp(500e6, 200e6, 7 days, marketIdB, secondBorrower);
    }

    function test_OfframpToSharesLifecycleRepaysLoanAndReturnsVaultShares() public {
        (uint256 loanId, uint128 initialShares) = _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 5);
        _approveRouterPositions(borrower);

        (uint256 expectedMergeOut, uint256 expectedRepayment, uint256 expectedExcess) =
            router.previewOfframpToShares(loanId, marketIdA, positionShareAmount);
        uint256 eveUSDCBefore = eveUSDC.balanceOf(borrower);
        uint256 collateralShares = _loanCollateral(loanId);

        _offrampToShares(borrower, loanId, marketIdA, positionShareAmount);

        ISEveUSDCLending.Loan memory loan = _loanState(loanId);
        assertTrue(loan.repaid);
        assertEq(vault.balanceOf(borrower), collateralShares);
        assertEq(eveUSDC.balanceOf(borrower) - eveUSDCBefore, expectedExcess);
        assertEq(expectedMergeOut, uint256(positionShareAmount));
        assertEq(expectedRepayment, _loanDebt(loanId));
        _assertRouterClean(marketIdA);
    }

    function test_OfframpToUsdcLifecycleRepaysLoanRedeemsYieldAndUnwraps() public {
        (uint256 loanId, uint128 initialShares) = _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 7);
        _approveRouterPositions(borrower);
        _notifyRevenue(80e6);

        (
            uint256 expectedMergeOut,
            uint256 expectedRedeemedCollateral,
            uint256 expectedRepayment,
            uint256 expectedUsdcOut
        ) = router.previewOfframpToUSDC(loanId, marketIdA, positionShareAmount);
        uint256 receiverBefore = usdc.balanceOf(alternateReceiver);

        uint256 usdcOut = _offrampToUSDC(borrower, loanId, marketIdA, positionShareAmount, alternateReceiver);

        ISEveUSDCLending.Loan memory loan = _loanState(loanId);
        assertTrue(loan.repaid);
        assertEq(usdcOut, expectedUsdcOut);
        assertEq(usdc.balanceOf(alternateReceiver) - receiverBefore, expectedUsdcOut);
        assertEq(expectedMergeOut, uint256(positionShareAmount));
        assertEq(expectedRepayment, _loanDebt(loanId));
        assertGt(expectedRedeemedCollateral, _loanCollateral(loanId));
        _assertRouterClean(marketIdA);
    }

    function test_RevertWhen_NonBorrowerAttemptsOfframp() public {
        (uint256 loanId,) = _onramp(borrower, 500e6, 200e6, 7 days, marketIdA, borrower);

        vm.prank(secondBorrower);
        vm.expectRevert(abi.encodeWithSelector(IMakerLendingRouter.NotLoanBorrower.selector, secondBorrower, borrower));
        router.offrampToShares(loanId, marketIdA, 1);

        vm.prank(secondBorrower);
        vm.expectRevert(abi.encodeWithSelector(IMakerLendingRouter.NotLoanBorrower.selector, secondBorrower, borrower));
        router.offrampToUSDC(loanId, marketIdA, 1, alternateReceiver);
    }

    function test_ConstructorAndErc1155ReceiverBehavior() public {
        assertEq(router.usdc(), address(usdc));
        assertEq(router.eveUSDC(), address(eveUSDC));
        assertEq(router.vault(), address(vault));
        assertEq(router.lending(), address(lending));
        assertEq(router.diamond(), address(diamond));
        assertEq(router.defaultConditionalTokens(), address(conditionalTokens));
        assertTrue(conditionalTokens.isApprovedForAll(address(router), address(diamond)));

        vm.expectRevert(IMakerLendingRouter.ZeroAddress.selector);
        new MakerLendingRouter(
            address(0), address(eveUSDC), address(vault), address(lending), address(diamond), address(conditionalTokens)
        );

        assertEq(
            router.onERC1155Received(address(this), address(this), 1, 1, ""),
            IERC1155Receiver.onERC1155Received.selector
        );
        assertEq(
            router.onERC1155BatchReceived(address(this), address(this), new uint256[](0), new uint256[](0), ""),
            IERC1155Receiver.onERC1155BatchReceived.selector
        );
        assertTrue(router.supportsInterface(type(IERC165).interfaceId));
        assertTrue(router.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

    function test_EventEmissionsForOnrampAndOfframps() public {
        uint256 usdcAmount = 500e6;
        uint256 borrowAmount = 200e6;
        (uint256 expectedDebtPrincipal, uint256 expectedOriginationFee) =
            lending.previewBorrowTerms(vault.previewDeposit(usdcAmount * USDC_TO_EVEUSDC_SCALE), borrowAmount);
        uint256 expectedNetBorrowed = expectedDebtPrincipal - expectedOriginationFee;

        _seedUsdcAndApproveRouter(borrower, usdcAmount);
        vm.prank(borrower);
        vm.expectEmit(true, true, true, true, address(router));
        emit Onramped(
            borrower,
            borrower,
            marketIdA,
            usdcAmount,
            expectedNetBorrowed,
            expectedDebtPrincipal,
            expectedOriginationFee,
            1,
            uint128(expectedNetBorrowed),
            borrower
        );
        (uint256 loanId, uint128 initialShares) = router.onramp(usdcAmount, borrowAmount, 7 days, marketIdA, borrower);

        uint128 sharePositionAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 3);
        _approveRouterPositions(borrower);

        (uint256 mergeOut, uint256 repaymentAmount, uint256 excessEveUSDC) =
            router.previewOfframpToShares(loanId, marketIdA, sharePositionAmount);

        vm.prank(borrower);
        vm.expectEmit(true, true, false, true, address(router));
        emit OfframpedToShares(
            borrower, borrower, loanId, marketIdA, sharePositionAmount, mergeOut, repaymentAmount, excessEveUSDC
        );
        router.offrampToShares(loanId, marketIdA, sharePositionAmount);

        (loanId, initialShares) = _onramp(secondBorrower, usdcAmount, borrowAmount, 7 days, marketIdA, secondBorrower);
        uint128 usdcPositionAmount = _prepareRepayInventory(secondBorrower, marketIdA, loanId, initialShares, 4);
        _approveRouterPositions(secondBorrower);
        _notifyRevenue(60e6);

        (uint256 mergeOutUsdc, uint256 redeemedCollateralEveUSDC, uint256 repaymentAmountUsdc, uint256 expectedUsdcOut) =
            router.previewOfframpToUSDC(loanId, marketIdA, usdcPositionAmount);

        vm.prank(secondBorrower);
        vm.expectEmit(true, true, false, true, address(router));
        emit OfframpedToUSDC(
            secondBorrower,
            secondBorrower,
            loanId,
            marketIdA,
            usdcPositionAmount,
            mergeOutUsdc,
            repaymentAmountUsdc,
            redeemedCollateralEveUSDC,
            expectedUsdcOut,
            alternateReceiver
        );
        router.offrampToUSDC(loanId, marketIdA, usdcPositionAmount, alternateReceiver);
    }

    function _positionTokenTypeMismatch(bytes32 marketId) internal pure returns (bytes memory) {
        return _positionTokenTypeMismatch(marketId, LibEveMarket.PositionTokenType.CTF);
    }

    function _positionTokenTypeMismatch(bytes32 marketId, LibEveMarket.PositionTokenType expected)
        internal
        pure
        returns (bytes memory)
    {
        LibEveMarket.PositionTokenType actual = expected == LibEveMarket.PositionTokenType.CTF
            ? LibEveMarket.PositionTokenType.PARIMUTUEL
            : LibEveMarket.PositionTokenType.CTF;
        return
            abi.encodeWithSelector(Errors.PositionTokenTypeMismatch.selector, marketId, uint8(expected), uint8(actual));
    }

    function _createParimutuelMarket(string memory question) internal returns (bytes32 marketId) {
        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question,
                "router",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days),
                7 days
            );
    }
}
