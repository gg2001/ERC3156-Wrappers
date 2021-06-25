// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.5;

import '../interfaces/UniswapV3PoolLike.sol';
import './PoolAddress.sol';

library CallbackValidation {
    function verifyCallback(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view returns (UniswapV3PoolLike pool) {
        return verifyCallback(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    function verifyCallback(address factory, PoolAddress.PoolKey memory poolKey)
        internal
        view
        returns (UniswapV3PoolLike pool)
    {
        pool = UniswapV3PoolLike(PoolAddress.computeAddress(factory, poolKey));
        require(msg.sender == address(pool));
    }
}
