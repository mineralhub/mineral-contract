pragma solidity ^0.5.4;

import "./ERC/ERC721Metadata.sol";
import "../utils/Ownable.sol";
import "../math/SafeMath.sol";

contract MineralNFT is ERC721Metadata, Ownable {
    using SafeMath for uint256;

    constructor (string memory name, string memory symbol) ERC721Metadata(name, symbol) public {
    }

    function createItem(address to, string memory jsonUrl) public onlyOwner returns (uint256) {
        uint256 id = _totalSupply();
        _mint(to, id);
        _setTokenURI(id, jsonUrl);
        return id;
    }
}