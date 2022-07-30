// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Strategy.sol";

import "../interfaces/lido/IStETH.sol";
import "../interfaces/lido/IStEthPriceFeed.sol";
import "../interfaces/curve/IStEthStableSwap.sol";

/// @title StETH Tranche Strategy
/// @author bakuchi
contract StEthTrancheStrategy is TrancheStrategy {
    IStEthStableSwap public constant stableSwapSTETH = IStEthStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    IStEthPriceFeed public constant priceFeed = IStEthPriceFeed(0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6);

    IStETH public constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    uint256 private constant DENOMINATOR = 10_000;

    address private constant REFERRAL = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814; // Idle finance Treasury League multisig

    int128 private constant WETHID = 0;

    int128 private constant STETHID = 1;

    uint256 public maximumSlippage = 50; // out of 10000. 50 = 0.5%

    bool public isAllowedUnsafePrice;

    event UpdateMaxSlippage(uint256 _oldSlippage, uint256 _newSlippage);
    event UpdateApprovalUnsafePrice(bool _isAllowedUnsafePrice);

    receive() external payable {
        require(msg.sender == address(WETH) || msg.sender == address(stableSwapSTETH), "strat/recieve-eth");
    }

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
    )
        public
        TrancheStrategy(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _idleCDO,
            _isAATranche,
            _rewardTokens,
            _gauge,
            _dp,
            _healthCheck
        )
    {
        require(address(want) == address(WETH), "strat/want-ne-weth");
        require(_idleCDO.token() == address(stETH), "strat/cdo-steth");

        WETH.approve(address(stETH), type(uint256).max);
        stETH.approve(address(_idleCDO), type(uint256).max);
        stETH.approve(address(stableSwapSTETH), type(uint256).max);
    }

    /// @notice deposit steth to idleCDO and mint tranche
    /// @param _amount eth amount to invest
    function _depositTranche(uint256 _amount) internal override {
        uint256 _stEthBalanceBefore = _balance(stETH);

        // weth => eth
        WETH.withdraw(_amount);

        // eth => steth
        // test if we should buy instead of mint
        uint256 out = stableSwapSTETH.get_dy(WETHID, STETHID, _amount);
        if (out < _amount) {
            stETH.submit{ value: _amount }(REFERRAL);
        } else {
            stableSwapSTETH.exchange{ value: _amount }(WETHID, STETHID, _amount, _amount);
        }
        uint256 amountIn = _balance(stETH).sub(_stEthBalanceBefore);

        // deposit steth to idle
        super._depositTranche(amountIn);
    }

    /// @notice redeem tranches and get steth
    /// @param _trancheAmount tranche amount to redeem
    function _withdrawTranche(uint256 _trancheAmount) internal override {
        uint256 _stEthBalanceBefore = _balance(stETH);
        uint256 _trancheBalance = _balance(tranche);

        // fix rounding error
        if (_trancheBalance < _trancheAmount) {
            _trancheAmount = _trancheBalance;
        }

        // withraw tranche and get steth
        super._withdrawTranche(_trancheAmount);

        uint256 _amountIn = _balance(stETH).sub(_stEthBalanceBefore);

        // steth => eth
        uint256 slippageAllowance = _amountIn.mul(DENOMINATOR.sub(maximumSlippage)).div(DENOMINATOR);
        stableSwapSTETH.exchange(STETHID, WETHID, _amountIn, slippageAllowance);

        // eth => weth
        WETH.deposit{ value: address(this).balance }();
    }

    /// @dev NOTE: Unreliable price
    function ethToWant(uint256 _amount) public view override returns (uint256) {
        return _amount;
    }

    /// @dev convert `tranches` denominated in `want`
    /// @notice Usually idleCDO.underlyingToken is equal to the `want`
    function _tranchesInWant(IERC20 _tranche, uint256 _trancheAmount) internal view override returns (uint256) {
        (uint256 stEthPrice, bool isSafe) = priceFeed.current_price();
        require(isSafe || isAllowedUnsafePrice, "strat/price-unsafe");

        uint256 amountsInStEth = super._tranchesInWant(_tranche, _trancheAmount);
        return amountsInStEth.mul(stEthPrice).div(EXP_SCALE);
    }

    /// @dev for debugging
    function wantBal() external view returns (uint256) {
        return _balance(want);
    }

    /// @dev convert `_wantAmount` denominated in `tranche`
    /// NOTE: underlying token is equal to steth here
    function _wantsInTranche(IERC20 _tranche, uint256 _wantAmount) internal view override returns (uint256) {
        (uint256 stEthPrice, bool isSafe) = priceFeed.current_price();
        require(isSafe || isAllowedUnsafePrice, "strat/price-unsafe");

        // _wantAmount to stEthAmount (underlyingAmount)
        uint256 stEthAmount = _wantAmount.mul(EXP_SCALE).div(stEthPrice);
        // underlying to tranche amount
        return _underlyingTokensInTranche(_tranche, stEthAmount);
    }

    function setMaxSlippage(uint256 _maximumSlippage) external onlyKeepers {
        require(_maximumSlippage <= DENOMINATOR, "strat/invalid-slippage");

        uint256 oldMaximumSlippage = maximumSlippage;
        maximumSlippage = _maximumSlippage;

        emit UpdateMaxSlippage(oldMaximumSlippage, _maximumSlippage);
    }

    /// @notice set approval unsafe price
    function setApprovalUnsafePrice(bool _isAllowedUnsafePrice) external onlyVaultManagers {
        isAllowedUnsafePrice = _isAllowedUnsafePrice;

        emit UpdateApprovalUnsafePrice(_isAllowedUnsafePrice);
    }
}
