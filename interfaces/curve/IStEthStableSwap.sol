// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

interface IStEthStableSwap {
    function get_virtual_price() external view returns (uint256);

    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external payable;

    function balances(int128) external view returns (uint256);

    function get_dy(
        int128 from,
        int128 to,
        uint256 _from_amount
    ) external view returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts, bool is_deposit)
        external
        view
        returns (uint256);
}
