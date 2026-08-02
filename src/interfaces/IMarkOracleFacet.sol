// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarkOracleTypes} from "../types/MarkOracleTypes.sol";

interface IMarkOracleFacet {
    error InvalidOracleThresholds(uint256 cautionThreshold, uint256 staleThreshold);
    error InvalidOracleLookback();
    error MarkOracleBookNotFound(bytes32 bookId);
    error MarkOracleObservationNotFound(bytes32 bookId, uint256 index);
    error InvalidOracleManualState(uint8 state);
    error InvalidRiskMarkConfig(uint256 lookbackSeconds, uint256 assetHaircutBps, uint256 liabilityPremiumBps);

    event MarkOracleThresholdsSet(
        uint32 previousCautionThreshold, uint32 cautionThreshold, uint32 previousStaleThreshold, uint32 staleThreshold
    );
    event MarkOracleManualStateSet(bytes32 indexed bookId, bool manualOverride, MarkOracleTypes.OracleState state);
    event RiskDomainMarkConfigSet(
        bytes32 indexed riskDomainId, uint32 lookbackSeconds, uint16 assetHaircutBps, uint16 liabilityPremiumBps
    );

    function getMarkOracle(bytes32 bookId) external view returns (MarkOracleTypes.OracleSnapshot memory snapshot);

    function getMarkObservation(bytes32 bookId, uint256 index)
        external
        view
        returns (MarkOracleTypes.Observation memory observation);

    function consultTwap(bytes32 bookId, uint32 lookbackSeconds)
        external
        view
        returns (uint128 twapPrice, uint32 elapsedSeconds);

    function consultVwap(bytes32 bookId, uint32 lookbackSeconds)
        external
        view
        returns (uint128 vwapPrice, uint256 volume);

    function oracleState(bytes32 bookId) external view returns (MarkOracleTypes.OracleState state);

    function riskMarkForBook(bytes32 bookId, MarkOracleTypes.RiskMarkConfig calldata config)
        external
        view
        returns (MarkOracleTypes.RiskMark memory mark);

    function markOracleConfig() external view returns (MarkOracleTypes.OracleConfig memory config);

    function setMarkOracleThresholds(uint32 cautionThreshold, uint32 staleThreshold) external;

    function clearMarkOracleManualState(bytes32 bookId) external;

    function setMarkOracleManualState(bytes32 bookId, MarkOracleTypes.OracleState state) external;
}
