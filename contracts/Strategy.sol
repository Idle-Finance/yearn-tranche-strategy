// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { BaseStrategy } from "@yearnvaults/contracts/BaseStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/idle/IIdleCDO.sol";
import "../interfaces/idle/ILiquidityGaugeV3.sol";
import "../interfaces/idle/IDistributorProxy.sol";
import "../interfaces/IBaseFeeOracle.sol";
import "../interfaces/yswap/ITradeFactory.sol";
import "../interfaces/IERC20Metadata.sol";
import "../interfaces/IWETH.sol";

/// @title Base Tranche Strategy
/// @author bakuchi
/// @dev in case of emergency,
/// if Idle Gauge have some problems,
/// - disable staking to the gauge
/// - revoke the gauge by calling `setGauge(address(0))`
/// Migrations
/// set `checkStakedBeforeMigrating` false by calling `SetCheckStakedBeforeMigrating`
/// and then `migrate()`
/// it is possible for vault manageres to mannually invest/dinvest/claimRewards
/// mannually claiming rewards can bypass `enabledStake` flag check

contract TrancheStrategy is BaseStrategy {
    /// @dev `tranche` has fixed 18 decimals regardless of the underlying
    uint256 internal constant EXP_SCALE = 1e18;

    IBaseFeeOracle internal constant BASE_FEE_ORACLE = IBaseFeeOracle(0xb5e1CAcB567d98faaDB60a1fD4820720141f064F);

    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IERC20Metadata public immutable tranche;

    IIdleCDO public immutable idleCDO;

    /// @notice junior or senior. AATranche is Senior tranche. BB is Junior one.
    bool public immutable isAATranche;

    /// @notice https://github.com/Idle-Finance/idle-gauges/tree/main/contracts
    /// @dev tokens will be staked if the `enableStake` is true. some rewards are distributed.
    ILiquidityGaugeV3 public gauge;

    /// @notice IDLE distributor contract
    /// @dev  when tokens are staked to gauge, IDLE are claimable
    IDistributorProxy public distributorProxy;

    /// @notice default: True
    /// @dev  in case of emergency we have the option to turn it off and
    /// not interact with gauge during migration if we have to.
    bool public checkStakedBeforeMigrating = true;

    /// @dev we assume gauge address is not zero address if this flag is true.
    bool public enabledStake;

    /// @notice yswap ref
    address public tradeFactory;

    /// @dev reward tokens to swap for the want through yswap i.e trade factory
    IERC20[] internal rewardTokens;

    event UpdateCheckStakedBeforeMigrating(bool _checkStakedBeforeMigrating);

    /**
     * @notice
     *  Initializes the Strategy, this is called only once, when the
     *  contract is deployed.
     * @dev `_vault` should implement `VaultAPI`.
     * @param _vault The address of the Vault responsible for this Strategy.
     * @param _strategist The address to assign as `strategist`.
     * The strategist is able to change the reward address
     * @param _rewards  The address to use for pulling rewards.
     * @param _keeper The adddress of the _keeper. _keeper
     * can harvest and tend a strategy.
     * @param _idleCDO  The address of IdleCDO
     * @param _isAATranche  tranche AA or BB
     * @param _rewardTokens  The address to be swapped for the want
     * @param _gauge  The address to the Idle gauge
     * @param _dp  The address of IDLE distributorProxy
     * @param _healthCheck  The address to use for health check
     */
    constructor(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        IIdleCDO _idleCDO,
        bool _isAATranche,
        IERC20[] memory _rewardTokens,
        ILiquidityGaugeV3 _gauge,
        IDistributorProxy _dp,
        address _healthCheck
    ) public BaseStrategy(_vault) {
        require(_healthCheck != address(0), "strat/zero-address");

        idleCDO = _idleCDO;
        isAATranche = _isAATranche;

        // can be empaty array
        rewardTokens = _rewardTokens; // set `tradeFactory` address after deployment.

        // can be zero address
        gauge = _gauge;
        distributorProxy = _dp;

        // non-zero address
        healthCheck = _healthCheck;

        // BaseStrategy
        strategist = _strategist;
        rewards = _rewards;
        keeper = _keeper;

        IERC20Metadata _tranche = IERC20Metadata(_isAATranche ? _idleCDO.AATranche() : _idleCDO.BBTranche());
        tranche = _tranche;

        // tranche would have fixed 18 decimals regardless of underlying
        // `EXP_SCALE` is fixed
        require(_tranche.decimals() == 18, "strat/decimals-18");

        want.safeApprove(address(_idleCDO), type(uint256).max);
        if (address(_gauge) != address(0)) {
            _tranche.approve(address(_gauge), type(uint256).max);
        }
    }

    // ******** PERMISSIONED METHODS ************

    function setCheckStakedBeforeMigrating(bool _checkStakedBeforeMigrating) external onlyGovernance {
        checkStakedBeforeMigrating = _checkStakedBeforeMigrating;

        emit UpdateCheckStakedBeforeMigrating(_checkStakedBeforeMigrating);
    }

    /// @notice enable staking
    function enableStaking() external onlyVaultManagers {
        require(tradeFactory != address(0), "strat/tf-zero"); // first set tradeFactory
        require(address(gauge) != address(0), "strat/gauge-zero"); // first set gauge

        enabledStake = true;
    }

    /// @notice withdraw staked and disable staking
    /// @dev to revoke Gauge contract use `setGauge` method
    function disableStaking() external onlyVaultManagers {
        enabledStake = false; // reset
    }

    /// @notice set gauge contract
    /// @dev revoke or approve gauge contract
    function setGauge(ILiquidityGaugeV3 _gauge) external onlyGovernance {
        IERC20 _tranche = tranche; // caching

        ILiquidityGaugeV3 _oldGauge = gauge; // read old gauge
        gauge = _gauge; // set new gauge

        if (address(_oldGauge) != address(0)) {
            // Exit
            uint256 bal = _oldGauge.balanceOf(address(this));
            if (bal != 0) {
                _oldGauge.withdraw(bal, true);
            }
            // revoke
            _tranche.approve(address(_oldGauge), 0);
        }

        // approve & stake
        if (address(_gauge) != address(0)) {
            uint256 trancheBal = _balance(_tranche);
            _tranche.approve(address(_gauge), type(uint256).max); // approve

            // stake
            if (enabledStake && trancheBal != 0) {
                _gauge.deposit(trancheBal, address(this), false);
            }
        }
    }

    /// @notice set distributor proxy contract
    function setDistributorProxy(IDistributorProxy _dp) external onlyGovernance {
        IDistributorProxy _oldDp = distributorProxy; // read old distributor proxy
        distributorProxy = _dp; // set new distributor proxy

        // Claim
        address _gauge = address(gauge);
        if (enabledStake && address(_oldDp) != address(0) && _gauge != address(0)) {
            _oldDp.distribute(_gauge);
        }
    }

    /// @notice set reward tokens
    function setRewardTokens(IERC20[] memory _rewardTokens) external onlyVaultManagers {
        bool useTradeFactory = tradeFactory != address(0);

        if (useTradeFactory) {
            _revokeTradeFactoryPermissions();
        }

        rewardTokens = _rewardTokens; // set

        if (useTradeFactory) {
            _approveTradeFactory();
        }
    }

    /// @dev first a role must be granted by _newTradeFactory
    /// NOTE: https://github.com/yearn/yswaps/blob/7410951c9514dfa2abdcf82477cb4f92e1da7dd5/solidity/contracts/TradeFactory/TradeFactoryPositionsHandler.sol#L80
    ///      to revoke tradeFactory set address(0) as the parameter
    function updateTradeFactory(address _newTradeFactory) public onlyGovernance {
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
            // a role must be granted beforehand
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

    /// @notice AA tranche means Senior tranche which achieves a greater and leveraged yield by dragging more risk,
    /// BB tranche means Junior one here.
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
    function estimatedTotalAssets() public view virtual override returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        uint256 wantBal = _balance(want);
        uint256 totalTranches = totalTranches();
        return wantBal.add(_tranchesInWant(tranche, totalTranches));
    }

    /// @notice return staked tranches + tranche balance that this contract holds
    function totalTranches() public view returns (uint256) {
        ILiquidityGaugeV3 _gauge = gauge;
        uint256 stakedBal;
        // NOTE: a conversion rate between gauge token and tranche is always 1.
        // simply add each balances
        if (address(_gauge) != address(0)) {
            stakedBal = _gauge.balanceOf(address(this));
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

        // Get total debt, total assets (want+idle)
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;
        uint256 totalAssets = estimatedTotalAssets();

        _profit = totalAssets > totalDebt ? totalAssets - totalDebt : 0; // no underflow

        // To withdraw = profit from lending + _debtOutstanding
        uint256 toFree = _debtOutstanding.add(_profit);

        uint256 freed;
        // In the case want is not enough, divest from idle
        (freed, _loss) = liquidatePosition(toFree);

        _debtPayment = _debtOutstanding >= freed ? freed : _debtOutstanding; // min

        // net out PnL
        if (_profit > _loss) {
            _profit = _profit - _loss; // no underflow
            _loss = 0;
        } else {
            _loss = _loss - _profit; // no underflow
            _profit = 0;
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

        if (enabledStake) {
            _claimRewards();
        }

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
            // divest some of tranches
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
    function liquidateAllPositions() internal override returns (uint256 amountFreed) {
        // TODO: Liquidate all positions and return the amount freed.
        _divest(totalTranches());
        amountFreed = _balance(want);
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    function prepareMigration(address _newStrategy) internal virtual override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
        IERC20 _tranche = tranche;

        // rewards
        IERC20[] memory _rewardTokens = rewardTokens;
        uint256 length = _rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            _rewardTokens[i].safeTransfer(_newStrategy, _rewardTokens[i].balanceOf(address(this)));
        }

        // gauge token
        ILiquidityGaugeV3 _gauge = gauge;

        if (checkStakedBeforeMigrating && address(_gauge) != address(0)) {
            uint256 toWithdraw = _gauge.balanceOf(address(this));
            if (toWithdraw != 0) _gauge.withdraw(toWithdraw, false);
        }

        // tranche
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
    /// @dev in case of emergency we have the option to turn `checkStakedBeforeMigrating` off
    function protectedTokens() internal view virtual override returns (address[] memory) {
        IERC20[] memory _rewardTokens = rewardTokens;
        uint256 length = _rewardTokens.length;

        address[] memory protected;

        // gov can sweep *any token excluding `want`*
        if (msg.sender == governance()) {
            return protected;
        }

        // work successfully
        if (checkStakedBeforeMigrating) {
            protected = new address[](length + 2);
            protected[length] = address(tranche);
            protected[length + 1] = address(gauge);
        } else {
            // escape hatche as we can during an emergency.
            // skip protecting tranche and gauge token
            protected = new address[](length);
        }

        for (uint256 i; i < length; i++) {
            protected[i] = address(_rewardTokens[i]);
        }

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
    function ethToWant(uint256 _amount) public view virtual override returns (uint256) {}

    /**
     * @notice
     *  Provide a signal to the keeper that `harvest()` should be called. The
     *  keeper will provide the estimated gas cost that they would pay to call
     *  `harvest()`, and this function should use that estimate to make a
     *  determination if calling it is "worth it" for the keeper. This is not
     *  the only consideration into issuing this trigger, for example if the
     *  position would be negatively affected if `harvest()` is not called
     *  shortly, then this can return `true` even if the keeper might be "at a
     *  loss" (keepers are always reimbursed by Yearn).
     * @return `true` if `harvest()` should be called, `false` otherwise.
     */
    function harvestTrigger(uint256 callCostInWei) public view virtual override returns (bool) {
        return BASE_FEE_ORACLE.isCurrentBaseFeeAcceptable() && super.harvestTrigger(callCostInWei);
    }

    // ************************* External Invest/Divest methods *************************

    function invest(uint256 _wantAmount) external onlyVaultManagers {
        _invest(_wantAmount);
    }

    function divest(uint256 _tokensToWithdraw) external onlyVaultManagers {
        _divest(_tokensToWithdraw);
    }

    function claimRewards() external onlyVaultManagers {
        _claimRewards();
    }

    /* **** Internal Mutative functions **** */

    /// @notice deposit `want` to IdleCDO and mint AATranche or BBTranche
    /// @param _wantAmount amount of `want` to deposit
    /// @return trancheMinted : tranche tokens minted
    function _invest(uint256 _wantAmount) internal virtual returns (uint256 trancheMinted) {
        IERC20 _tranche = tranche;

        uint256 before = _balance(_tranche);

        _depositTranche(_wantAmount);

        trancheMinted = _balance(_tranche).sub(before);

        if (enabledStake && trancheMinted != 0) {
            gauge.deposit(trancheMinted, address(this), false);
        }
    }

    /// @notice redeem `tranche` from IdleCDO and withdraw `want`
    /// @param _trancheAmount amount of tranche needed
    /// @return wantRedeemed : want redeemed
    function _divest(uint256 _trancheAmount) internal virtual returns (uint256 wantRedeemed) {
        IERC20 _want = want;

        uint256 trancheBal = _balance(tranche);

        // if tranches to withdraw > current balance, withdraw staked tranches from gauge
        if (_trancheAmount > trancheBal) {
            ILiquidityGaugeV3 _gauge = gauge;

            uint256 stakedBal = _gauge.balanceOf(address(this));
            // NOTE: a conersion rate between gauge token and tranche is always 1.
            // due to rounding error, `trancheAmount - trancheBal` may be greater than `stakedBal`.
            // get smaller one here to be sure that this strategy don't withdraw amounts greater than actual balance.
            uint256 toWithdraw = Math.min(stakedBal, _trancheAmount - trancheBal); // no underflow

            if (toWithdraw != 0) _gauge.withdraw(toWithdraw, false);
        }

        uint256 before = _balance(_want);

        _withdrawTranche(_trancheAmount);

        wantRedeemed = _balance(_want).sub(before);
    }

    /// @notice claim liquidity mining rewards
    function _claimRewards() internal virtual {
        IDistributorProxy _dp = distributorProxy;
        ILiquidityGaugeV3 _gauge = gauge;

        // Claim some rewards
        _gauge.claim_rewards(address(this), address(this));

        // Claim IDLE
        if (address(_dp) != address(0)) {
            _dp.distribute(address(_gauge));
        }
    }

    /// @notice deposit specified underlying amount to idleCDO and mint tranche
    /// @dev when `want` is different from CDO underlying token, this method will be overridden by pararent contract
    /// @param _underlyingAmount underlying amount of idleCDO
    function _depositTranche(uint256 _underlyingAmount) internal virtual {
        function(uint256) external returns (uint256) depositXX = isAATranche ? idleCDO.depositAA : idleCDO.depositBB;

        if (_underlyingAmount != 0) depositXX(_underlyingAmount);
    }

    /// @notice redeem tranches and get `want`
    /// @dev when `want` is different from CDO underlying token, this method will be overridden by pararent contract
    /// @param _trancheAmount amount of `tranche`
    function _withdrawTranche(uint256 _trancheAmount) internal virtual {
        function(uint256) external returns (uint256) withdrawXX = isAATranche ? idleCDO.withdrawAA : idleCDO.withdrawBB;

        if (_trancheAmount != 0) withdrawXX(_trancheAmount);
    }

    /* **** Internal Helper functions **** */
    function _balance(IERC20 _token) internal view returns (uint256 balance) {
        balance = _token.balanceOf(address(this));
    }

    /// @dev convert `tranches` denominated in `want`
    /// @notice Usually idleCDO.underlyingToken is equal to the `want`
    function _tranchesInWant(IERC20 _tranche, uint256 _trancheAmount) internal view virtual returns (uint256) {
        return _tranchesInUnderlyingToken(_tranche, _trancheAmount);
    }

    /// @dev convert `tranches` to `underlyingToken`
    function _tranchesInUnderlyingToken(IERC20 _tranche, uint256 _trancheAmount) internal view returns (uint256) {
        if (_trancheAmount == 0) return 0;
        // price has the same decimals as underlying
        uint256 price = idleCDO.virtualPrice(address(_tranche));
        return _trancheAmount.mul(price).div(EXP_SCALE);
    }

    /// @dev convert `_wantAmount` denominated in `tranche`
    /// @notice Usually idleCDO.underlyingToken is equal to the `want`
    function _wantsInTranche(IERC20 _tranche, uint256 _wantAmount) internal view virtual returns (uint256) {
        return _underlyingTokensInTranche(_tranche, _wantAmount);
    }

    /// @dev convert `_underlyingTokens` to `tranche`
    function _underlyingTokensInTranche(IERC20 _tranche, uint256 _underlyingTokens) internal view returns (uint256) {
        if (_underlyingTokens == 0) return 0;
        return _underlyingTokens.mul(EXP_SCALE).div(idleCDO.virtualPrice(address(_tranche)));
    }
}
