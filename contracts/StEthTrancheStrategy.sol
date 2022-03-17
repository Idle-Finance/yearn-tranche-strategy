// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../interfaces/lido/IStETH.sol";
import "../interfaces/lido/IWstETH.sol";
import "../interfaces/lido/StEthPriceFeed.sol";
import "../interfaces/curve/IStEthStableSwap.sol";

import {
    SafeERC20,
    SafeMath,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./Strategy.sol";

contract StEthTrancheStrategy is TrancheStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IStEthStableSwap public constant stableSwapSTETH =
        IStEthStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    StEthPriceFeed public constant priceFeed =
        StEthPriceFeed(0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6);

    IStETH public constant stETH =
        IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    IWstETH public constant wstETH =
        IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    uint256 private constant DENOMINATOR = 10_000;
    address private constant REFERRAL = address(0);
    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;

    uint256 public maximumSlippage = 50; //out of 10000. 50 = 0.5%

    receive() external payable {
        require(
            msg.sender == address(WETH) ||
                msg.sender == address(stableSwapSTETH),
            "strat/recieve-eth"
        );
    }

    constructor(
        address _vault,
        IIdleCDO _idleCDO,
        bool _isAATranche,
        IUniswapV2Router02 _router
    ) public TrancheStrategy(_vault, _idleCDO, _isAATranche, _router) {
        require(address(want) == address(WETH), "strat/want-ne-weth");
        require(_idleCDO.token() == address(stETH), "strat/cdo-steth");

        WETH.approve(address(stETH), type(uint256).max);
        stETH.approve(address(idleCDO), type(uint256).max);
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
            stableSwapSTETH.exchange{ value: _amount }(
                WETHID,
                STETHID,
                _amount,
                _amount
            );
        }
        uint256 amountIn = _balance(stETH).sub(_stEthBalanceBefore);

        // deposit steth to idle
        super._depositTranche(amountIn);
    }

    /// @notice redeem tranches and get steth
    /// @param _trancheAmount tranche amount to redeem
    function _withdrawTranche(uint256 _trancheAmount) internal override {
        uint256 _stEthBalanceBefore = _balance(stETH);

        // withraw tranche and get steth
        super._withdrawTranche(_trancheAmount);

        uint256 _amountIn = _balance(stETH).sub(_stEthBalanceBefore);

        // steth => eth
        uint256 slippageAllowance =
            _amountIn.mul(DENOMINATOR.sub(maximumSlippage)).div(DENOMINATOR);
        stableSwapSTETH.exchange(STETHID, WETHID, _amountIn, slippageAllowance);

        // eth => weth
        WETH.deposit{ value: address(this).balance }();
    }

    /// @dev NOTE: Unreliable price
    function ethToWant(uint256 _amount) public view override returns (uint256) {
        return _amount;
    }

    /// @dev override default behavior
    /// @notice
    function _getTrancheBalanceInWant(IERC20 _tranche)
        internal
        view
        override
        returns (uint256)
    {
        // underlying token of steth cdo is steth
        uint256 balancesInStEth = _getTrancheBalanceInUnderlying(_tranche);
        (uint256 stEthPrice, ) = priceFeed.safe_price();

        return balancesInStEth.mul(stEthPrice).div(_EXP_SCALE);
    }

    /// @dev convert `wantAmount` denominated in `tranche`
    function _wantsInTranche(IERC20 _tranche, uint256 wantAmount)
        internal
        view
        override
        returns (uint256)
    {
        (uint256 stEthPrice, ) = priceFeed.safe_price();

        uint256 uTokensInTranche =
            _underlyingTokensInTranche(_tranche, wantAmount);
        return uTokensInTranche.mul(_EXP_SCALE).div(stEthPrice);
    }

    function updateMaxSlippage(uint256 _maximumSlippage) external onlyKeepers {
        require(_maximumSlippage <= DENOMINATOR, "strat/invalid-slippage");
        maximumSlippage = _maximumSlippage;
    }
}
