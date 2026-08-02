// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC165} from "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IEveRiskShares} from "./interfaces/IEveRiskShares.sol";
import {IEveUSD} from "./interfaces/IEveUSD.sol";
import {IEveUSDPool} from "./interfaces/IEveUSDPool.sol";
import {IEveUSDRouter} from "./interfaces/IEveUSDRouter.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract EveUSDRouter is IEveUSDRouter, IERC1155Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct ResidualSnapshot {
        uint256 wethBalance;
        uint256 eveUSDBalance;
        uint256 riskShareBalance;
        uint256 nativeBalance;
    }

    address public immutable pool;
    address public immutable weth;
    address public immutable eveUSD;
    address public immutable evRisk;

    constructor(address pool_, address weth_, address eveUSD_, address evRisk_) {
        _requireContract(pool_);
        _requireContract(weth_);
        _requireContract(eveUSD_);
        _requireContract(evRisk_);

        _requirePoolAsset(weth_, IEveUSDPool(pool_).weth());
        _requirePoolAsset(eveUSD_, IEveUSDPool(pool_).eveUSD());
        _requirePoolAsset(evRisk_, IEveUSDPool(pool_).evRisk());
        _requireTokenPool(eveUSD_, pool_, IEveUSD(eveUSD_).pool());
        _requireTokenPool(evRisk_, pool_, IEveRiskShares(evRisk_).pool());

        pool = pool_;
        weth = weth_;
        eveUSD = eveUSD_;
        evRisk = evRisk_;
    }

    receive() external payable {
        if (msg.sender != weth) {
            revert UnexpectedETH(msg.sender);
        }
    }

    function depositETH(address eveUSDReceiver, address shareReceiver, uint256 minEveUSD, uint256 minShares)
        external
        payable
        nonReentrant
        returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted)
    {
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        _requireReceiver(eveUSDReceiver);
        _requireReceiver(shareReceiver);

        IEveUSDPool.DepositPreview memory preview = _requireDepositMinimums(msg.value, minEveUSD, minShares);
        ResidualSnapshot memory residuals = _residualSnapshot(preview.seriesId);

        IWETH9(weth).deposit{value: msg.value}();
        IERC20(weth).forceApprove(pool, msg.value);

        (seriesId, eveUSDMinted, sharesMinted) =
            IEveUSDPool(pool).depositWETH(msg.value, eveUSDReceiver, shareReceiver);
        _requireMinimum(eveUSDMinted, minEveUSD);
        _requireMinimum(sharesMinted, minShares);
        IERC20(weth).forceApprove(pool, 0);
        residuals.nativeBalance -= msg.value;
        _assertResidualBalancesRestored(seriesId, residuals);

        emit ETHDeposited(msg.sender, eveUSDReceiver, shareReceiver, seriesId, msg.value, eveUSDMinted, sharesMinted);
    }

    function depositWETH(
        uint256 wethAmount,
        address eveUSDReceiver,
        address shareReceiver,
        uint256 minEveUSD,
        uint256 minShares
    ) external nonReentrant returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) {
        if (wethAmount == 0) {
            revert ZeroAmount();
        }
        _requireReceiver(eveUSDReceiver);
        _requireReceiver(shareReceiver);

        IEveUSDPool.DepositPreview memory preview = _requireDepositMinimums(wethAmount, minEveUSD, minShares);
        ResidualSnapshot memory residuals = _residualSnapshot(preview.seriesId);

        IERC20(weth).safeTransferFrom(msg.sender, address(this), wethAmount);
        IERC20(weth).forceApprove(pool, wethAmount);

        (seriesId, eveUSDMinted, sharesMinted) =
            IEveUSDPool(pool).depositWETH(wethAmount, eveUSDReceiver, shareReceiver);
        _requireMinimum(eveUSDMinted, minEveUSD);
        _requireMinimum(sharesMinted, minShares);
        IERC20(weth).forceApprove(pool, 0);
        _assertResidualBalancesRestored(seriesId, residuals);

        emit WETHDeposited(msg.sender, eveUSDReceiver, shareReceiver, seriesId, wethAmount, eveUSDMinted, sharesMinted);
    }

    function recombineToWETH(
        uint256 seriesId,
        uint256 eveUSDAmount,
        uint256 maxSharesIn,
        address receiver,
        uint256 minWETHOut
    ) external nonReentrant returns (uint256 wethOut) {
        _requireReceiver(receiver);

        IEveUSDPool.RedemptionPreview memory preview =
            _requireRecombinationBounds(seriesId, eveUSDAmount, maxSharesIn, minWETHOut);
        ResidualSnapshot memory residuals = _residualSnapshot(seriesId);
        _pullRecombinationTokens(seriesId, eveUSDAmount, preview.sharesBurned);

        wethOut = IEveUSDPool(pool).recombine(seriesId, eveUSDAmount, preview.sharesBurned, receiver);
        _requireMinimum(wethOut, minWETHOut);
        _assertResidualBalancesRestored(seriesId, residuals);

        emit RecombinedToWETH(msg.sender, receiver, seriesId, eveUSDAmount, preview.sharesBurned, wethOut);
    }

    function recombineToETH(
        uint256 seriesId,
        uint256 eveUSDAmount,
        uint256 maxSharesIn,
        address receiver,
        uint256 minETHOut
    ) external nonReentrant returns (uint256 ethOut) {
        _requireReceiver(receiver);

        IEveUSDPool.RedemptionPreview memory preview =
            _requireRecombinationBounds(seriesId, eveUSDAmount, maxSharesIn, minETHOut);
        ResidualSnapshot memory residuals = _residualSnapshot(seriesId);
        _pullRecombinationTokens(seriesId, eveUSDAmount, preview.sharesBurned);

        ethOut = IEveUSDPool(pool).recombine(seriesId, eveUSDAmount, preview.sharesBurned, address(this));
        _requireMinimum(ethOut, minETHOut);

        IWETH9(weth).withdraw(ethOut);
        (bool ok,) = payable(receiver).call{value: ethOut}("");
        if (!ok) {
            revert NativeTransferFailed(receiver, ethOut);
        }
        _assertResidualBalancesRestored(seriesId, residuals);

        emit RecombinedToETH(msg.sender, receiver, seriesId, eveUSDAmount, preview.sharesBurned, ethOut);
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

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function _requireDepositMinimums(uint256 wethAmount, uint256 minEveUSD, uint256 minShares)
        internal
        view
        returns (IEveUSDPool.DepositPreview memory preview)
    {
        preview = IEveUSDPool(pool).previewDeposit(wethAmount);
        _requireMinimum(preview.eveUSDMinted, minEveUSD);
        _requireMinimum(preview.sharesMinted, minShares);
    }

    function _requireRecombinationBounds(
        uint256 seriesId,
        uint256 eveUSDAmount,
        uint256 maxSharesIn,
        uint256 minOut
    ) internal view returns (IEveUSDPool.RedemptionPreview memory preview) {
        preview = IEveUSDPool(pool).previewRecombine(seriesId, eveUSDAmount);
        if (preview.sharesBurned > maxSharesIn) {
            revert SharesAboveMaximum(preview.sharesBurned, maxSharesIn);
        }
        _requireMinimum(preview.collateralOut, minOut);
    }

    function _pullRecombinationTokens(uint256 seriesId, uint256 eveUSDAmount, uint256 sharesBurned) internal {
        IERC20(eveUSD).safeTransferFrom(msg.sender, address(this), eveUSDAmount);
        IERC1155(evRisk).safeTransferFrom(msg.sender, address(this), seriesId, sharesBurned, "");
    }

    function _requireMinimum(uint256 actual, uint256 minimum) internal pure {
        if (actual < minimum) {
            revert OutputBelowMinimum(actual, minimum);
        }
    }

    function _requireReceiver(address receiver) internal pure {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
    }

    function _residualSnapshot(uint256 seriesId) internal view returns (ResidualSnapshot memory snapshot) {
        snapshot = ResidualSnapshot({
            wethBalance: IERC20(weth).balanceOf(address(this)),
            eveUSDBalance: IERC20(eveUSD).balanceOf(address(this)),
            riskShareBalance: IERC1155(evRisk).balanceOf(address(this), seriesId),
            nativeBalance: address(this).balance
        });
    }

    function _assertResidualBalancesRestored(uint256 seriesId, ResidualSnapshot memory snapshot) internal view {
        uint256 balance = IERC20(weth).balanceOf(address(this));
        if (balance != snapshot.wethBalance) {
            revert ResidualRouterBalance(weth, snapshot.wethBalance, balance);
        }

        balance = IERC20(eveUSD).balanceOf(address(this));
        if (balance != snapshot.eveUSDBalance) {
            revert ResidualRouterBalance(eveUSD, snapshot.eveUSDBalance, balance);
        }

        balance = IERC1155(evRisk).balanceOf(address(this), seriesId);
        if (balance != snapshot.riskShareBalance) {
            revert ResidualRouterERC1155Balance(evRisk, seriesId, snapshot.riskShareBalance, balance);
        }

        balance = address(this).balance;
        if (balance != snapshot.nativeBalance) {
            revert ResidualRouterNativeBalance(snapshot.nativeBalance, balance);
        }
    }

    function _requireContract(address account) internal view {
        if (account == address(0)) {
            revert ZeroAddress();
        }
        if (account.code.length == 0) {
            revert ContractExpected(account);
        }
    }

    function _requirePoolAsset(address provided, address expected) internal pure {
        if (provided != expected) {
            revert InvalidPoolAsset(provided, expected);
        }
    }

    function _requireTokenPool(address token, address expectedPool, address actualPool) internal pure {
        if (actualPool != expectedPool) {
            revert InvalidPoolToken(token, expectedPool, actualPool);
        }
    }
}
