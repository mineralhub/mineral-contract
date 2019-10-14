pragma solidity ^0.5.4;

contract IERC20Receiver {
    function onERC20Received(address from, uint256 amount, bytes memory data)
    public returns (bool);
}