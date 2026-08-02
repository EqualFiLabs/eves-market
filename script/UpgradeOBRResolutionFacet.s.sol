// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console2} from "../lib/forge-std/src/Script.sol";

import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {OBRResolutionFacet} from "../src/facets/OBRResolutionFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {IMarketFactoryFacet} from "../src/interfaces/IMarketFactoryFacet.sol";
import {IOBRResolutionFacet} from "../src/interfaces/IOBRResolutionFacet.sol";
import {MarketFactoryTypes} from "../src/types/MarketFactoryTypes.sol";

contract UpgradeOBRResolutionFacet is Script {
    struct UpgradeDeployment {
        address obrResolutionFacet;
    }

    struct UpgradeConfig {
        uint256 privateKey;
        address diamond;
        uint128 marketCreationFee;
    }

    function run() external returns (UpgradeDeployment memory deployment) {
        UpgradeConfig memory config = _loadConfig();

        vm.startBroadcast(config.privateKey);
        deployment.obrResolutionFacet = address(new OBRResolutionFacet());
        DiamondCutFacet(config.diamond).diamondCut(_obrFacetCuts(deployment), address(0), "");
        OwnershipFacet(config.diamond).setMarketCreationFee(config.marketCreationFee);
        vm.stopBroadcast();

        _verifyUpgrade(deployment, config);
        _logDeployment(deployment, config);
    }

    function _loadConfig() private view returns (UpgradeConfig memory config) {
        config.privateKey = vm.envUint("PRIVATE_KEY");
        config.diamond = vm.envAddress("DIAMOND");
        config.marketCreationFee = uint128(vm.envUint("MARKET_CREATION_FEE"));
    }

    function _obrFacetCuts(UpgradeDeployment memory deployment)
        private
        pure
        returns (DiamondCutFacet.FacetCut[] memory cuts)
    {
        cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: deployment.obrResolutionFacet,
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _obrResolutionSelectors()
        });
    }

    function _obrResolutionSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IOBRResolutionFacet.settleMarket.selector;
        selectors[1] = IOBRResolutionFacet.openResolution.selector;
        selectors[2] = IOBRResolutionFacet.disputeResolution.selector;
        selectors[3] = IOBRResolutionFacet.getResolutionHistory.selector;
        selectors[4] = IOBRResolutionFacet.finalizeResolution.selector;
        selectors[5] = IOBRResolutionFacet.getMarketStatus.selector;
        selectors[6] = IOBRResolutionFacet.settleMarketEarly.selector;
    }

    function _verifyUpgrade(UpgradeDeployment memory deployment, UpgradeConfig memory config) private view {
        bytes4[] memory selectors = _obrResolutionSelectors();
        for (uint256 index = 0; index < selectors.length; ++index) {
            _assertSelector(config.diamond, selectors[index], deployment.obrResolutionFacet);
        }

        MarketFactoryTypes.MarketConfigView memory marketConfig = IMarketFactoryFacet(config.diamond).getMarketConfig();
        require(marketConfig.marketCreationFee == config.marketCreationFee, "market creation fee mismatch");
    }

    function _logDeployment(UpgradeDeployment memory deployment, UpgradeConfig memory config) private pure {
        console2.log("obrResolutionFacet", deployment.obrResolutionFacet);
        console2.log("diamond", config.diamond);
        console2.log("marketCreationFee", uint256(config.marketCreationFee));
    }

    function _assertSelector(address diamond, bytes4 selector, address expectedFacet) private view {
        address actualFacet = _facetAddress(diamond, selector);
        require(actualFacet == expectedFacet, "selector not upgraded");
    }

    function _facetAddress(address diamond, bytes4 selector) private view returns (address facet) {
        (bool ok, bytes memory data) = diamond.staticcall(abi.encodeWithSignature("facetAddress(bytes4)", selector));
        require(ok, "facetAddress failed");
        facet = abi.decode(data, (address));
    }
}
