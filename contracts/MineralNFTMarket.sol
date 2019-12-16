pragma solidity ^0.5.13;

import "./GSN/Context.sol";
import "./token/MineralNFT.sol";
import "./token/Mineral.sol";
import "./token/ERC/SafeERC20.sol";
import "./token/ERC/IERC721Receiver.sol";
import "./token/ERC/IERC20Receiver.sol";
import "./utils/Ownable.sol";
import "./utils/BytesLib.sol";
import "./math/SafeMath.sol";


contract MineralNFTMarket is Context, IERC721Receiver, IERC20Receiver, Ownable {
    using SafeMath for uint256;
    using BytesLib for bytes;
    using SafeERC20 for IERC20;

    enum ItemStatus { enable, sold, canceled }

    struct Item {
        uint256 id;
        uint256 price;
        address owner;
        uint8 status; // 0 : enable, 1 : sold, 2 : cancel
    }

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    event SellItem(address owner, uint256 id, uint256 price);
    event BuyItem(address seller, address buyer, uint256 id, uint256 price);
    event CancelItem(address owner, uint256 id);
    event TakeMineral(address owner, uint256 mineral, uint256[] ids);

    mapping(uint256 => Item) private _items;
    mapping(address => uint256[]) private _soldTokenIds;
    mapping(address => uint256) private _takeableMineral;

    MineralNFT public _nft;
    IERC20 public _mineral;

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

        return _items[id].status == uint8(ItemStatus.enable);
    }

    function getTakeableMineral() external view returns (uint256) {
        return _takeableMineral[_msgSender()];
    }

    function getItemInfo(uint256 tokenId) external view returns (uint256 price, address owner, uint8 status) {
        return (_items[tokenId].price, _items[tokenId].owner, _items[tokenId].status);
    }

    // sell
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
        require (_msgSender() == address(_nft), "msg.sender is not nft token address");
        require (_exists(tokenId) == false, "item with input tokenId is existing");
        uint256 price = data.toUint(0);
        require (0 < price, "input price is not valid");

        _items[tokenId] = Item({
            id: tokenId,
            price: price,
            owner: operator,
            status: uint8(ItemStatus.enable)
        });
        emit SellItem(_items[tokenId].owner, _items[tokenId].id, _items[tokenId].price);
        return _ERC721_RECEIVED;
    }

    // buy
    function onERC20Received(address from, uint256 amount, bytes memory data) public returns (bool) {
        require (_msgSender() == address(_mineral), "msg.sender is not mineral token address");

        uint256 id = data.toUint(0);
        require (_exists(id), "item with input tokenId is existing");

        Item storage item = _items[id];

        require (item.price == amount, "input amount is not valid");
        require (from != item.owner, "input buyer is not valid");
        require (item.status == 0, "item is not available");

        _takeableMineral[item.owner] = _takeableMineral[item.owner].add(amount);
        _soldTokenIds[item.owner].push(id);
        item.status = uint8(ItemStatus.sold);
        _nft.safeTransferFrom(address(this), from, id);

        emit BuyItem(item.owner, from, id, amount);
        return true;
    }

    function cancelItem(uint256 tokenId) external {
        require (_exists(tokenId), "item with input tokenId is existing");

        Item storage item = _items[tokenId];

        require (_msgSender() == item.owner, "msg.sender is not token owner");
        require (item.status != uint8(ItemStatus.canceled), "item is already canceled");

        item.status = uint8(ItemStatus.canceled);
        _nft.safeTransferFrom(address(this), _msgSender(), tokenId);

        emit CancelItem(_msgSender(), tokenId);
    }

    function takeMineral() external {
        require (0 < _takeableMineral[_msgSender()], "There is no sender's mineral to be take");
        _takeMineral(_msgSender());
    }

    function _takeMineral(address addr) internal {
        require(_soldTokenIds[addr].length > 0, "There is no mineral to be take");

        uint256 amount = _takeableMineral[addr];
        uint256[] memory tokenIds = _soldTokenIds[addr];
        _takeableMineral[addr] = 0;
        _soldTokenIds[addr].length = 0;

        _mineral.safeTransfer(addr, amount);
        emit TakeMineral(addr, amount, tokenIds);
    }

    function getSoldTokenIds(address addr) external view returns (uint256[] memory) {
        return _soldTokenIds[addr];
    }

    function setMineralNFTTokenContract(address addr) public onlyOwner {
        _nft = MineralNFT(addr);
    }

    function setMineralTokenContract(address addr) public onlyOwner {
        _mineral = IERC20(addr);
    }

    // reset contract
    function getTakeableMineral(address addr) external view onlyOwner returns (uint256) {
        return _takeableMineral[addr];
    }

    function takeMineralOwnerable(address addr) external onlyOwner {
        _takeMineral(addr);
    }
}