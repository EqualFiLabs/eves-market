// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {TestnetEVE} from "../../src/mocks/TestnetEVE.sol";

contract TestnetEVETest is Test {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 internal ownerKey;
    address internal owner;
    address internal spender;
    TestnetEVE internal token;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        spender = makeAddr("spender");
        token = new TestnetEVE(owner);
    }

    function test_OwnerControlsMintingAndCanDelegateLaunchSupply() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.mint(address(this), 1e18);

        vm.prank(owner);
        token.mintAndDelegate(owner, 1_000_000e18);

        assertEq(token.balanceOf(owner), 1_000_000e18);
        assertEq(token.delegates(owner), owner);
        assertEq(token.getVotes(owner), 1_000_000e18);
    }

    function test_PermitAuthorizesAnExactAllowanceAndCannotReplay() public {
        uint256 amount = 125e18;
        uint256 deadline = block.timestamp + 20 minutes;
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, 0, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        token.permit(owner, spender, amount, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.nonces(owner), 1);
        vm.expectRevert();
        token.permit(owner, spender, amount, deadline, v, r, s);
    }
}
