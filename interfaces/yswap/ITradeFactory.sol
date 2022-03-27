// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

/// https://github.com/yearn/yswaps/blob/main/solidity/contracts/TradeFactory/
interface ITradeFactory {
    /// @dev account that has STRATEGY role can call the method
    function enable(address, address) external;
}
