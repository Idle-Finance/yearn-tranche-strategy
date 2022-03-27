// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

/// @notice https://docs.lido.fi/contracts/steth-price-feed/#current_price
///         url: https://etherscan.io/address/0xab55bf4dfbf469ebfe082b7872557d1f87692fe6
interface IStEthPriceFeed {
    /// @notice Returns the cached safe price and its timestamp.
    function safe_price()
        external
        view
        returns (uint256 price, uint256 timestamp);

    /// @notice Returns the current pool price and whether the price is safe.
    function current_price()
        external
        view
        returns (uint256 price, bool is_safe);
}
