pragma solidity ^0.5.13;

import "./ERC/ERC721Metadata.sol";
import "../utils/Ownable.sol";
import "../math/SafeMath.sol";

contract MineralNFT is ERC721Metadata, Ownable {
    using SafeMath for uint256;

    uint256 private _finalTokenId = 0;

    constructor (string memory name, string memory symbol) ERC721Metadata(name, symbol) public {
    }

    function _generateTokenId() internal returns (uint256) {
        return _finalTokenId++;
    }

    /*
        [createItem() 에 대한 피드백]
        가스를 절약하기 위해 public 에서 external 으로 수정
    */
    function createItem(address to, string calldata jsonUrl) external onlyOwner returns (uint256) {
        uint256 id = _generateTokenId();
        _mint(to, id);
        _setTokenURI(id, jsonUrl);
        return id;
    }

    function burnItem(uint256 tokenId) external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "msg.sender is not token owner");
        _burn(_msgSender(), tokenId);
    }
}