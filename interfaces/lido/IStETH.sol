// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStETH is IERC20 {
    function submit(address) external payable returns (uint256);
}
