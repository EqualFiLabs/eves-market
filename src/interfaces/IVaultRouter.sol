// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IVaultRouter {
    error ZeroAmount();
    error InvalidReceiver(address receiver);
    error ResidualRouterBalance(address token, uint256 expectedBalance, uint256 actualBalance);
    error ResidualRouterNativeBalance(uint256 expectedBalance, uint256 actualBalance);
    error CollateralProfileNotFound(uint8 profileId);
    error CollateralProfileDisabled(uint8 profileId);
    error CollateralProfileWrapperMissing(uint8 profileId);
    error CollateralProfileWrapperMismatch(uint8 profileId, address expectedWrapper, address actualWrapper);

    function wrapAndDeposit(uint256 usdcAmount, address receiver) external returns (uint256 shares);

    function redeemAndUnwrap(uint256 shares, address receiver) external returns (uint256 usdcOut);

    function wrapETHToEveETH(uint8 collateralProfileId, address receiver)
        external
        payable
        returns (uint256 eveETHMinted);
}
