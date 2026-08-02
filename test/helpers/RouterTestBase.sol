// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MakerLendingRouter} from "../../src/MakerLendingRouter.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {SEveUSDCLending} from "../../src/SEveUSDCLending.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {VaultFeeRoutingFixture} from "./VaultFeeRoutingFixture.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

abstract contract RouterTestBase is VaultFeeRoutingFixture {
    uint16 internal constant DEFAULT_MAX_LTV_BPS = 9_500;
    uint16 internal constant DEFAULT_ORIGINATION_FEE_BPS = 100;
    uint16 internal constant DEFAULT_EXTENSION_FEE_BPS = 50;
    uint16 internal constant DEFAULT_LENDING_FEE_RECIPIENT_BPS = 3_000;
    uint32 internal constant DEFAULT_MIN_DURATION = 1 days;
    uint32 internal constant DEFAULT_MAX_DURATION = 400 days;
    uint32 internal constant DEFAULT_GRACE_PERIOD = 1 days;

    SEveUSDCLending internal lending;
    MakerLendingRouter internal router;

    bytes32 internal marketIdA;
    bytes32 internal marketIdB;

    address internal borrower;
    address internal secondBorrower;
    address internal routerReceiver;
    address internal alternateReceiver;

    function setUp() public virtual override {
        super.setUp();

        borrower = makeAddr("router-borrower");
        secondBorrower = makeAddr("router-second-borrower");
        routerReceiver = makeAddr("router-receiver");
        alternateReceiver = makeAddr("router-alt-receiver");

        lending = new SEveUSDCLending(address(vault), address(eveUSDC), owner);

        vm.prank(owner);
        vault.setLendingContract(address(lending));

        vm.prank(owner);
        lending.setLendingConfig(
            DEFAULT_MAX_LTV_BPS,
            DEFAULT_ORIGINATION_FEE_BPS,
            DEFAULT_EXTENSION_FEE_BPS,
            DEFAULT_MIN_DURATION,
            DEFAULT_MAX_DURATION,
            DEFAULT_GRACE_PERIOD
        );
        vm.prank(owner);
        lending.setLendingFeeRecipientBps(DEFAULT_LENDING_FEE_RECIPIENT_BPS);

        router = new MakerLendingRouter(
            address(usdc),
            address(eveUSDC),
            address(vault),
            address(lending),
            address(diamond),
            address(conditionalTokens)
        );

        vm.prank(owner);
        lending.setApprovedRouter(address(router), true);

        (marketIdA,) = _createTradingMarket("router-market-a", 7 days);
        (marketIdB,) = _createTradingMarket("router-market-b", 8 days);
    }

    function _seedEveUSDC(address account, uint256 amount) internal {
        uint256 backing = (amount + USDC_TO_EVEUSDC_SCALE - 1) / USDC_TO_EVEUSDC_SCALE;
        usdc.mint(address(eveUSDC), backing);
        eveUSDC.mint(account, amount);
    }

    function _seedUsdcAndApproveRouter(address account, uint256 amount) internal {
        usdc.mint(account, amount);

        vm.prank(account);
        usdc.approve(address(router), type(uint256).max);
    }

    function _approveRouterPositions(address account) internal {
        vm.prank(account);
        conditionalTokens.setApprovalForAll(address(router), true);
    }

    function _approveDiamondForEveUSDC(address account) internal {
        vm.prank(account);
        eveUSDC.approve(address(diamond), type(uint256).max);
    }

    function _mintMatchedPositions(address account, bytes32 marketId, uint256 collateralAmount)
        internal
        returns (uint128 sharesMinted)
    {
        _seedEveUSDC(account, collateralAmount);
        _approveDiamondForEveUSDC(account);

        vm.prank(account);
        sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, uint128(collateralAmount));
    }

    function _onramp(
        address caller,
        uint256 usdcAmount,
        uint256 borrowAmount,
        uint256 durationSeconds,
        bytes32 marketId,
        address receiver
    ) internal returns (uint256 loanId, uint128 positionSharesMinted) {
        _seedUsdcAndApproveRouter(caller, usdcAmount);

        vm.prank(caller);
        return router.onramp(usdcAmount, borrowAmount, durationSeconds, marketId, receiver);
    }

    function _offrampToShares(address caller, uint256 loanId, bytes32 marketId, uint128 positionShareAmount) internal {
        vm.prank(caller);
        router.offrampToShares(loanId, marketId, positionShareAmount);
    }

    function _offrampToUSDC(
        address caller,
        uint256 loanId,
        bytes32 marketId,
        uint128 positionShareAmount,
        address receiver
    ) internal returns (uint256 usdcOut) {
        vm.prank(caller);
        return router.offrampToUSDC(loanId, marketId, positionShareAmount, receiver);
    }

    function _notifyRevenue(uint256 assets) internal {
        _seedEveUSDC(address(diamond), assets);

        vm.prank(address(diamond));
        eveUSDC.approve(address(vault), assets);

        vm.prank(address(diamond));
        vault.notifyRevenue(assets);
    }

    function _seedRouterShares(uint256 assets) internal returns (uint256 shares) {
        _seedEveUSDC(address(router), assets);

        vm.prank(address(router));
        eveUSDC.approve(address(vault), type(uint256).max);

        vm.prank(address(router));
        shares = vault.deposit(assets, address(router));

        vm.prank(address(router));
        vault.approve(address(lending), type(uint256).max);
    }

    function _seedRouterDebtAndApprove(uint256 amount) internal {
        _seedEveUSDC(address(router), amount);

        vm.prank(address(router));
        eveUSDC.approve(address(lending), type(uint256).max);
    }

    function _routerBorrowFor(
        uint256 collateralShares,
        uint256 durationSeconds,
        uint256 borrowAmount,
        address recipient,
        address onBehalfOf
    ) internal returns (uint256 loanId) {
        vm.prank(address(router));
        loanId = lending.borrowFor(collateralShares, durationSeconds, borrowAmount, recipient, onBehalfOf);
    }

    function _routerRepayFor(uint256 loanId, bool redeemUnderlying, address recipient) internal {
        vm.prank(address(router));
        lending.repayFor(loanId, redeemUnderlying, recipient);
    }

    function _positionBalances(address account, bytes32 marketId)
        internal
        view
        returns (uint256 yesBalance, uint256 noBalance)
    {
        MarketFactoryTypes.MarketInfo memory market = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketId);
        yesBalance = IERC1155(market.positionToken).balanceOf(account, market.yesPositionId);
        noBalance = IERC1155(market.positionToken).balanceOf(account, market.noPositionId);
    }

    function _assertRouterClean(bytes32 marketId) internal view {
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(eveUSDC.balanceOf(address(router)), 0);
        assertEq(vault.balanceOf(address(router)), 0);

        (uint256 yesBalance, uint256 noBalance) = _positionBalances(address(router), marketId);
        assertEq(yesBalance, 0);
        assertEq(noBalance, 0);
    }

    function _maxBorrowForUsdc(uint256 usdcAmount) internal view returns (uint256 maxBorrow) {
        maxBorrow = lending.maxBorrowForShares(vault.previewDeposit(usdcAmount * USDC_TO_EVEUSDC_SCALE));
    }

    function _requiredPositionShares(uint256 loanId) internal view returns (uint128 sharesRequired) {
        uint256 repaymentAmount = lending.previewRequiredRepayment(loanId);
        sharesRequired = uint128(repaymentAmount);
    }

    function _boundBorrow(uint256 seed, uint256 maxBorrow) internal pure returns (uint256 borrowAmount) {
        borrowAmount = bound(seed, USDC_UNIT, maxBorrow);
        if (borrowAmount == 0) {
            borrowAmount = USDC_UNIT;
        }
    }

    function _prepareRepayInventory(
        address account,
        bytes32 marketId,
        uint256 loanId,
        uint128 existingShares,
        uint128 extraShares
    ) internal returns (uint128 positionShareAmount) {
        positionShareAmount = _requiredPositionShares(loanId) + extraShares;

        if (positionShareAmount > existingShares) {
            _mintMatchedPositions(account, marketId, uint256(positionShareAmount - existingShares));
        }
    }

    function _loanDebt(uint256 loanId) internal view returns (uint256) {
        return uint256(lending.loanState(loanId).debtPrincipal);
    }

    function _netBorrowed(uint256 debtPrincipal, uint256 originationFee) internal pure returns (uint256) {
        return debtPrincipal - originationFee;
    }

    function _loanCollateral(uint256 loanId) internal view returns (uint256) {
        return uint256(lending.loanState(loanId).collateralShares);
    }

    function _loanBorrower(uint256 loanId) internal view returns (address) {
        return lending.loanState(loanId).borrower;
    }

    function _loanState(uint256 loanId) internal view returns (ISEveUSDCLending.Loan memory) {
        return lending.loanState(loanId);
    }

    function _repayMarket(bool useSecondMarket) internal view returns (bytes32) {
        return useSecondMarket ? marketIdB : marketIdA;
    }
}
