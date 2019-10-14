pragma solidity ^0.5.4;

import "./token/MineralNFT.sol";
import "./token/Mineral.sol";
import "./token/ERC/IERC721Receiver.sol";
import "./token/ERC/IERC20Receiver.sol";
import "./utils/Ownable.sol";
import "./utils/BytesLib.sol";
import "./math/SafeMath.sol";

contract MineralNFTMarket is IERC721Receiver, IERC20Receiver, Ownable {
    using SafeMath for uint256;
    using BytesLib for bytes;

    struct Item {
        uint256 id;
        uint256 price;
        address owner;
        uint8 status; // 0 : enable, 1 : selled, 2 : cancel
    }

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    event SellItem(address owner, uint256 id, uint256 price);
    event BuyItem(address seller, address buyer, uint256 id, uint256 price);
    event CancelItem(address owner, uint256 id);
    event TakeMineral(address owner, uint256 mineral, uint256[] ids);

    mapping(uint256 => Item) private _items;
    mapping(address => uint256[]) private _selledTokenIds;
    mapping(address => uint256) private _takeableMineral;

    MineralNFT public _nft;
    Mineral public _mineral;

    constructor(address nft, address mineral) public {
        setMineralNFTTokenContract(nft);
        setMineralTokenContract(mineral);
    }

    function exists(uint id) external view returns (bool) {
        return _exists(id);
    }

    function _exists(uint id) internal view returns (bool) {
        if (_items[id].price == 0)
            return false;

        return _items[id].status == 0;
    }

    function getTakeableMineral() external view returns (uint256) {
        return _takeableMineral[msg.sender];
    }

    function getItemInfo(uint256 tokenId) external view returns (uint256 price, address owner, uint8 status) {
        return (_items[tokenId].price, _items[tokenId].owner, _items[tokenId].status);
    }

    // sell
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) public returns (bytes4) {
        require (msg.sender == address(_nft), "require same token address");
        require (_exists(tokenId) == false, "exists item");
        uint256 price = data.toUint(0);
        require (0 < price, "require 0 < price");

        _items[tokenId] = Item({
            id: tokenId,
            price: price,
            owner: operator,
            status: 0
        });
        emit SellItem(_items[tokenId].owner, _items[tokenId].id, _items[tokenId].price);
        return _ERC721_RECEIVED;
    }

    // buy
    function onERC20Received(address from, uint256 amount, bytes memory data) public returns (bool) {
        require (msg.sender == address(_mineral), "require same token address");

        uint256 id = data.toUint(0);
        require (_exists(id), "not exists tokenId");

        Item storage item = _items[id];

        require (item.price == amount, "price != amount");
        require (from != item.owner, "from == owner");

        _nft.transferFrom(address(this), from, id);
        _takeableMineral[item.owner] = _takeableMineral[item.owner].add(amount);
        _selledTokenIds[item.owner].push(id);
        item.status = 1;

        emit BuyItem(item.owner, from, id, amount);
        return true;
    }

    function cancelItem(uint256 tokenId) external {
        require (_exists(tokenId), "not exists tokenId");

        Item storage item = _items[tokenId];
        require (msg.sender == item.owner, "not owner");

        _nft.transferFrom(address(this), msg.sender, tokenId);
        item.status = 2;

        emit CancelItem(msg.sender, tokenId);
    }

    function takeMineral() external {
        require (0 < _takeableMineral[msg.sender], "nothing");
        _takeMineral(msg.sender);
    }

    function _takeMineral(address addr) internal {
        _mineral.transfer(addr, _takeableMineral[addr]);
        emit TakeMineral(addr, _takeableMineral[addr], _selledTokenIds[addr]);
        _takeableMineral[addr] = 0;
        _selledTokenIds[addr].length = 0;
    }

    function getSelledTokenIds(address addr) external view returns (uint256[] memory) {
        return _selledTokenIds[addr];
    }

    function setMineralNFTTokenContract(address addr) public onlyOwner {
        _nft = MineralNFT(addr);
    }

    function setMineralTokenContract(address addr) public onlyOwner {
        _mineral = Mineral(addr);
    }

    // reset contract
    function getTakeableMineral(address addr) external view onlyOwner returns (uint256) {
        return _takeableMineral[addr];
    }

    function takeMineralOnwerable(address addr) external onlyOwner {
        _takeMineral(addr);
    }
}