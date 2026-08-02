// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library LibEveUSDCUnits {
    uint256 internal constant USDC_TO_EVEUSDC_SCALE = 1e12;

    function toEveUSDC(uint256 usdcAmount) internal pure returns (uint256 eveUSDCAmount) {
        eveUSDCAmount = usdcAmount * USDC_TO_EVEUSDC_SCALE;
    }

    function convertibleEveUSDC(uint256 eveUSDCAmount) internal pure returns (uint256 convertibleAmount) {
        convertibleAmount = (eveUSDCAmount / USDC_TO_EVEUSDC_SCALE) * USDC_TO_EVEUSDC_SCALE;
    }

    function eveUSDCDust(uint256 eveUSDCAmount) internal pure returns (uint256 dust) {
        dust = eveUSDCAmount % USDC_TO_EVEUSDC_SCALE;
    }
}
