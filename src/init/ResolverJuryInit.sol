// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";

contract ResolverJuryInit {
    function initResolverJury(address eveIdentity) external {
        if (eveIdentity == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        address previous = jury.eveIdentity;
        jury.eveIdentity = eveIdentity;

        emit Events.ConfigUpdated("eveIdentity", uint256(uint160(previous)), uint256(uint160(eveIdentity)));
    }
}
