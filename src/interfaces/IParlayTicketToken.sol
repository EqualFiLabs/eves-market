// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IParlayTicketToken {
    error NotDiamond(address caller);

    function diamond() external view returns (address);

    function mint(address to, uint256 id, uint256 amount) external;

    function burn(address from, uint256 id, uint256 amount) external;
}
