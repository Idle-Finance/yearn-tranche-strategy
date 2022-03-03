// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/idle/IIdleCDO.sol";
import "../interfaces/IERC20Metadata.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 private immutable _EXP_SCALE;

    IIdleCDO public idleCDO;
    IERC20Metadata public tranche;
    bool public isAATranche;

    constructor(
        address _vault,
        IIdleCDO _idleCDO,
        bool _isAATranche
    ) public BaseStrategy(_vault) {
        require(
            address(want) == _idleCDO.token(),
            "Vault want is different from Idle token underlying"
        );

        isAATranche = _isAATranche;
        maxReportDelay = 6300;
        profitFactor = 100;
        debtThreshold = 0;

        idleCDO = _idleCDO;
        isAATranche = _isAATranche;
        IERC20Metadata _tranche =
            IERC20Metadata(
                _isAATranche ? _idleCDO.AATranche() : _idleCDO.BBTranche()
            );
        tranche = _tranche;
        _EXP_SCALE = 10**uint256(_tranche.decimals());

        want.safeApprove(address(_idleCDO), type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return string(abi.encodePacked("Strategy", tranche.name()));
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
    function estimatedTotalAssets() public view override returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        IERC20Metadata _tranche = tranche;
        uint256 balances = _tranche.balanceOf(address(this));
        uint256 price = idleCDO.tranchePrice(address(_tranche));
        return
            want.balanceOf(address(this)).add(
                balances.mul(price).div(_EXP_SCALE)
            );
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

        uint256 wantBal = _balance(_want);
        uint256 totalAssets = wantBal.add(_trancheInWant(_tranche));

        // stratに貸したた金
        uint256 debt = vault.strategies(address(this)).totalDebt;

        // 利益出てるなら true
        if (totalAssets >= debt) {
            _profit = totalAssets.sub(debt);
            //　引き出す totalAssets - totalDebt  + debtOutstanding
            uint256 toWithdraw = _profit.add(_debtOutstanding);

            if (toWithdraw > wantBal) {
                //we step our withdrawals.
                uint256 withdrawn = _divest(_toTranche(_tranche, toWithdraw));
                if (withdrawn < toWithdraw) {
                    //  損失
                    _loss = toWithdraw.sub(withdrawn);
                }
            }
            wantBal = _balance(_want);

            //net off profit and loss
            if (_profit >= _loss) {
                _profit = _profit - _loss; // totalAssets - totalDebt - loss
                _loss = 0;
            } else {
                _profit = 0;
                _loss = _loss - _profit;
            }

            //profit + _debtOutstanding must be <= wantbalance. Prioritise profit first
            if (wantBal < _profit) {
                _profit = wantBal;
            } else if (wantBal < toWithdraw) {
                _debtPayment = wantBal.sub(_profit);
            } else {
                _debtPayment = _debtOutstanding;
            }
        } else {
            _loss = debt.sub(totalAssets);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
    }

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
            uint256 toWithdraw = _amountNeeded.sub(wantBal);
            uint256 withdrawn = _divest(_toTranche(_tranche, _amountNeeded));
            if (withdrawn < toWithdraw) {
                _loss = toWithdraw.sub(withdrawn);
            }
        }

        _liquidatedAmount = _amountNeeded.sub(_loss);
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 amountFreed)
    {
        // TODO: Liquidate all positions and return the amount freed.
        uint256 trancheBalance = _balance(tranche);
        liquidatePosition(trancheBalance); // @note wantBalance diff ?
        amountFreed = _balance(want);
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
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
        override
        returns (address[] memory)
    {}

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
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }

    function _divest(uint256 _trancheAmount)
        internal
        returns (uint256 wantRedeemed)
    {
        IERC20 _want = want;
        function(uint256) external returns (uint256) withdrawTranche =
            isAATranche ? idleCDO.withdrawAA : idleCDO.withdrawBB;

        uint256 before = _balance(_want);

        withdrawTranche(_trancheAmount);

        wantRedeemed = _balance(_want).sub(before);
    }

    function _balance(IERC20 _token) internal view returns (uint256 balance) {
        balance = _token.balanceOf(address(this));
    }

    function _trancheInWant(IERC20 _tranche)
        internal
        view
        returns (uint256 balancesInWant)
    {
        uint256 price = idleCDO.tranchePrice(address(_tranche));
        balancesInWant = _tranche.balanceOf(address(this)).mul(price).div(
            _EXP_SCALE
        );
    }

    function _toTranche(IERC20 _tranche, uint256 wantAmount)
        internal
        returns (uint256)
    {
        return
            wantAmount.mul(_EXP_SCALE).div(
                idleCDO.tranchePrice(address(_tranche))
            );
    }
}
