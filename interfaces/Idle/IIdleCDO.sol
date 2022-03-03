// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

interface IIdleCDO {
    // address of AA (Senior) Tranche token contract
    function AATranche() external view returns (address);

    // address of BB (Junior) Tranche token contract
    function BBTranche() external view returns (address);

    // address of AA Staking reward token contract
    function AAStaking() external view returns (address);

    // address of BB Staking reward token contract
    function BBStaking() external view returns (address);

    // address of the strategy used to lend funds
    function strategy() external view returns (address);

    // address of the strategy token which represent the position in the lending provider
    function strategyToken() external view returns (address);

    // underlying token (eg DAI)
    function token() external view returns (address);

    // Flag for allowing AA withdraws
    function allowAAWithdraw() external view returns (bool);

    // Flag for allowing BB withdraws
    function allowBBWithdraw() external view returns (bool);

    // Fee amount (relative to FULL_ALLOC)
    function fee() external view returns (uint256);

    function getApr(address _tranche) external view returns (uint256);

    /// @notice calculates the current total value locked (in `token` terms)
    /// @dev unclaimed rewards (gov tokens) are not counted.
    /// NOTE: `unclaimedFees` are not included in the contract value
    /// NOTE2: fees that *will* be taken (in the next _updateAccounting call) are counted
    function getContractValue() external view returns (uint256);

    // Apr split ratio for AA tranches
    // (relative to FULL_ALLOC so 50% => 50000 => 50% of the interest to tranche AA)
    function trancheAPRSplitRatio() external view returns (uint256);

    function getCurrentAARatio() external view returns (uint256);

    /// @notice This method returns the last tranche price saved on the last smart contract interaction
    ///         (it may not include interest earned since the last update.
    ///         For an up-to-date price, check the virtualPrice method).
    /// @param _tranche tranche address
    /// @return tranche price
    function tranchePrice(address _tranche) external view returns (uint256);

    /// @notice calculates the current tranches price considering the interest that is yet to be splitted
    /// ie the interest generated since the last update of priceAA and priceBB (done on depositXX/withdrawXX/harvest)
    /// useful for showing updated gains on frontends
    /// @dev this should always be >= of _tranchePrice(_tranche)
    /// @param _tranche address of the requested tranche
    /// @return _virtualPrice tranche price considering all interest
    function virtualPrice(address _tranche) external view returns (uint256);

    /// @notice returns an array of tokens used to incentive tranches via IIdleCDOTrancheRewards
    /// @return array with addresses of incentiveTokens (can be empty)
    function getIncentiveTokens() external view returns (address[] memory);

    // ###############
    // Mutative methods
    // ###############

    /// @notice pausable
    /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
    /// @param _amount amount of `token` to deposit
    /// @return AA tranche tokens minted
    function depositAA(uint256 _amount) external returns (uint256);

    /// @notice pausable in _deposit
    /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
    /// @param _amount amount of `token` to deposit
    /// @return BB tranche tokens minted
    function depositBB(uint256 _amount) external returns (uint256);

    /// @notice pausable in _deposit
    /// @param _amount amount of AA tranche tokens to burn
    /// @return underlying tokens redeemed
    function withdrawAA(uint256 _amount) external returns (uint256);

    /// @notice pausable
    /// @param _amount amount of BB tranche tokens to burn
    /// @return underlying tokens redeemed
    function withdrawBB(uint256 _amount) external returns (uint256);
}
