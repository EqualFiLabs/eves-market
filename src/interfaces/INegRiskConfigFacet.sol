// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface INegRiskConfigFacet {
    function setNegRiskAdapter(address adapter) external;
    function negRiskAdapter() external view returns (address);
    function setCTFSettlementAdapter(address adapter) external;
    function ctfSettlementAdapter() external view returns (address);
}
