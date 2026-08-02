// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployMockUSDG} from "../../script/DeployMockUSDG.s.sol";
import {MockUSDG} from "../../src/mocks/MockUSDG.sol";

contract DeployMockUSDGTest is Test {
    function testDeploysSupplyAndTransfersControl() public {
        address owner = makeAddr("owner");
        address recipient = makeAddr("recipient");
        uint256 initialSupply = 10_000_000e6;

        MockUSDG token = new DeployMockUSDG().deploy(owner, recipient, initialSupply);

        assertEq(token.name(), "Mock USDG");
        assertEq(token.symbol(), "mUSDG");
        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.balanceOf(recipient), initialSupply);
        assertEq(token.owner(), owner);
        assertEq(token.nonces(recipient), 0);
    }
}
