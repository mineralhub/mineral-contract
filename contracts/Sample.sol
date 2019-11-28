pragma solidity ^0.5.13;

contract Sample {
    address private _owner;
    uint private _one;
    uint private _two;

    constructor() public {
        _owner = msg.sender;
    }

    function setNumber(uint one, uint two) public {
        _one = one;
        _two = two;
    }

    function getNumber() public view returns (uint, uint)  {
        return (_one, _two);
    }
}