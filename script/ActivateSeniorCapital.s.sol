// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {ISeniorCapitalFacet} from "../src/interfaces/ISeniorCapitalFacet.sol";

contract ActivateSeniorCapital is Script {
    function run() external returns (uint256 principal, uint256 storedUnits) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address diamond = vm.envAddress("EVE_DIAMOND");
        address provider = vm.addr(privateKey);
        ISeniorCapitalFacet.SeniorCapitalAccount memory beforeAccount =
            ISeniorCapitalFacet(diamond).seniorCapitalAccount(provider);
        require(beforeAccount.pendingPrincipal != 0, "no pending Senior capital");

        vm.startBroadcast(privateKey);
        (principal, storedUnits) = ISeniorCapitalFacet(diamond).activateSeniorCapital();
        vm.stopBroadcast();

        ISeniorCapitalFacet.SeniorCapitalAccount memory afterAccount =
            ISeniorCapitalFacet(diamond).seniorCapitalAccount(provider);
        ISeniorCapitalFacet.SeniorCapitalState memory state = ISeniorCapitalFacet(diamond).seniorCapitalState();
        require(afterAccount.pendingPrincipal == 0, "Senior activation incomplete");
        require(afterAccount.effectivePrincipal >= principal, "Senior principal mismatch");
        require(state.availableCapital >= principal, "Senior capital unavailable");

        console2.log("activated Senior principal", principal);
        console2.log("stored units", storedUnits);
    }
}
