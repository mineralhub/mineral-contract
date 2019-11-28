pragma solidity ^0.5.13;

contract Ownable {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require (msg.sender == owner, "only Onwer");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0))
            owner = newOwner;
    }
}