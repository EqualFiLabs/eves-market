// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IMarketSettlementFacet {
    function getCTFRedemptionParams(bytes32 marketId)
        external
        view
        returns (address collateralToken, bytes32 conditionId, uint256[] memory indexSets);

    function previewCTFRedemption(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome);

    function previewParimutuelPayout(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome);

    function previewRedemption(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome);
}
