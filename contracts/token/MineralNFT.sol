pragma solidity ^0.5.11;

import "./ERC/ERC721Full.sol";
import "./ERC/IERC721MultiReceiver.sol";
import "../utils/Ownable.sol";
import "../utils/Address.sol";
import "../math/SafeMath.sol";

contract MineralNFT is ERC721Full, Ownable {
    using SafeMath for uint256;
    using Address for address;

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    uint256 private _finalTokenId = 0;

    constructor (string memory name, string memory symbol) ERC721Full(name, symbol) public {
    }

    function _generateTokenId() internal returns (uint256) {
        return ++_finalTokenId;
    }

    function createItem(address to, string calldata jsonUrl) external onlyOwner returns (uint256) {
        uint256 id = _generateTokenId();
        _mint(to, id);
        _setTokenURI(id, jsonUrl);
        return id;
    }

    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        return _tokensOfOwner(owner);
    }

    function ownerTokenLength(address owner) external view returns (uint256) {
        return _tokensOfOwner(owner).length;
    }

    function safeMultiTransfer(address to, uint256[] calldata ids, bytes calldata data) external {
        require (ids.length > 0, "ids is empty");
        for(uint i = 0; i < ids.length; i++) {
            transferFrom(_msgSender(), to, ids[i]);
        }
        require(_checkOnERC721MultiReceived(to, ids, data), "ERC721: transfer to non onERC721MultiReceived implementer");
    }

    function burnItems(uint256[] calldata ids) external {
        require (ids.length > 0, "ids is empty");
        for(uint i = 0; i < ids.length; i++) {
            _burnItem(ids[i]);
        }
    }

    function _burnItem(uint256 tokenId) internal {
        require (_isApprovedOrOwner(_msgSender(), tokenId), "msg.sender is not token owner");
        _burn(_msgSender(), tokenId);
    }

    function _checkOnERC721MultiReceived(address to, uint256[] memory ids, bytes memory data)
        internal returns (bool)
    {
        if (!to.isContract()) {
            return true;
        }

        bytes4 retval = IERC721MultiReceiver(to).onERC721MultiReceived(_msgSender(), ids, data);
        return (retval == _ERC721_RECEIVED);
    }
}