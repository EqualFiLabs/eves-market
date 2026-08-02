// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";

contract DiamondLoupeFacet {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    function facets() external view returns (Facet[] memory facets_) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        address[] storage facetAddresses_ = state.facetAddresses;

        facets_ = new Facet[](facetAddresses_.length);

        for (uint256 index = 0; index < facetAddresses_.length; ++index) {
            address facetAddress_ = facetAddresses_[index];
            bytes4[] storage storedSelectors = state.facetFunctionSelectors[facetAddress_];
            bytes4[] memory selectors = new bytes4[](storedSelectors.length);

            for (uint256 selectorIndex = 0; selectorIndex < storedSelectors.length; ++selectorIndex) {
                selectors[selectorIndex] = storedSelectors[selectorIndex];
            }

            facets_[index] = Facet({facetAddress: facetAddress_, functionSelectors: selectors});
        }
    }

    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory selectors) {
        bytes4[] storage storedSelectors = LibEveMarket.store().facetFunctionSelectors[facet];
        selectors = new bytes4[](storedSelectors.length);

        for (uint256 index = 0; index < storedSelectors.length; ++index) {
            selectors[index] = storedSelectors[index];
        }
    }

    function facetAddresses() external view returns (address[] memory facetAddresses_) {
        address[] storage storedFacetAddresses = LibEveMarket.store().facetAddresses;
        facetAddresses_ = new address[](storedFacetAddresses.length);

        for (uint256 index = 0; index < storedFacetAddresses.length; ++index) {
            facetAddresses_[index] = storedFacetAddresses[index];
        }
    }

    function facetAddress(bytes4 selector) external view returns (address) {
        return LibEveMarket.store().selectorToFacet[selector];
    }
}
