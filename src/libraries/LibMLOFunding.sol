// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IMLOInsuranceFund} from "../interfaces/IMLOInsuranceFund.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarginAccount} from "./LibMarginAccount.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";
import {LibSeniorCapital} from "./LibSeniorCapital.sol";

library LibMLOFunding {
    using SafeERC20 for IERC20;

    function payFromProceeds(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        address collateralToken,
        uint256 maxAssets
    ) internal returns (uint256 paid) {
        LibRiskEngine.accrueConfiguredFunding(state, bucketId);
        uint256 liability = state.marginBuckets[bucketId].fundingLiability;
        paid = maxAssets < liability ? maxAssets : liability;
        if (paid == 0) return 0;
        LibRiskEngine.recordFundingPayment(state, bucketId, paid);
        _transferFunding(state, bucketId, collateralToken, paid, false);
    }

    function payFromMargin(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 maxAssets)
        internal
        returns (uint256 paid)
    {
        paid = LibMarginAccount.payFundingFromMarginTrusted(state, bucketId, maxAssets);
        if (paid == 0) return 0;
        _transferFunding(state, bucketId, state.marginAsset, paid, true);
    }

    function transferRecordedPayment(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        address collateralToken,
        uint256 assets,
        bool fromMargin
    ) internal {
        _transferFunding(state, bucketId, collateralToken, assets, fromMargin);
    }

    function _transferFunding(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        address collateralToken,
        uint256 assets,
        bool fromMargin
    ) private {
        uint256 seniorAmount = Math.mulDiv(assets, state.mloFundingSeniorBps, 10_000);
        uint256 insuranceAmount = assets - seniorAmount;
        address insuranceFund = state.mloInsuranceFund;
        if (insuranceAmount != 0 && insuranceFund == address(0)) {
            revert IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund(insuranceFund);
        }
        if (seniorAmount != 0) {
            LibSeniorCapital.Storage storage senior = LibSeniorCapital.s();
            LibSeniorCapital.noteFundingRevenue(senior, bucketId, seniorAmount);
            LibSeniorCapital.accrueFees(senior, seniorAmount, LibSeniorCapital.FEE_SOURCE_MLO_FUNDING, bucketId);
        }
        if (insuranceAmount != 0) {
            IERC20(collateralToken).forceApprove(insuranceFund, insuranceAmount);
            IMLOInsuranceFund(insuranceFund).notifyFundingRevenue(bucketId, insuranceAmount);
        }
        emit IMLOPredictionAdapterFacet.MLOFundingPaid(
            bucketId, insuranceFund, assets, seniorAmount, insuranceAmount, fromMargin
        );
    }
}
