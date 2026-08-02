// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IEveIdentity} from "../interfaces/IEveIdentity.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";

contract EveIdentity is IEveIdentity {
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 internal constant ERC721_INTERFACE_ID = 0x80ac58cd;

    address public immutable override diamond;
    string public name;
    string public symbol;

    uint256 internal _totalMinted;
    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _identityOf;
    mapping(uint256 => bool) internal _creatorRole;
    mapping(uint256 => bool) internal _resolverRole;

    modifier onlyDiamond() {
        if (msg.sender != diamond) {
            revert NotDiamond(msg.sender);
        }
        _;
    }

    constructor(address diamond_, string memory name_, string memory symbol_) {
        if (diamond_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        diamond = diamond_;
        name = name_;
        symbol = symbol_;
    }

    function mint(address to) external override onlyDiamond returns (uint256 identityId) {
        if (to == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_identityOf[to] != 0) {
            revert Errors.IdentityAlreadyOwned(to);
        }

        identityId = ++_totalMinted;
        _ownerOf[identityId] = to;
        _identityOf[to] = identityId;

        emit Transfer(address(0), to, identityId);
        emit Events.IdentityMinted(identityId, to);
    }

    function setRoles(uint256 identityId, bool creatorRole, bool resolverRole) external override onlyDiamond {
        _requireExistingIdentity(identityId);

        _creatorRole[identityId] = creatorRole;
        _resolverRole[identityId] = resolverRole;

        emit Events.IdentityRolesUpdated(identityId, creatorRole, resolverRole);
    }

    function ownerOf(uint256 identityId) external view override returns (address owner) {
        owner = _ownerOf[identityId];
        if (owner == address(0)) {
            revert Errors.IdentityNotFound(identityId);
        }
    }

    function balanceOf(address owner) external view override returns (uint256) {
        if (owner == address(0)) {
            revert Errors.ZeroAddress();
        }

        return _identityOf[owner] == 0 ? 0 : 1;
    }

    function identityOf(address owner) external view override returns (uint256) {
        return _identityOf[owner];
    }

    function totalMinted() external view override returns (uint256) {
        return _totalMinted;
    }

    function hasCreatorRole(uint256 identityId) external view override returns (bool) {
        _requireExistingIdentity(identityId);
        return _creatorRole[identityId];
    }

    function hasResolverRole(uint256 identityId) external view override returns (bool) {
        _requireExistingIdentity(identityId);
        return _resolverRole[identityId];
    }

    function votingWeightOf(uint256 identityId) external view override returns (uint256) {
        _requireExistingIdentity(identityId);
        return 0;
    }

    function approve(address, uint256) external pure override {
        revert Errors.IdentityApprovalDisabled();
    }

    function getApproved(uint256 identityId) external view override returns (address) {
        _requireExistingIdentity(identityId);
        return address(0);
    }

    function setApprovalForAll(address, bool) external pure override {
        revert Errors.IdentityApprovalDisabled();
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure override {
        revert Errors.IdentityTransferDisabled();
    }

    function safeTransferFrom(address, address, uint256) external pure override {
        revert Errors.IdentityTransferDisabled();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure override {
        revert Errors.IdentityTransferDisabled();
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == ERC165_INTERFACE_ID || interfaceId == ERC721_INTERFACE_ID
            || interfaceId == type(IEveIdentity).interfaceId;
    }

    function _requireExistingIdentity(uint256 identityId) internal view {
        if (_ownerOf[identityId] == address(0)) {
            revert Errors.IdentityNotFound(identityId);
        }
    }
}
