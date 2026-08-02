// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarkOracleFacet} from "../interfaces/IMarkOracleFacet.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarkOracle} from "../libraries/LibMarkOracle.sol";
import {MarkOracleTypes} from "../types/MarkOracleTypes.sol";

contract MarkOracleFacet is IMarkOracleFacet {
    function getMarkOracle(bytes32 bookId) external view returns (MarkOracleTypes.OracleSnapshot memory snapshot) {
        snapshot = LibMarkOracle.snapshot(LibEveMarket.store(), bookId);
    }

    function getMarkObservation(bytes32 bookId, uint256 index)
        external
        view
        returns (MarkOracleTypes.Observation memory observation)
    {
        observation = LibMarkOracle.observation(LibEveMarket.store(), bookId, index);
    }

    function consultTwap(bytes32 bookId, uint32 lookbackSeconds)
        external
        view
        returns (uint128 twapPrice, uint32 elapsedSeconds)
    {
        (twapPrice, elapsedSeconds) = LibMarkOracle.consultTwap(LibEveMarket.store(), bookId, lookbackSeconds);
    }

    function consultVwap(bytes32 bookId, uint32 lookbackSeconds)
        external
        view
        returns (uint128 vwapPrice, uint256 volume)
    {
        (vwapPrice, volume) = LibMarkOracle.consultVwap(LibEveMarket.store(), bookId, lookbackSeconds);
    }

    function oracleState(bytes32 bookId) external view returns (MarkOracleTypes.OracleState state) {
        state = LibMarkOracle.stateFor(LibEveMarket.store(), bookId);
    }

    function riskMarkForBook(bytes32 bookId, MarkOracleTypes.RiskMarkConfig calldata config)
        external
        view
        returns (MarkOracleTypes.RiskMark memory mark)
    {
        mark = LibMarkOracle.riskMarkForBook(LibEveMarket.store(), bookId, config);
    }

    function markOracleConfig() external view returns (MarkOracleTypes.OracleConfig memory config) {
        config = LibMarkOracle.config(LibEveMarket.store());
    }

    function setMarkOracleThresholds(uint32 cautionThreshold, uint32 staleThreshold) external {
        LibDiamond.enforceIsContractOwner();
        LibMarkOracle.setThresholds(LibEveMarket.store(), cautionThreshold, staleThreshold);
    }

    function clearMarkOracleManualState(bytes32 bookId) external {
        LibDiamond.enforceIsContractOwner();
        LibMarkOracle.clearManualState(LibEveMarket.store(), bookId);
    }

    function setMarkOracleManualState(bytes32 bookId, MarkOracleTypes.OracleState state) external {
        LibDiamond.enforceIsContractOwner();
        LibMarkOracle.setManualState(LibEveMarket.store(), bookId, state);
    }
}
