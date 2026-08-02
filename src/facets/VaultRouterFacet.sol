// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEveUSDC} from "../interfaces/IEveUSDC.sol";
import {IEveETH} from "../interfaces/IEveETH.sol";
import {ISEveUSDCVault} from "../interfaces/ISEveUSDCVault.sol";
import {IVaultRouter} from "../interfaces/IVaultRouter.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibRouter} from "../libraries/LibRouter.sol";

contract VaultRouterFacet is IVaultRouter {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function wrapAndDeposit(uint256 usdcAmount, address receiver)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (usdcAmount == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        (address usdc, address eveUSDC, address vault) = _routerAddresses();
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(address(this));
        uint256 eveUsdcBalanceBefore = IERC20(eveUSDC).balanceOf(address(this));
        uint256 vaultBalanceBefore = IERC20(vault).balanceOf(address(this));

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);
        IERC20(usdc).forceApprove(eveUSDC, usdcAmount);

        uint256 wrapped = IEveUSDC(eveUSDC).wrap(usdcAmount, address(this));
        IERC20(usdc).forceApprove(eveUSDC, 0);

        IERC20(eveUSDC).forceApprove(vault, wrapped);
        shares = ISEveUSDCVault(vault).deposit(wrapped, receiver);
        IERC20(eveUSDC).forceApprove(vault, 0);

        LibRouter.assertBalanceRestored(usdc, usdcBalanceBefore);
        LibRouter.assertBalanceRestored(eveUSDC, eveUsdcBalanceBefore);
        LibRouter.assertBalanceRestored(vault, vaultBalanceBefore);
    }

    function redeemAndUnwrap(uint256 shares, address receiver)
        external
        override
        nonReentrant
        returns (uint256 usdcOut)
    {
        if (shares == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        (address usdc, address eveUSDC, address vault) = _routerAddresses();
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(address(this));
        uint256 eveUsdcBalanceBefore = IERC20(eveUSDC).balanceOf(address(this));
        uint256 vaultBalanceBefore = IERC20(vault).balanceOf(address(this));

        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);

        uint256 assets = ISEveUSDCVault(vault).redeem(shares, address(this), address(this));
        usdcOut = LibRouter.unwrapConvertibleEveUSDC(eveUSDC, assets, receiver);

        LibRouter.assertBalanceRestored(usdc, usdcBalanceBefore);
        LibRouter.assertBalanceRestored(eveUSDC, eveUsdcBalanceBefore);
        LibRouter.assertBalanceRestored(vault, vaultBalanceBefore);
    }

    function wrapETHToEveETH(uint8 collateralProfileId, address receiver)
        external
        payable
        override
        nonReentrant
        returns (uint256 eveETHMinted)
    {
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        uint256 nativeBalanceBefore = address(this).balance - msg.value;
        (address eveETH, address weth) = _eveEthProfileAddresses(collateralProfileId);
        uint256 wethBalanceBefore = IERC20(weth).balanceOf(address(this));
        uint256 eveEthBalanceBefore = IERC20(eveETH).balanceOf(address(this));

        IWETH9(weth).deposit{value: msg.value}();
        IERC20(weth).forceApprove(eveETH, msg.value);
        eveETHMinted = IEveETH(eveETH).wrap(msg.value, receiver);
        IERC20(weth).forceApprove(eveETH, 0);

        LibRouter.assertNativeBalanceRestored(nativeBalanceBefore);
        LibRouter.assertBalanceRestored(weth, wethBalanceBefore);
        LibRouter.assertBalanceRestored(eveETH, eveEthBalanceBefore);
    }

    function _routerAddresses() internal view returns (address usdc, address eveUSDC, address vault) {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        eveUSDC = config.collateralToken;
        vault = config.stakingVault;

        if (eveUSDC == address(0) || vault == address(0)) {
            revert ZeroAmount();
        }

        usdc = IEveUSDC(eveUSDC).usdc();
    }

    function _eveEthProfileAddresses(uint8 collateralProfileId) internal view returns (address eveETH, address weth) {
        LibEveMarket.CollateralProfile storage profile = LibEveMarket.store().collateralProfiles[collateralProfileId];
        eveETH = profile.collateralToken;
        weth = profile.wrapperToken;

        if (eveETH == address(0)) {
            revert CollateralProfileNotFound(collateralProfileId);
        }
        if (!profile.enabled) {
            revert CollateralProfileDisabled(collateralProfileId);
        }
        if (weth == address(0)) {
            revert CollateralProfileWrapperMissing(collateralProfileId);
        }

        address eveEthWeth = IEveETH(eveETH).weth();
        if (eveEthWeth != weth) {
            revert CollateralProfileWrapperMismatch(collateralProfileId, eveEthWeth, weth);
        }
    }
}
