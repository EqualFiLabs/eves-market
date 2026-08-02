// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {Errors} from "../libraries/Errors.sol";
import {LibCTF} from "../libraries/LibCTF.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract CurveInventoryFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function splitInventory(bytes32 marketId, uint128 collateralAmount)
        external
        nonReentrant
        returns (uint128 sharesMinted)
    {
        if (collateralAmount == 0) {
            revert Errors.InvalidAmount(collateralAmount);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requireExistingMarket(state, marketId);
        LibMarketAccess.requirePositionTokenType(market, LibEveMarket.PositionTokenType.CTF);
        LibMarketAccess.validatePositionIds(market);

        IERC20 collateralToken = IERC20(market.collateralToken);
        IERC1155 positionToken = IERC1155(market.positionToken);

        LibCTF.prepareMarketCondition(market.positionToken, market.resolutionId);
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);
        collateralToken.forceApprove(market.positionToken, collateralAmount);

        LibCTF.splitCollateral(market.positionToken, market.collateralToken, market.conditionId, collateralAmount);

        positionToken.safeTransferFrom(address(this), msg.sender, market.yesPositionId, collateralAmount, "");
        positionToken.safeTransferFrom(address(this), msg.sender, market.noPositionId, collateralAmount, "");

        sharesMinted = collateralAmount;
    }

    function mergeInventory(bytes32 marketId, uint128 shareAmount)
        external
        nonReentrant
        returns (uint128 collateralOut)
    {
        if (shareAmount == 0) {
            revert Errors.InvalidAmount(shareAmount);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requireExistingMarket(state, marketId);
        LibMarketAccess.requirePositionTokenType(market, LibEveMarket.PositionTokenType.CTF);
        LibMarketAccess.validatePositionIds(market);

        IERC1155 positionToken = IERC1155(market.positionToken);
        LibCTF.prepareMarketCondition(market.positionToken, market.resolutionId);
        positionToken.safeTransferFrom(msg.sender, address(this), market.yesPositionId, shareAmount, "");
        positionToken.safeTransferFrom(msg.sender, address(this), market.noPositionId, shareAmount, "");

        LibCTF.mergeCollateral(market.positionToken, market.collateralToken, market.conditionId, shareAmount);
        IERC20(market.collateralToken).safeTransfer(msg.sender, shareAmount);

        collateralOut = shareAmount;
    }
}
