// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

interface StEthPriceFeed {
    /// @notice Returns the cached safe price and its timestamp.
    function safe_price()
        external
        view
        returns (uint256 price, uint256 timestamp);
}
