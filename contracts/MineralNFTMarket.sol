pragma solidity ^0.5.11;

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
        uint256 index;
        uint8 status; // 0 : enable, 1 : sold, 2 : cancel
    }

    struct TakeableOwner {
        uint256 takeableToken;
        uint256[] soldItemIds;
        uint256 index;
    }

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    event NFTChanged(address contractAddress);
    event MineralChanged(address contractAddress);

    event SellItem(address owner, uint256 id, uint256 price);
    event BuyItem(address seller, address buyer, uint256 id, uint256 price);
    event CancelItem(address owner, uint256 id);
    event TakeMineral(address owner, uint256 mineral, uint256[] ids);

    uint256 public _feeNumerator = 5;
    uint256 public _feeDenominator = 100;
    uint256 public _minimumPrice = 1000000;

    mapping(uint256 => Item) private _items;
    mapping(address => TakeableOwner) private _takeableOwners;
    uint256 private _takeableFee;

    uint256[] private _itemIdKeys;
    address[] private _takeableOwnerKeys;

    MineralNFT public _nft;
    IERC20 public _token;

    constructor(address nft, address token) public {
        setNFTContract(nft);
        setERC20TokenContract(token);
    }

    function exists(uint256 id) external view returns (bool) {
        return _exists(id);
    }

    function _exists(uint256 id) internal view returns (bool) {
        if (_items[id].price == 0)
            return false;

        return _items[id].status == uint8(ItemStatus.enable);
    }

    function _removeItemId(uint256 index) internal {
        require (index < _itemIdKeys.length, "out of length");

        uint256 lastIndex = _itemIdKeys.length.sub(1);
        if (lastIndex != index) {
            uint256 lastId = _itemIdKeys[lastIndex];
            _itemIdKeys[index] = lastId;
            _items[lastId].index = index;
        }
        _itemIdKeys.length--;
    }

    function _removeTakeableOwner(uint256 index) internal {
        require (index < _takeableOwnerKeys.length, "out of length");

        uint256 lastIndex = _takeableOwnerKeys.length.sub(1);
        if (lastIndex != index) {
            address lastOwner = _takeableOwnerKeys[lastIndex];
            _takeableOwnerKeys[index] = lastOwner;
            _takeableOwners[lastOwner].index = index;
        }
        _takeableOwnerKeys.length--;
    }

    function getTakeableMineral() external view returns (uint256) {
        return _takeableOwners[_msgSender()].takeableToken;
    }

    function getItemInfo(uint256 tokenId) external view returns (uint256 price, address owner, uint8 status) {
        return (_items[tokenId].price, _items[tokenId].owner, _items[tokenId].status);
    }

    // sell
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
        require (_msgSender() == address(_nft), "msg.sender is not nft token address");
        require (_exists(tokenId) == false, "item with input tokenId is existing");
        
        uint256 price = data.toUint(0);
        require (_minimumPrice <= price, "required _minimumPrice <= price");
        require (from == operator, "input seller is not valid");

        _items[tokenId] = Item({
            id: tokenId,
            price: price,
            owner: operator,
            status: uint8(ItemStatus.enable),
            index: _itemIdKeys.length
        });
        _itemIdKeys.push(tokenId);

        emit SellItem(_items[tokenId].owner, _items[tokenId].id, _items[tokenId].price);
        return _ERC721_RECEIVED;
    }

    // buy
    function onERC20Received(address from, uint256 amount, bytes calldata data) external returns (bool) {
        require (_msgSender() == address(_token), "msg.sender is not mineral token address");

        uint256 id = data.toUint(0);
        require (_exists(id), "item with input tokenId doesn't existing");

        Item storage item = _items[id];
        require (item.price == amount, "input amount is not valid");
        require (from != item.owner, "input buyer is not valid");

        uint256 fee = amount.div(_feeDenominator).mul(_feeNumerator);
        _takeableFee = _takeableFee.add(fee);
        _takeableOwners[item.owner].takeableToken = _takeableOwners[item.owner].takeableToken.add(amount.sub(fee));
        _takeableOwners[item.owner].soldItemIds.push(item.id);
        if (_takeableOwners[item.owner].soldItemIds.length == 1) {
            _takeableOwners[item.owner].index = _takeableOwnerKeys.length;
            _takeableOwnerKeys.push(item.owner);
        }
        item.status = uint8(ItemStatus.sold);
        _removeItemId(item.index);

        _nft.safeTransferFrom(address(this), from, id);
        emit BuyItem(item.owner, from, id, amount);
        return true;
    }

    function cancelItem(uint256 tokenId) external {
        _cancelItem(_msgSender(), tokenId);
    }

    function _cancelItem(address owner, uint256 tokenId) internal {
        require (_exists(tokenId), "item with input tokenId doesn't existing");

        Item storage item = _items[tokenId];
        require (owner == item.owner, "msg.sender is not token owner");

        item.status = uint8(ItemStatus.canceled);
        _removeItemId(item.index);

        _nft.safeTransferFrom(address(this), owner, tokenId);
        emit CancelItem(owner, tokenId);
    }

    function takeMineral() external {
        _takeMineral(_msgSender());
    }

    function _takeMineral(address owner) internal {
        require (_takeableOwners[owner].takeableToken > 0, "There is no mineral to be take");

        uint256 amount = _takeableOwners[owner].takeableToken;
        uint256[] memory tokenIds = _takeableOwners[owner].soldItemIds;

        _removeTakeableOwner(_takeableOwners[owner].index);
        delete _takeableOwners[owner];

        _token.safeTransfer(owner, amount);
        emit TakeMineral(owner, amount, tokenIds);
    }

    function itemIdKeysLength() external view returns (uint256) {
        return _itemIdKeys.length;
    }

    function getSoldTokenIds(address owner) external view returns (uint256[] memory) {
        return _takeableOwners[owner].soldItemIds;
    }

    // admin functions
    function setNFTContract(address addr) public onlyOwner {
        require (_itemIdKeys.length == 0, "Market has items");

        _nft = MineralNFT(addr);
        emit NFTChanged(addr);
    }

    function setERC20TokenContract(address addr) public onlyOwner {
        require (_takeableOwnerKeys.length == 0, "Makret has takeble token");

        _token = IERC20(addr);
        emit MineralChanged(addr);
    }

    // reset contract
    function cancelItemByAdmin(uint256 tokenId) external onlyOwner {
        _cancelItem(_items[tokenId].owner, tokenId);
    }

    function takeMineralByAdmin(address owner) external onlyOwner {
        _takeMineral(owner);
    }

    // fee from owner for market independently
    function takeMineralFee(address owner, uint256 amount) external onlyOwner {
        require (0 < _takeableFee, "No more fees left");
        require (amount <= _takeableFee, "Request amount greater than saved fee");

        _takeableFee = _takeableFee.sub(amount);
        _token.safeTransfer(owner, amount);
    }

    function setFee(uint256 numerator, uint256 denominator) external onlyOwner {
        _feeNumerator = numerator;
        _feeDenominator = denominator;
    }

    function setMinimumPrice(uint256 price) external onlyOwner {
        require (0 < price, "required 0 < price");
        _minimumPrice = price;
    }
}