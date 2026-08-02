// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {IEveUSDC} from "./interfaces/IEveUSDC.sol";
import {IGnosisConditionalTokens} from "./interfaces/IGnosisConditionalTokens.sol";
import {ICurveInventoryFacet} from "./interfaces/ICurveInventoryFacet.sol";
import {IMakerLendingRouter} from "./interfaces/IMakerLendingRouter.sol";
import {IMarketFactoryFacet} from "./interfaces/IMarketFactoryFacet.sol";
import {IParimutuelFacet} from "./interfaces/IParimutuelFacet.sol";
import {ISEveUSDCLending} from "./interfaces/ISEveUSDCLending.sol";
import {ISEveUSDCVault} from "./interfaces/ISEveUSDCVault.sol";
import {Errors} from "./libraries/Errors.sol";
import {LibEveUSDCUnits} from "./libraries/LibEveUSDCUnits.sol";
import {LibEveMarket} from "./libraries/LibEveMarket.sol";
import {LibRouter} from "./libraries/LibRouter.sol";
import {MarketFactoryTypes} from "./types/MarketFactoryTypes.sol";

/// @notice Standalone maker-lending router for deposit-borrow-position workflows kept outside the diamond.
/// @dev Deprecated directionally; retained until the senior margin pool replaces vault-share lending.
contract MakerLendingRouter is ReentrancyGuard, IERC1155Receiver, IMakerLendingRouter {
    using SafeERC20 for IERC20;

    struct OnrampSnapshot {
        uint256 vaultSharesMinted;
        uint256 debtPrincipal;
        uint256 originationFee;
    }

    struct OfframpSnapshot {
        uint256 mergeEveUSDCOut;
        uint256 repaymentAmount;
        uint256 redeemedCollateralEveUSDC;
    }

    struct ResidualSnapshot {
        uint256 usdcBalance;
        uint256 eveUSDCBalance;
        uint256 vaultBalance;
        uint256 yesBalance;
        uint256 noBalance;
    }

    address public immutable owner;
    address public immutable usdc;
    address public immutable eveUSDC;
    address public immutable vault;
    address public immutable lending;
    address public immutable diamond;
    address public immutable defaultConditionalTokens;

    constructor(
        address usdc_,
        address eveUSDC_,
        address vault_,
        address lending_,
        address diamond_,
        address defaultConditionalTokens_
    ) {
        if (
            usdc_ == address(0) || eveUSDC_ == address(0) || vault_ == address(0) || lending_ == address(0)
                || diamond_ == address(0) || defaultConditionalTokens_ == address(0)
        ) {
            revert ZeroAddress();
        }

        owner = msg.sender;
        usdc = usdc_;
        eveUSDC = eveUSDC_;
        vault = vault_;
        lending = lending_;
        diamond = diamond_;
        defaultConditionalTokens = defaultConditionalTokens_;

        IGnosisConditionalTokens(defaultConditionalTokens_).setApprovalForAll(diamond_, true);
    }

    function onramp(
        uint256 usdcAmount,
        uint256 borrowAmount,
        uint256 durationSeconds,
        bytes32 marketId,
        address receiver
    ) external override nonReentrant returns (uint256 loanId, uint128 positionSharesMinted) {
        OnrampSnapshot memory snapshot;

        if (usdcAmount == 0 || borrowAmount == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        _validatedMarket(marketId);
        ResidualSnapshot memory residuals = _residualSnapshot(marketId);

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);
        snapshot.vaultSharesMinted = _wrapUSDCAndDepositToVault(usdcAmount);

        IERC20(vault).forceApprove(lending, snapshot.vaultSharesMinted);
        (snapshot.debtPrincipal, snapshot.originationFee) =
            ISEveUSDCLending(lending).previewBorrowTerms(snapshot.vaultSharesMinted, borrowAmount);
        uint256 netBorrowed = _netBorrowed(snapshot);
        loanId = ISEveUSDCLending(lending)
            .borrowFor(snapshot.vaultSharesMinted, durationSeconds, borrowAmount, address(this), msg.sender);

        IERC20(eveUSDC).forceApprove(diamond, netBorrowed);
        positionSharesMinted = ICurveInventoryFacet(diamond).splitInventory(marketId, SafeCast.toUint128(netBorrowed));

        {
            MarketFactoryTypes.MarketInfo memory market = IMarketFactoryFacet(diamond).getMarketInfo(marketId);
            IGnosisConditionalTokens positionToken = IGnosisConditionalTokens(market.positionToken);
            positionToken.safeTransferFrom(address(this), receiver, market.yesPositionId, positionSharesMinted, "");
            positionToken.safeTransferFrom(address(this), receiver, market.noPositionId, positionSharesMinted, "");
        }

        _assertResidualBalancesRestored(marketId, residuals);

        _emitOnramped(marketId, usdcAmount, snapshot, loanId, positionSharesMinted, receiver);
    }

    function onrampParimutuel(
        uint256 usdcAmount,
        uint256 borrowAmount,
        uint256 durationSeconds,
        bytes32 marketId,
        bool isYes,
        uint128 minSharesOut,
        address receiver
    ) external override nonReentrant returns (uint256 loanId, uint128 sharesMinted) {
        OnrampSnapshot memory snapshot;

        if (usdcAmount == 0 || borrowAmount == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        _validatedParimutuelMarket(marketId);
        ResidualSnapshot memory residuals = _residualSnapshot(marketId);

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);
        snapshot.vaultSharesMinted = _wrapUSDCAndDepositToVault(usdcAmount);

        IERC20(vault).forceApprove(lending, snapshot.vaultSharesMinted);
        (snapshot.debtPrincipal, snapshot.originationFee) =
            ISEveUSDCLending(lending).previewBorrowTerms(snapshot.vaultSharesMinted, borrowAmount);
        uint256 netBorrowed = _netBorrowed(snapshot);
        loanId = ISEveUSDCLending(lending)
            .borrowFor(snapshot.vaultSharesMinted, durationSeconds, borrowAmount, address(this), msg.sender);

        IERC20(eveUSDC).forceApprove(diamond, netBorrowed);
        sharesMinted = IParimutuelFacet(diamond)
            .buyShares(marketId, isYes, SafeCast.toUint128(netBorrowed), receiver, minSharesOut);

        _assertResidualBalancesRestored(marketId, residuals);

        _emitParimutuelOnramped(marketId, isYes, usdcAmount, snapshot, loanId, sharesMinted, receiver);
    }

    function offrampToShares(uint256 loanId, bytes32 marketId, uint128 positionShareAmount)
        external
        override
        nonReentrant
    {
        OfframpSnapshot memory snapshot;
        address borrower;

        if (positionShareAmount == 0) {
            revert ZeroAmount();
        }

        ResidualSnapshot memory residuals = _residualSnapshot(marketId);

        {
            ISEveUSDCLending.Loan memory loan = ISEveUSDCLending(lending).loanState(loanId);
            borrower = loan.borrower;
            _enforceLoanBorrower(borrower);
            MarketFactoryTypes.MarketInfo memory market = _validatedMarket(marketId);
            IGnosisConditionalTokens positionToken = IGnosisConditionalTokens(market.positionToken);

            positionToken.safeTransferFrom(msg.sender, address(this), market.yesPositionId, positionShareAmount, "");
            positionToken.safeTransferFrom(msg.sender, address(this), market.noPositionId, positionShareAmount, "");

            _ensurePositionTokenApproval(market.positionToken);
            snapshot.mergeEveUSDCOut = ICurveInventoryFacet(diamond).mergeInventory(marketId, positionShareAmount);
            snapshot.repaymentAmount = uint256(loan.debtPrincipal);
        }

        IERC20(eveUSDC).forceApprove(lending, snapshot.repaymentAmount);
        ISEveUSDCLending(lending).repayFor(loanId, false, address(0));

        uint256 excessEveUSDC = LibRouter.balanceDelta(eveUSDC, residuals.eveUSDCBalance);
        if (excessEveUSDC != 0) {
            IERC20(eveUSDC).safeTransfer(msg.sender, excessEveUSDC);
        }

        _assertResidualBalancesRestored(marketId, residuals);

        emit OfframpedToShares(
            msg.sender,
            borrower,
            loanId,
            marketId,
            positionShareAmount,
            snapshot.mergeEveUSDCOut,
            snapshot.repaymentAmount,
            excessEveUSDC
        );
    }

    function offrampToUSDC(uint256 loanId, bytes32 marketId, uint128 positionShareAmount, address receiver)
        external
        override
        nonReentrant
        returns (uint256 usdcOut)
    {
        OfframpSnapshot memory snapshot;
        address borrower;

        if (positionShareAmount == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        ResidualSnapshot memory residuals = _residualSnapshot(marketId);

        {
            ISEveUSDCLending.Loan memory loan = ISEveUSDCLending(lending).loanState(loanId);
            borrower = loan.borrower;
            _enforceLoanBorrower(borrower);
            MarketFactoryTypes.MarketInfo memory market = _validatedMarket(marketId);
            IGnosisConditionalTokens positionToken = IGnosisConditionalTokens(market.positionToken);

            positionToken.safeTransferFrom(msg.sender, address(this), market.yesPositionId, positionShareAmount, "");
            positionToken.safeTransferFrom(msg.sender, address(this), market.noPositionId, positionShareAmount, "");

            _ensurePositionTokenApproval(market.positionToken);
            snapshot.mergeEveUSDCOut = ICurveInventoryFacet(diamond).mergeInventory(marketId, positionShareAmount);
            snapshot.repaymentAmount = uint256(loan.debtPrincipal);
            snapshot.redeemedCollateralEveUSDC = ISEveUSDCVault(vault).previewRedeem(uint256(loan.collateralShares));
        }

        IERC20(eveUSDC).forceApprove(lending, snapshot.repaymentAmount);
        ISEveUSDCLending(lending).repayFor(loanId, true, address(this));

        usdcOut = LibRouter.unwrapConvertibleEveUSDC(
            eveUSDC, LibRouter.balanceDelta(eveUSDC, residuals.eveUSDCBalance), receiver
        );

        _assertResidualBalancesRestored(marketId, residuals);

        emit OfframpedToUSDC(
            msg.sender,
            borrower,
            loanId,
            marketId,
            positionShareAmount,
            snapshot.mergeEveUSDCOut,
            snapshot.repaymentAmount,
            snapshot.redeemedCollateralEveUSDC,
            usdcOut,
            receiver
        );
    }

    function previewOnramp(uint256 usdcAmount, uint256 borrowAmount, bytes32 marketId)
        external
        view
        override
        returns (uint256 vaultSharesMinted, uint128 positionSharesMinted, uint256 originationFee, uint256 debtPrincipal)
    {
        _validatedMarket(marketId);

        vaultSharesMinted = ISEveUSDCVault(vault).previewDeposit(LibEveUSDCUnits.toEveUSDC(usdcAmount));
        (debtPrincipal, originationFee) = ISEveUSDCLending(lending).previewBorrowTerms(vaultSharesMinted, borrowAmount);
        positionSharesMinted = SafeCast.toUint128(debtPrincipal - originationFee);
    }

    function previewParimutuelOnramp(uint256 usdcAmount, uint256 borrowAmount, bytes32 marketId)
        external
        view
        override
        returns (
            uint256 vaultSharesMinted,
            uint128 sharesMinted,
            uint128 entryFee,
            uint256 originationFee,
            uint256 debtPrincipal
        )
    {
        _validatedParimutuelMarket(marketId);

        vaultSharesMinted = ISEveUSDCVault(vault).previewDeposit(LibEveUSDCUnits.toEveUSDC(usdcAmount));
        (debtPrincipal, originationFee) = ISEveUSDCLending(lending).previewBorrowTerms(vaultSharesMinted, borrowAmount);
        uint256 netBorrowed = debtPrincipal - originationFee;
        (uint128 totalFee,,,, uint128 netShares) =
            IParimutuelFacet(diamond).previewEntryFee(marketId, SafeCast.toUint128(netBorrowed));
        (uint256 multiplierBps,) = IParimutuelFacet(diamond).getEpochMultiplier(marketId);
        sharesMinted = SafeCast.toUint128((uint256(netShares) * multiplierBps) / 10_000);
        entryFee = totalFee;
    }

    function previewOfframpToShares(uint256 loanId, bytes32 marketId, uint128 positionShareAmount)
        external
        view
        override
        returns (uint256 mergeEveUSDCOut, uint256 repaymentAmount, uint256 excessEveUSDC)
    {
        _validatedMarket(marketId);

        mergeEveUSDCOut = positionShareAmount;
        repaymentAmount = ISEveUSDCLending(lending).previewRequiredRepayment(loanId);
        excessEveUSDC = mergeEveUSDCOut > repaymentAmount ? mergeEveUSDCOut - repaymentAmount : 0;
    }

    function previewOfframpToUSDC(uint256 loanId, bytes32 marketId, uint128 positionShareAmount)
        external
        view
        override
        returns (uint256 mergeEveUSDCOut, uint256 redeemedCollateralEveUSDC, uint256 repaymentAmount, uint256 usdcOut)
    {
        _validatedMarket(marketId);
        ISEveUSDCLending.Loan memory loan = ISEveUSDCLending(lending).loanState(loanId);

        mergeEveUSDCOut = positionShareAmount;
        redeemedCollateralEveUSDC = ISEveUSDCVault(vault).previewRedeem(uint256(loan.collateralShares));
        repaymentAmount = ISEveUSDCLending(lending).previewRequiredRepayment(loanId);

        if (mergeEveUSDCOut >= repaymentAmount) {
            uint256 eveUSDCOut = mergeEveUSDCOut - repaymentAmount + redeemedCollateralEveUSDC;
            usdcOut = LibEveUSDCUnits.convertibleEveUSDC(eveUSDCOut) / LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE;
        }
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function rescueERC20(address token, address receiver, uint256 amount) external override nonReentrant {
        _enforceOwner();
        LibRouter.requireReceiver(receiver);
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC20(token).safeTransfer(receiver, amount);
        emit ERC20Rescued(token, receiver, amount);
    }

    function rescueERC1155(address token, uint256 id, address receiver, uint256 amount) external override nonReentrant {
        _enforceOwner();
        LibRouter.requireReceiver(receiver);
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC1155(token).safeTransferFrom(address(this), receiver, id, amount, "");
        emit ERC1155Rescued(token, id, receiver, amount);
    }

    function _validatedMarket(bytes32 marketId) internal view returns (MarketFactoryTypes.MarketInfo memory market) {
        market = IMarketFactoryFacet(diamond).getMarketInfo(marketId);
        if (market.positionTokenType != uint8(LibEveMarket.PositionTokenType.CTF)) {
            revert Errors.PositionTokenTypeMismatch(
                marketId, uint8(LibEveMarket.PositionTokenType.CTF), market.positionTokenType
            );
        }
        if (market.collateralToken != eveUSDC) {
            revert InvalidMarketCollateral(market.collateralToken, eveUSDC);
        }
    }

    function _validatedParimutuelMarket(bytes32 marketId)
        internal
        view
        returns (MarketFactoryTypes.MarketInfo memory market)
    {
        market = IMarketFactoryFacet(diamond).getMarketInfo(marketId);
        if (market.positionTokenType != uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)) {
            revert Errors.PositionTokenTypeMismatch(
                marketId, uint8(LibEveMarket.PositionTokenType.PARIMUTUEL), market.positionTokenType
            );
        }
        if (market.collateralToken != eveUSDC) {
            revert InvalidMarketCollateral(market.collateralToken, eveUSDC);
        }
    }

    function _enforceLoanBorrower(address borrower) internal view {
        if (msg.sender != borrower) {
            revert NotLoanBorrower(msg.sender, borrower);
        }
    }

    function _netBorrowed(OnrampSnapshot memory snapshot) internal pure returns (uint256) {
        return snapshot.debtPrincipal - snapshot.originationFee;
    }

    function _emitOnramped(
        bytes32 marketId,
        uint256 usdcAmount,
        OnrampSnapshot memory snapshot,
        uint256 loanId,
        uint128 positionSharesMinted,
        address receiver
    ) internal {
        emit Onramped(
            msg.sender,
            msg.sender,
            marketId,
            usdcAmount,
            _netBorrowed(snapshot),
            snapshot.debtPrincipal,
            snapshot.originationFee,
            loanId,
            positionSharesMinted,
            receiver
        );
    }

    function _emitParimutuelOnramped(
        bytes32 marketId,
        bool isYes,
        uint256 usdcAmount,
        OnrampSnapshot memory snapshot,
        uint256 loanId,
        uint128 sharesMinted,
        address receiver
    ) internal {
        emit ParimutuelOnramped(
            msg.sender,
            msg.sender,
            marketId,
            isYes,
            usdcAmount,
            _netBorrowed(snapshot),
            snapshot.debtPrincipal,
            snapshot.originationFee,
            loanId,
            sharesMinted,
            receiver
        );
    }

    function _residualSnapshot(bytes32 marketId) internal view returns (ResidualSnapshot memory snapshot) {
        MarketFactoryTypes.MarketInfo memory market = IMarketFactoryFacet(diamond).getMarketInfo(marketId);
        snapshot = ResidualSnapshot({
            usdcBalance: IERC20(usdc).balanceOf(address(this)),
            eveUSDCBalance: IERC20(eveUSDC).balanceOf(address(this)),
            vaultBalance: IERC20(vault).balanceOf(address(this)),
            yesBalance: IGnosisConditionalTokens(market.positionToken).balanceOf(address(this), market.yesPositionId),
            noBalance: IGnosisConditionalTokens(market.positionToken).balanceOf(address(this), market.noPositionId)
        });
    }

    function _assertResidualBalancesRestored(bytes32 marketId, ResidualSnapshot memory snapshot) internal view {
        MarketFactoryTypes.MarketInfo memory market = IMarketFactoryFacet(diamond).getMarketInfo(marketId);
        LibRouter.assertBalanceRestored(usdc, snapshot.usdcBalance);
        LibRouter.assertBalanceRestored(eveUSDC, snapshot.eveUSDCBalance);
        LibRouter.assertBalanceRestored(vault, snapshot.vaultBalance);
        LibRouter.assertERC1155BalanceRestored(market.positionToken, market.yesPositionId, snapshot.yesBalance);
        LibRouter.assertERC1155BalanceRestored(market.positionToken, market.noPositionId, snapshot.noBalance);
    }

    function _wrapUSDCAndDepositToVault(uint256 usdcAmount) internal returns (uint256 shares) {
        IERC20(usdc).forceApprove(eveUSDC, usdcAmount);
        uint256 wrapped = IEveUSDC(eveUSDC).wrap(usdcAmount, address(this));
        IERC20(usdc).forceApprove(eveUSDC, 0);

        IERC20(eveUSDC).forceApprove(vault, wrapped);
        shares = ISEveUSDCVault(vault).deposit(wrapped, address(this));
        IERC20(eveUSDC).forceApprove(vault, 0);
    }

    function _ensurePositionTokenApproval(address positionToken) internal {
        IGnosisConditionalTokens token = IGnosisConditionalTokens(positionToken);
        if (!token.isApprovedForAll(address(this), diamond)) {
            token.setApprovalForAll(diamond, true);
        }
    }

    function _enforceOwner() internal view {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
    }
}
