// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { BaseStrategy } from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/idle/IIdleCDO.sol";
import "../interfaces/idle/IMultiRewards.sol";
import "../interfaces/uniswap/IUniswapV2Router02.sol";
import "../interfaces/yswap/ITradeFactory.sol";
import "../interfaces/IERC20Metadata.sol";
import "../interfaces/IWETH.sol";

/// @title Base Tranche Strategy
/// @author bakuchi
contract TrancheStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @dev `tranche` have fixed 18 decimals regardless of the underlying
    uint256 internal constant EXP_SCALE = 1e18;

    IWETH internal constant WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IERC20Metadata public immutable tranche;

    IIdleCDO public immutable idleCDO;

    IUniswapV2Router02 public router;

    IMultiRewards public multiRewards;

    bool public immutable isAATranche;

    bool public enabledStake;

    address public tradeFactory;

    IERC20[] internal rewardTokens;

    constructor(
        address _vault,
        IIdleCDO _idleCDO,
        bool _isAATranche,
        IUniswapV2Router02 _router,
        IERC20[] memory _rewardTokens,
        IMultiRewards _multiRewards,
        address _healthCheck
    ) public BaseStrategy(_vault) {
        require(
            address(_router) != address(0) || _healthCheck != address(0),
            "strat/zero-address"
        );

        idleCDO = _idleCDO;
        isAATranche = _isAATranche;
        router = _router;
        // can be empaty array
        rewardTokens = _rewardTokens; // set `tradeFactory` address after deployment.
        // can be zero address
        multiRewards = _multiRewards; // set `enabledStake` to true to enable stakeing after deployment.
        healthCheck = _healthCheck;

        IERC20Metadata _tranche =
            IERC20Metadata(
                _isAATranche ? _idleCDO.AATranche() : _idleCDO.BBTranche()
            );
        tranche = _tranche;

        // tranche would have fixed 18 decimals regardless of underlying
        // `EXP_SCALE` is fixed
        require(_tranche.decimals() == 18, "strat/decimals-18");

        want.safeApprove(address(_idleCDO), type(uint256).max);

        if (address(_multiRewards) != address(0)) {
            _tranche.approve(address(_multiRewards), type(uint256).max);
        }
    }

    // ******** PERMISSIONED METHODS ************

    /// @notice enable staking
    function enableStaking() external onlyVaultManagers {
        require(tradeFactory != address(0), "strat/tf-zero"); // first set tradeFactory
        require(address(multiRewards) != address(0), "strat/multirewards-zero"); // first set multiRewards
        enabledStake = true;
    }

    /// @notice withdraw staked and disable staking
    /// @dev to revoke multirewards contract use `setMultiRewards` method
    function disableStaking() external onlyVaultManagers {
        enabledStake = false;
        IMultiRewards _multiRewards = multiRewards;
        // exit
        // NOTE: withdrawing amount 0 will cause to revert
        if (
            address(_multiRewards) != address(0) &&
            _multiRewards.balanceOf(address(this)) != 0
        ) {
            _multiRewards.exit();
        }
    }

    /// @notice set multirewards contract
    /// @dev revoke or approve multirewards contract
    function setMultiRewards(IMultiRewards _multiRewards)
        external
        onlyVaultManagers
    {
        IERC20 _tranche = tranche; // caching

        IMultiRewards _oldMultiRewards = multiRewards; // read old multirewards
        multiRewards = _multiRewards; // set new multirewards

        if (address(_oldMultiRewards) != address(0)) {
            // exit
            // NOTE: withdrawing amount 0 will cause to revert
            if (_oldMultiRewards.balanceOf(address(this)) != 0) {
                _oldMultiRewards.exit();
            }
            // revoke
            _tranche.approve(address(_oldMultiRewards), 0);
        }

        // approve & stake
        if (address(_multiRewards) != address(0)) {
            uint256 trancheBal = _balance(_tranche);
            _tranche.approve(address(_multiRewards), type(uint256).max); // approve

            // stake
            if (enabledStake && trancheBal != 0) {
                _multiRewards.stake(trancheBal);
            }
        }
    }

    /// @notice set reward tokens
    function setRewardTokens(IERC20[] memory _rewardTokens)
        external
        onlyVaultManagers
    {
        bool useTradeFactory = tradeFactory != address(0);

        if (useTradeFactory) {
            _revokeTradeFactoryPermissions();
        }

        rewardTokens = _rewardTokens; // set

        if (useTradeFactory) {
            _approveTradeFactory();
        }
    }

    /// @dev this strategy must be granted STRATEGY role if `_newTradeFactory` is non-zero address NOTE: https://github.com/yearn/yswaps/blob/7410951c9514dfa2abdcf82477cb4f92e1da7dd5/solidity/contracts/TradeFactory/TradeFactoryPositionsHandler.sol#L80
    ///      to revoke tradeFactory pass address(0) as the parameter
    function updateTradeFactory(address _newTradeFactory)
        public
        onlyGovernance
    {
        if (tradeFactory != address(0)) {
            _revokeTradeFactoryPermissions();
        }

        tradeFactory = _newTradeFactory; // set

        if (_newTradeFactory != address(0)) {
            _approveTradeFactory();
        }
    }

    /// @notice setup tradeFactory
    /// @dev assume tradeFactory is not zero address
    function _approveTradeFactory() internal {
        IERC20[] memory _rewardTokens = rewardTokens;
        address _want = address(want);
        ITradeFactory tf = ITradeFactory(tradeFactory);

        uint256 length = _rewardTokens.length;
        IERC20 _rewardToken;
        for (uint256 i; i < length; i++) {
            _rewardToken = _rewardTokens[i];
            _rewardToken.safeApprove(address(tf), type(uint256).max);
            // this strategy must be granted STRATEGY role : https://github.com/yearn/yswaps/blob/7410951c9514dfa2abdcf82477cb4f92e1da7dd5/solidity/contracts/TradeFactory/TradeFactoryPositionsHandler.sol#L80
            tf.enable(address(_rewardToken), _want);
        }
    }

    /// @notice remove tradeFactory
    /// @dev assume tradeFactory is not zero address
    function _revokeTradeFactoryPermissions() internal {
        address _tradeFactory = tradeFactory;
        IERC20[] memory _rewardTokens = rewardTokens;
        uint256 length = _rewardTokens.length;

        for (uint256 i; i < length; i++) {
            _rewardTokens[i].safeApprove(_tradeFactory, 0);
        }
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return string(abi.encodePacked("Strategy", tranche.name()));
    }

    function getRewardTokens() external view returns (IERC20[] memory) {
        return rewardTokens;
    }

    /**
     * @notice
     *  Provide an accurate estimate for the total amount of assets
     *  (principle + return) that this Strategy is currently managing,
     *  denominated in terms of `want` tokens.
     *
     *  This total should be "realizable" e.g. the total value that could
     *  *actually* be obtained from this Strategy if it were to divest its
     *  entire position based on current on-chain conditions.
     * @dev
     *  Care must be taken in using this function, since it relies on external
     *  systems, which could be manipulated by the attacker to give an inflated
     *  (or reduced) value produced by this function, based on current on-chain
     *  conditions (e.g. this function is possible to influence through
     *  flashloan attacks, oracle manipulations, or other DeFi attack
     *  mechanisms).
     *
     *  It is up to governance to use this function to correctly order this
     *  Strategy relative to its peers in the withdrawal queue to minimize
     *  losses for the Vault based on sudden withdrawals. This value should be
     *  higher than the total debt of the Strategy and higher than its expected
     *  value to be "safe".
     * @return The estimated total assets in this Strategy.
     */
    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        uint256 wantBal = _balance(want);
        uint256 totalTranches = totalTranches();
        return wantBal.add(_tranchesInWant(tranche, totalTranches));
    }

    /// @notice return staked tranches + tranche balance that this contract holds
    function totalTranches() public view returns (uint256) {
        IMultiRewards _multiRewards = multiRewards;
        uint256 stakedBal;

        if (address(_multiRewards) != address(0)) {
            stakedBal = _multiRewards.balanceOf(address(this));
        }

        return stakedBal.add(_balance(tranche));
    }

    /**
     * Perform any Strategy unwinding or other calls necessary to capture the
     * "free return" this Strategy has generated since the last time its core
     * position(s) were adjusted. Examples include unwrapping extra rewards.
     * This call is only used during "normal operation" of a Strategy, and
     * should be optimized to minimize losses as much as possible.
     *
     * This method returns any realized profits and/or realized losses
     * incurred, and should return the total amounts of profits/losses/debt
     * payments (in `want` tokens) for the Vault's accounting (e.g.
     * `want.balanceOf(this) >= _debtPayment + _profit`).
     *
     * `_debtOutstanding` will be 0 if the Strategy is not past the configured
     * debt limit, otherwise its value will be how far past the debt limit
     * the Strategy is. The Strategy's debt limit is configured in the Vault.
     *
     * NOTE: `_debtPayment` should be less than or equal to `_debtOutstanding`.
     *       It is okay for it to be less than `_debtOutstanding`, as that
     *       should only used as a guide for how much is left to pay back.
     *       Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     *
     * See `vault.debtOutstanding()`.
     */
    function prepareReturn(uint256 _debtOutstanding)
        internal
        virtual
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
        IERC20 _want = want;
        IERC20 _tranche = tranche;
        _debtPayment = _debtOutstanding;

        if (enabledStake) {
            _claimRewards();
        }

        uint256 wantBal = _balance(_want);
        uint256 totalAssets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        // should be true if working greatly
        if (debt < totalAssets) {
            // profit
            _profit = totalAssets - debt;
        } else {
            _loss = debt.sub(totalAssets);
        }

        uint256 toWithdraw = _debtOutstanding.add(_profit);

        if (toWithdraw > wantBal) {
            // (wantBal + wantInvested) - totalDebt + debtOutstanding - wantBal
            toWithdraw = toWithdraw - wantBal; // no underflow
            uint256 withdrawn = _divest(_wantsInTranche(_tranche, toWithdraw));

            uint256 withdrawalLoss;
            if (withdrawn < toWithdraw) {
                withdrawalLoss = toWithdraw - withdrawn; // no underflow
            }

            // when we withdraw we can lose money in the withdrawal
            if (withdrawalLoss < _profit) {
                _profit = _profit - withdrawalLoss; // no underflow
            } else {
                // Add withdrawal loss to loss, cancel profit
                _loss = _loss.add(withdrawalLoss.sub(_profit));
                _profit = 0;
            }

            wantBal = _balance(_want);

            // profit + _debtOutstanding must be <= wantbalance. Prioritise profit first
            if (wantBal < _profit) {
                _profit = wantBal;
                _debtPayment = 0;
            } else if (wantBal < _debtOutstanding.add(_profit)) {
                _debtPayment = wantBal.sub(_profit);
            }
        }
    }

    /**
     * Perform any adjustments to the core position(s) of this Strategy given
     * what change the Vault made in the "investable capital" available to the
     * Strategy. Note that all "free capital" in the Strategy after the report
     * was made is available for reinvestment. Also note that this number
     * could be 0, and you should handle that scenario accordingly.
     *
     * See comments regarding `_debtOutstanding` on `prepareReturn()`.
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
        uint256 wantBal = _balance(want);

        if (wantBal > _debtOutstanding) {
            _invest(wantBal - _debtOutstanding); // no underflow
        }
    }

    /**
     * Liquidate up to `_amountNeeded` of `want` of this strategy's positions,
     * irregardless of slippage. Any excess will be re-invested with `adjustPosition()`.
     * This function should return the amount of `want` tokens made available by the
     * liquidation. If there is a difference between them, `_loss` indicates whether the
     * difference is due to a realized loss, or if there is some other sitution at play
     * (e.g. locked funds) where the amount made available is less than what is needed.
     *
     * NOTE: The invariant `_liquidatedAmount + _loss <= _amountNeeded` should always be maintained
     */
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

        IERC20 _tranche = tranche;
        uint256 wantBal = _balance(want);

        if (_amountNeeded > wantBal) {
            uint256 toWithdraw = _amountNeeded - wantBal; // no underflow
            uint256 withdrawn = _divest(_wantsInTranche(_tranche, toWithdraw));
            if (withdrawn < toWithdraw) {
                _loss = toWithdraw - withdrawn; // no underflow
            }
        }

        _liquidatedAmount = _amountNeeded.sub(_loss);
    }

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `prepareReturn()` to
     * liquidate all of the Strategy's positions back to the Vault.
     *
     * @dev `amountFeed` is total balance held by the strategy incl. any prior balance
     */
    function liquidateAllPositions()
        internal
        override
        returns (uint256 amountFreed)
    {
        // TODO: Liquidate all positions and return the amount freed.
        _divest(totalTranches());
        amountFreed = _balance(want);
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    function prepareMigration(address _newStrategy) internal virtual override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
        IERC20 _tranche = tranche;

        IMultiRewards _multiRewards = multiRewards;

        // withdrawing amount 0 will cause to revert
        if (enabledStake && _multiRewards.balanceOf(address(this)) != 0) {
            _multiRewards.exit();
        }

        uint256 trancheBalance = _balance(_tranche);
        if (trancheBalance != 0) {
            _tranche.safeTransfer(_newStrategy, trancheBalance);
        }
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        view
        virtual
        override
        returns (address[] memory)
    {
        IERC20[] memory _rewardTokens = rewardTokens;
        uint256 length = _rewardTokens.length;
        address[] memory protected = new address[](length + 1);

        for (uint256 i; i < length; i++) {
            protected[i] = address(_rewardTokens[i]);
        }
        protected[length + 1] = address(tranche);

        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *  NOTE: WARNING: manipulatable and simple routing
     * @param _amount The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amount)
        public
        view
        virtual
        override
        returns (uint256)
    {
        if (_amount == 0) {
            return 0;
        }

        address WETH_ADDRESS = address(WETH);
        address _want = address(want);

        if (_want == WETH_ADDRESS) {
            return _amount;
        }

        uint256[] memory amounts =
            router.getAmountsOut(
                _amount,
                _getTokenOutPathV2(WETH_ADDRESS, _want)
            );

        return amounts[amounts.length - 1];
    }

    /* **** Internal Mutative functions **** */

    /// @notice deposit `want` to IdleCDO and mint AATranche or BBTranche
    /// @param _wantAmount amount of `want` to deposit
    /// @return trancheMinted : tranche tokens minted
    function _invest(uint256 _wantAmount)
        internal
        virtual
        returns (uint256 trancheMinted)
    {
        IERC20 _tranche = tranche;

        uint256 before = _balance(_tranche);

        _depositTranche(_wantAmount);

        trancheMinted = _balance(_tranche).sub(before);

        if (enabledStake && trancheMinted != 0) {
            multiRewards.stake(trancheMinted);
        }
    }

    /// @notice redeem `tranche` from IdleCDO and withdraw `want`
    /// @param _trancheAmount amount of `want` to deposit
    /// @return wantRedeemed : want redeemed
    function _divest(uint256 _trancheAmount)
        internal
        virtual
        returns (uint256 wantRedeemed)
    {
        IERC20 _want = want;

        if (enabledStake) {
            uint256 trancheBal = _balance(tranche);

            // if tranche to withdraw > current balance, withdraw
            if (_trancheAmount > trancheBal) {
                IMultiRewards _multiRewards = multiRewards;
                uint256 stakedBal = _multiRewards.balanceOf(address(this));

                uint256 toWithdraw =
                    stakedBal >= _trancheAmount - trancheBal // should be stakedBal == _trancheAmount - trancheBal
                        ? _trancheAmount - trancheBal // no underflow
                        : stakedBal;
                // withdraw
                if (toWithdraw != 0) {
                    _multiRewards.withdraw(toWithdraw);
                }
            }
        }

        uint256 before = _balance(_want);

        _withdrawTranche(_trancheAmount);

        wantRedeemed = _balance(_want).sub(before);
    }

    /// @notice claim liquidity mining rewards
    function _claimRewards() internal virtual {
        multiRewards.getReward();
    }

    /// @notice deposit specified underlying amount to idleCDO and mint tranche
    /// @dev when `want` is different from CDO underlying token, this method will be overridden by pararent contract
    /// @param _underlyingAmount underlying amount of idleCDO
    function _depositTranche(uint256 _underlyingAmount) internal virtual {
        function(uint256) external returns (uint256) _depositXX =
            isAATranche ? idleCDO.depositAA : idleCDO.depositBB;

        if (_underlyingAmount != 0) _depositXX(_underlyingAmount);
    }

    /// @notice redeem tranches and get `want`
    /// @dev when `want` is different from CDO underlying token, this method will be overridden by pararent contract
    /// @param _trancheAmount amount of `tranche`
    function _withdrawTranche(uint256 _trancheAmount) internal virtual {
        function(uint256) external returns (uint256) _withdrawXX =
            isAATranche ? idleCDO.withdrawAA : idleCDO.withdrawBB;

        if (_trancheAmount != 0) _withdrawXX(_trancheAmount);
    }

    /* **** Internal Helper functions **** */
    function _balance(IERC20 _token) internal view returns (uint256 balance) {
        balance = _token.balanceOf(address(this));
    }

    /// @dev convert `tranches` denominated in `want`
    /// @notice Usually idleCDO.underlyingToken is equal to the `want`
    function _tranchesInWant(IERC20 _tranche, uint256 trancheAmount)
        internal
        view
        virtual
        returns (uint256)
    {
        return _tranchesInUnderlyingToken(_tranche, trancheAmount);
    }

    /// @dev convert `tranches` to `underlyingToken`
    function _tranchesInUnderlyingToken(IERC20 _tranche, uint256 trancheAmount)
        internal
        view
        returns (uint256)
    {
        if (trancheAmount == 0) return 0;
        // price has the same decimals as underlying
        uint256 price = idleCDO.virtualPrice(address(_tranche));
        return trancheAmount.mul(price).div(EXP_SCALE);
    }

    /// @dev convert `wantAmount` denominated in `tranche`
    /// @notice Usually idleCDO.underlyingToken is equal to the `want`
    function _wantsInTranche(IERC20 _tranche, uint256 wantAmount)
        internal
        view
        virtual
        returns (uint256)
    {
        return _underlyingTokensInTranche(_tranche, wantAmount);
    }

    /// @dev convert `underlyingTokens` to `tranche`
    function _underlyingTokensInTranche(
        IERC20 _tranche,
        uint256 underlyingTokens
    ) internal view returns (uint256) {
        if (underlyingTokens == 0) return 0;
        return
            underlyingTokens.mul(EXP_SCALE).div(
                idleCDO.virtualPrice(address(_tranche))
            );
    }

    function _getTokenOutPathV2(address _tokenIn, address _tokenOut)
        internal
        view
        returns (address[] memory _path)
    {
        require(_tokenIn != _tokenOut, "strat/identical-address");
        address WETH_ADDRESS = address(WETH);
        bool isWeth = _tokenIn == WETH_ADDRESS || _tokenOut == WETH_ADDRESS;

        if (isWeth) {
            _path = new address[](2);
            _path[0] = _tokenIn;
            _path[1] = _tokenOut;
        } else {
            _path = new address[](3);
            _path[0] = _tokenIn;
            _path[1] = WETH_ADDRESS;
            _path[2] = _tokenOut;
        }
    }
}
