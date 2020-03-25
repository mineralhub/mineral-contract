pragma solidity ^0.5.11;

contract IERC20Receiver {
    function onERC20Received(address from, uint256 amount, bytes calldata data)
    external returns (bool);
}