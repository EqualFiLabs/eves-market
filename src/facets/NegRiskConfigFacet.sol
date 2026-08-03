// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IEvesNegRiskAdapter} from "../interfaces/IEvesNegRiskAdapter.sol";
import {IEvesCTFSettlementAdapter} from "../interfaces/IEvesCTFSettlementAdapter.sol";
import {INegRiskConfigFacet} from "../interfaces/INegRiskConfigFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";

contract NegRiskConfigFacet is INegRiskConfigFacet {
    event NegRiskAdapterSet(address indexed adapter, address indexed wrappedCollateral);
    event CTFSettlementAdapterSet(address indexed adapter);

    function setNegRiskAdapter(address adapter) external {
        LibDiamond.enforceIsContractOwner();
        if (adapter == address(0)) revert Errors.ZeroAddress();

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        IEvesNegRiskAdapter configuredAdapter = IEvesNegRiskAdapter(adapter);
        if (
            configuredAdapter.oracle() != address(this)
                || configuredAdapter.conditionalTokens() != state.config.defaultConditionalTokens
                || configuredAdapter.collateralToken() != state.config.collateralToken
                || configuredAdapter.wrappedCollateral() == address(0)
        ) revert Errors.NegRiskAdapterConfigMismatch(adapter);

        state.negRiskAdapter = adapter;
        emit NegRiskAdapterSet(adapter, configuredAdapter.wrappedCollateral());
    }

    function negRiskAdapter() external view returns (address) {
        return LibEveMarket.store().negRiskAdapter;
    }

    function setCTFSettlementAdapter(address adapter) external {
        LibDiamond.enforceIsContractOwner();
        if (adapter == address(0)) revert Errors.ZeroAddress();

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        IEvesCTFSettlementAdapter configuredAdapter = IEvesCTFSettlementAdapter(adapter);
        if (
            configuredAdapter.conditionalTokens() != state.config.defaultConditionalTokens
                || configuredAdapter.collateralToken() != state.config.collateralToken
        ) revert Errors.NegRiskAdapterConfigMismatch(adapter);

        state.ctfSettlementAdapter = adapter;
        emit CTFSettlementAdapterSet(adapter);
    }

    function ctfSettlementAdapter() external view returns (address) {
        return LibEveMarket.store().ctfSettlementAdapter;
    }
}
