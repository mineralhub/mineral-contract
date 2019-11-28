pragma solidity ^0.5.13;

import "./GSN/Context.sol";
import "./token/MineralNFT.sol";
import "./token/Mineral.sol";
import "./token/ERC/IERC721Receiver.sol";
import "./token/ERC/IERC20Receiver.sol";
import "./utils/Ownable.sol";
import "./utils/BytesLib.sol";
import "./math/SafeMath.sol";

/*
    [전체적인 피드백]
    지역변수 owner 와 Ownable.owner (문서에 info 로만 있어서 가급적 지역변수로 owner를 쓰지말라고 권장하는것 같음)
    selled => sold
    require 오류 문구 변경 권장
*/

contract MineralNFTMarket is Context, IERC721Receiver, IERC20Receiver, Ownable {
    using SafeMath for uint256;
    using BytesLib for bytes;

    /*
        가독성을 위해 enum 권장
            ex) uint8(ItemStatus.sold)
    */
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

        return _items[id].status == uint8(ItemStatus.enable);
    }

    function getTakeableMineral() external view returns (uint256) {
        return _takeableMineral[_msgSender()];
    }

    function getItemInfo(uint256 tokenId) external view returns (uint256 price, address owner, uint8 status) {
        return (_items[tokenId].price, _items[tokenId].owner, _items[tokenId].status);
    }

    /*
        [onERC721Received() 에 대한 피드백]
        가스를 절약하기 위해 public 에서 external
            => overriding public function onERC721Received

        from 매개변수 쓰이지 않음, 함수의 기능을 명확하게 하고 싶다.
            => overriding function onERC721Received
        함수에서 전송 관련 로직이 없다.
            => 의도된 로직
    */
    // sell
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) public returns (bytes4) {
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

    /*
        [onERC20Received() 에 대한 피드백]
        Check-Effects-Interaction Pattern 사용 권장(재진입 공격 방어)
        가스를 절약하기 위해 public 에서 external
            => overriding public function onERC20Received

        transferFrom 에 from 변수가 매개변수의 두번째 to 인 이유
            => overriding function onERC20Received
            => onERC20Received 의 매개변수 from은 buy 요청을 한 유저의 address
    */
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
        _nft.transferFrom(address(this), from, id);

        emit BuyItem(item.owner, from, id, amount);
        return true;
    }

    /*
        [cancelItem() 에 대한 피드백]
        Check-Effects-Interaction Pattern 사용 권장(재진입 공격 방어)
    */
    function cancelItem(uint256 tokenId) external {
        require (_exists(tokenId), "item with input tokenId is existing");

        Item storage item = _items[tokenId];

        require (_msgSender() == item.owner, "msg.sender is not token owner");
        require (item.status != uint8(ItemStatus.canceled), "item is already canceled");

        item.status = uint8(ItemStatus.canceled);
        _nft.transferFrom(address(this), _msgSender(), tokenId);

        emit CancelItem(_msgSender(), tokenId);
    }

    function takeMineral() external {
        require (0 < _takeableMineral[_msgSender()], "There is no sender's mineral to be take");
        _takeMineral(_msgSender());
    }

    /*
        [_takeMineral() 에 대한 피드백]
        Check-Effects-Interaction Pattern 사용 권장(재진입 공격 방어)
    */
    function _takeMineral(address addr) internal {
        require(_soldTokenIds[addr].length > 0, "There is no mineral to be take");

        uint256 amount = _takeableMineral[addr];
        uint256[] memory tokenIds = _soldTokenIds[addr];
        _takeableMineral[addr] = 0;
        _soldTokenIds[addr].length = 0;

        _mineral.transfer(addr, amount);
        emit TakeMineral(addr, amount, tokenIds);
    }

    /*
        함수명 변경
        getSelledTokenIds -> getSoldTokenIds
    */
    function getSoldTokenIds(address addr) external view returns (uint256[] memory) {
        return _soldTokenIds[addr];
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

    /*
        [takeMineralOnwerable() 에 대한 피드백]
        함수 오타
            (수정) takeMineralOwnerable()
    */
    function takeMineralOwnerable(address addr) external onlyOwner {
        _takeMineral(addr);
    }
}