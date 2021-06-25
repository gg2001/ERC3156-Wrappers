// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.5;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "./interfaces/UniswapV3FlashBorrowerLike.sol";
import "./interfaces/UniswapV3PoolLike.sol";
import "./libraries/PoolAddress.sol";
import "./libraries/CallbackValidation.sol";


contract UniswapV3ERC3156 is IERC3156FlashLender, UniswapV3FlashBorrowerLike {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // CONSTANTS
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint24 public constant fee = 3000;
    address public immutable factory;

    // DEFAULT TOKENS
    address public immutable weth;
    address public immutable dai;

    /// @param factory_ Uniswap v3 UniswapV3Factory address
    /// @param weth_ Weth contract used in Uniswap v3 Pools
    /// @param dai_ Dai contract used in Uniswap v3 Pools
    constructor(address factory_, address weth_, address dai_) {
        factory = factory_;
        weth = weth_;
        dai = dai_;
    }

    /**
     * @dev Get the Uniswap Pool Key that will be used as the source of a loan. The opposite token will be Weth, except for Weth that will be Dai.
     * @param token The loan currency.
     * @return The Uniswap V3 Pool Key that will be used as the source of the flash loan.
     */
    function getPoolKey(address token) public view returns (PoolAddress.PoolKey memory) {
        address tokenOther = token == weth ? dai : weth;
        return PoolAddress.getPoolKey(token, tokenOther, fee);
    }

    /**
     * @dev Get the Uniswap Pool that will be used as the source of a loan. The opposite token will be Weth, except for Weth that will be Dai.
     * @param token The loan currency.
     * @return The Uniswap V3 Pool that will be used as the source of the flash loan.
     */
    function getPoolAddress(address token) public view returns (address) {
        return PoolAddress.computeAddress(factory, getPoolKey(token));
    }

    /**
     * @dev From ERC-3156. The amount of currency available to be lended.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view override returns (uint256) {
        address pairAddress = getPoolAddress(token);
        if (pairAddress != address(0)) {
            return IERC20(token).balanceOf(pairAddress);
        }
        return 0;
    }

    /**
     * @dev From ERC-3156. The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        require(getPoolAddress(token) != address(0), "Unsupported currency");
        return amount.mul(fee).div(1e6);
    }

    /**
     * @dev From ERC-3156. Loan `amount` tokens to `receiver`, which needs to return them plus fee to this contract within the same transaction.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param userData A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory userData) external override returns(bool) {
        PoolAddress.PoolKey memory poolKey = getPoolKey(token);
        (uint256 amount0, uint256 amount1) = token == poolKey.token0 ? (amount, uint256(0)) : (uint256(0), amount);
        UniswapV3PoolLike pool = UniswapV3PoolLike(PoolAddress.computeAddress(factory, poolKey));
        bytes memory data = abi.encode(
            msg.sender,
            receiver,
            amount,
            poolKey,
            userData
        );
        pool.flash(address(this), amount0, amount1, data);
        return true;
    }

    /// @dev Uniswap flash loan callback. It sends the value borrowed to `receiver`, and takes it back plus a `flashFee` after the ERC3156 callback.
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        // decode data
        (
            address origin,
            IERC3156FlashBorrower receiver,
            uint256 amount,
            PoolAddress.PoolKey memory poolKey,
            bytes memory userData
        ) = abi.decode(data, (address, IERC3156FlashBorrower, uint256, PoolAddress.PoolKey, bytes));
        // access control
        CallbackValidation.verifyCallback(factory, poolKey);

        (address token, uint256 fees) = fee0 > 0 ? (poolKey.token0, fee0) : (poolKey.token1, fee1);

        // send the borrowed amount to the receiver
        IERC20(token).transfer(address(receiver), amount);
        // do whatever the user wants
        require(
            receiver.onFlashLoan(origin, token, amount, fees, userData) == CALLBACK_SUCCESS,
            "Callback failed"
        );
        // retrieve the borrowed amount plus fee from the receiver and send it to the uniswap pair
        IERC20(token).transferFrom(address(receiver), msg.sender, amount.add(fees));
    }
}