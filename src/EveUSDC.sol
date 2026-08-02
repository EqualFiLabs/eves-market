// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEveUSDC} from "./interfaces/IEveUSDC.sol";
import {LibEveUSDCUnits} from "./libraries/LibEveUSDCUnits.sol";

contract EveUSDC is ERC20, IEveUSDC {
    using SafeERC20 for IERC20;

    uint256 public constant USDC_TO_EVEUSDC_SCALE = LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE;

    address public immutable override usdc;
    address public immutable override onramp;
    address public immutable override offramp;

    constructor(address usdc_, address onramp_, address offramp_) ERC20("eveUSDC", "eveUSDC") {
        usdc = usdc_;
        onramp = onramp_;
        offramp = offramp_;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function wrap(uint256 usdcAmount, address to) external returns (uint256 eveUSDCMinted) {
        if (usdcAmount == 0) {
            revert ZeroAmount();
        }

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);
        eveUSDCMinted = LibEveUSDCUnits.toEveUSDC(usdcAmount);
        _mint(to, eveUSDCMinted);

        emit Wrapped(msg.sender, to, usdcAmount);

        return eveUSDCMinted;
    }

    function unwrap(uint256 eveUSDCAmount, address to) external returns (uint256 usdcOut) {
        if (eveUSDCAmount == 0) {
            revert ZeroAmount();
        }
        if (LibEveUSDCUnits.eveUSDCDust(eveUSDCAmount) != 0) {
            revert NonConvertibleEveUSDC(eveUSDCAmount);
        }

        usdcOut = eveUSDCAmount / LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE;
        _burn(msg.sender, eveUSDCAmount);
        IERC20(usdc).safeTransfer(to, usdcOut);

        emit Unwrapped(msg.sender, to, usdcOut);

        return usdcOut;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != onramp) {
            revert UnauthorizedMinter(msg.sender);
        }

        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != offramp) {
            revert UnauthorizedBurner(msg.sender);
        }

        _burn(from, amount);
    }
}
