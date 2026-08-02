// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEveIdentity {
    error NotDiamond(address caller);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event IdentityMinted(uint256 indexed identityId, address indexed owner);
    event IdentityRolesUpdated(uint256 indexed identityId, bool creatorRole, bool resolverRole);

    function diamond() external view returns (address);
    function mint(address to) external returns (uint256 identityId);
    function setRoles(uint256 identityId, bool creatorRole, bool resolverRole) external;
    function ownerOf(uint256 identityId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function identityOf(address owner) external view returns (uint256);
    function totalMinted() external view returns (uint256);
    function hasCreatorRole(uint256 identityId) external view returns (bool);
    function hasResolverRole(uint256 identityId) external view returns (bool);
    function votingWeightOf(uint256 identityId) external view returns (uint256);
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
