// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";
import {IParimutuelShareToken} from "../interfaces/IParimutuelShareToken.sol";
import {ISEveUSDCVault} from "../interfaces/ISEveUSDCVault.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";

library LibAdminConfig {
    bytes4 internal constant VAULT_ASSET_SELECTOR = bytes4(keccak256("asset()"));

    function enforceContract(address account) internal view {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (account.code.length == 0) {
            revert Errors.ContractHasNoCode(account);
        }
    }

    function enforceNonZero(uint256 amount) internal pure {
        if (amount == 0) {
            revert Errors.InvalidAmount(0);
        }
    }

    function enforceERC20(address token) internal view {
        enforceContract(token);
        try IERC20(token).totalSupply() returns (uint256) {}
        catch {
            revert Errors.InvalidContractInterface(token, IERC20.totalSupply.selector);
        }
    }

    function enforceERC1155(address token) internal view {
        if (token.code.length == 0) {
            revert Errors.ContractHasNoCode(token);
        }
    }

    function enforceConditionalTokens(address conditionalTokens) internal view {
        enforceContract(conditionalTokens);
        try IGnosisConditionalTokens(conditionalTokens).getConditionId(address(this), bytes32(0), 2) returns (
            bytes32
        ) {}
        catch {
            revert Errors.InvalidContractInterface(conditionalTokens, IGnosisConditionalTokens.getConditionId.selector);
        }
    }

    function enforceVault(address vault) internal view {
        enforceContract(vault);
        try ISEveUSDCVault(vault).asset() returns (address asset) {
            if (asset == address(0)) {
                revert Errors.ZeroAddress();
            }
        } catch {
            revert Errors.InvalidContractInterface(vault, VAULT_ASSET_SELECTOR);
        }
    }

    function enforceParimutuelShareToken(address shareToken) internal view {
        enforceContract(shareToken);
        try IParimutuelShareToken(shareToken).diamond() returns (address diamond) {
            if (diamond != address(this)) {
                revert Errors.InvalidContractInterface(shareToken, IParimutuelShareToken.diamond.selector);
            }
        } catch {
            revert Errors.InvalidContractInterface(shareToken, IParimutuelShareToken.diamond.selector);
        }
    }

    function enforceBps(uint256 value) internal pure {
        if (value > 10_000) {
            revert Errors.InvalidAmount(value);
        }
    }

    function toUint128(uint256 value) internal pure returns (uint128 narrowed) {
        if (value > type(uint128).max) {
            revert Errors.InvalidAmount(value);
        }
        narrowed = uint128(value);
    }

    function emitConfigUpdate(bytes32 paramName, uint256 priorValue, uint256 newValue) internal {
        emit Events.ConfigUpdated(paramName, priorValue, newValue);
    }

    function emitConfigUpdateAddress(bytes32 paramName, address priorValue, address newValue) internal {
        emit Events.ConfigUpdated(paramName, uint256(uint160(priorValue)), uint256(uint160(newValue)));
    }
}
