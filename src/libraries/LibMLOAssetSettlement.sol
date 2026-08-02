// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IEvesPositionManager} from "../interfaces/IEvesPositionManager.sol";
import {IEvesNegRiskAdapter} from "../interfaces/IEvesNegRiskAdapter.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {MLOInventoryVault} from "../MLOInventoryVault.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibBookAccounting} from "./LibBookAccounting.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibNativeCollateral} from "./LibNativeCollateral.sol";
import {LibMLOFunding} from "./LibMLOFunding.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";
import {LibSeniorCapital} from "./LibSeniorCapital.sol";

library LibMLOAssetSettlement {
    using SafeERC20 for IERC20;

    function executeAsk(MLOPredictionTypes.MLOAskAssetSettlementParams calldata params) internal {
        if (params.seniorDeployed != 0) {
            LibSeniorCapital.deployReservedCapital(LibSeniorCapital.s(), params.bucketId, params.seniorDeployed);
        }
        if (params.seniorReleased != 0) {
            LibSeniorCapital.releaseReservedCapital(LibSeniorCapital.s(), params.bucketId, params.seniorReleased);
        }
        if (params.manufacturedShares != 0) {
            if (LibEveMarket.PositionTokenType(params.positionTokenType) == LibEveMarket.PositionTokenType.CTF) {
                _splitCTF(params);
            } else {
                _mintNativeOutcomes(params);
            }
        }
        if (params.inventoryUsed != 0) {
            MLOInventoryVault(params.inventoryVault)
                .transferPosition(params.positionToken, params.receiver, params.soldPositionId, params.inventoryUsed);
        }
        if (params.seniorRepaid != 0) {
            LibSeniorCapital.repayActiveExposure(LibSeniorCapital.s(), params.bucketId, params.seniorRepaid);
        }
        if (params.fundingPaid != 0) {
            LibRiskEngine.recordFundingPayment(LibEveMarket.store(), params.bucketId, params.fundingPaid);
            LibMLOFunding.transferRecordedPayment(
                LibEveMarket.store(), params.bucketId, params.collateralToken, params.fundingPaid, false
            );
        }
        _payFees(params.bookId, params.feePaid);
    }

    function executeBid(MLOPredictionTypes.MLOBidAssetSettlementParams calldata params) internal {
        if (params.grossPayment != 0) {
            LibSeniorCapital.deployReservedCapital(LibSeniorCapital.s(), params.bucketId, params.grossPayment);
        }
        if (params.seniorReleased != 0) {
            LibSeniorCapital.releaseReservedCapital(LibSeniorCapital.s(), params.bucketId, params.seniorReleased);
        }
        IERC1155(params.positionToken)
            .safeTransferFrom(params.source, params.inventoryVault, params.positionId, params.sharesIn, "");
        if (params.collateralOut != 0 && params.receiver != address(this)) {
            IERC20 token = IERC20(params.collateralToken);
            uint256 receiverBefore = token.balanceOf(params.receiver);
            token.safeTransfer(params.receiver, params.collateralOut);
            uint256 receiverAfter = token.balanceOf(params.receiver);
            uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
            if (received != params.collateralOut) {
                revert IMLOPredictionAdapterFacet.MLOCollateralNonExactTransfer(params.collateralOut, received);
            }
        }
        _payFees(params.bookId, params.feePaid);
    }

    function _splitCTF(MLOPredictionTypes.MLOAskAssetSettlementParams calldata params) private {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[state.books[params.bookId].marketId];
        if (multi.exists) {
            IERC20(params.collateralToken).forceApprove(multi.adapter, params.manufacturedShares);
            IEvesNegRiskAdapter(multi.adapter).splitEvent(multi.conditionId, params.manufacturedShares, address(this));
            IERC20(params.collateralToken).forceApprove(multi.adapter, 0);
        } else {
            IERC20(params.collateralToken).forceApprove(params.positionToken, params.manufacturedShares);
            LibCTF.prepareMarketCondition(params.positionToken, params.resolutionId);
            LibCTF.splitCollateral(
                params.positionToken, params.collateralToken, params.conditionId, params.manufacturedShares
            );
        }
        IERC1155 token = IERC1155(params.positionToken);
        for (uint256 index; index < params.retainedPositionIds.length; ++index) {
            token.safeTransferFrom(
                address(this), params.inventoryVault, params.retainedPositionIds[index], params.manufacturedShares, ""
            );
        }
        token.safeTransferFrom(address(this), params.receiver, params.soldPositionId, params.manufacturedShares, "");
    }

    function _mintNativeOutcomes(MLOPredictionTypes.MLOAskAssetSettlementParams calldata params) private {
        IEvesPositionManager positions = IEvesPositionManager(params.positionToken);
        positions.mint(params.receiver, params.soldPositionId, params.manufacturedShares);
        uint256[] memory amounts = new uint256[](params.retainedPositionIds.length);
        for (uint256 index; index < amounts.length; ++index) {
            amounts[index] = params.manufacturedShares;
        }
        positions.batchMint(params.inventoryVault, params.retainedPositionIds, amounts);
        LibNativeCollateral.increaseLiability(LibEveMarket.store(), params.collateralToken, params.manufacturedShares);
    }

    function _payFees(bytes32 bookId, uint128 feePaid) private {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = state.books[bookId];
        LibBookAccounting.payBookQuoteFees(state, book, LibBookAccounting.feeSharesForBook(state, book, feePaid));
    }
}
