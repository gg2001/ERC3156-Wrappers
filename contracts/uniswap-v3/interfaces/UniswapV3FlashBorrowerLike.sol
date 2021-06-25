// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.5;


interface UniswapV3FlashBorrowerLike {
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}
