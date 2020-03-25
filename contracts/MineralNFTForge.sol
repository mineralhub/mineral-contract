pragma solidity ^0.5.11;

import "./GSN/Context.sol";
import "./token/MineralNFT.sol";
import "./token/ERC/IERC721MultiReceiver.sol";
import "./utils/Ownable.sol";
import "./utils/BytesLib.sol";
import "./math/SafeMath.sol";

contract MineralNFTForge is Context, IERC721MultiReceiver, Ownable {
    using SafeMath for uint256;
    using BytesLib for bytes;

    enum ForgeType { none, craft, dismantle, reinforce, enchant }
    enum ForgeResult { destroyed, succeeded, great, failed }

    struct ForgeInfo {
        ForgeType forgeType;
        uint256[] ids;
    }

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    event Craft(address itemOwner, uint256[] ids, uint256 requestCode);
    event Dismantle(address itemOwner, uint256[] ids);
    event Reinforce(address itemOwner, uint256[] ids);
    event Enchant(address itemOwner, uint256[] ids);

    mapping(address => ForgeInfo) private _forgeUsers;
    mapping(uint256 => bytes) private _addOptions;

    MineralNFT public _nft;

    constructor(
        address nft
    )
        public
    {
        setMineralNFTTokenContract(nft);
    }

    // forge action
    function onERC721MultiReceived(
        address operator,
        uint256[] calldata ids,
        bytes calldata data
    )
        external
        returns (bytes4)
    {
        require (_msgSender() == address(_nft), "msg.sender is not nft token address");
        require (_forgeUsers[operator].forgeType == ForgeType.none, "There should be no work in progress.");
        require (_forgeUsers[operator].ids.length == 0, "There is already an ongoing forge process");

        ForgeType forgeType = ForgeType(data.toUint8(0));

        _forgeUsers[operator].forgeType = forgeType;
        for(uint i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            _forgeUsers[operator].ids.push(tokenId);
        }

        if(forgeType == ForgeType.craft) {
            uint256 requestCode = data.toUint(1);
            emit Craft(operator, ids, requestCode);
        } else if(forgeType == ForgeType.dismantle) {
            emit Dismantle(operator, ids);
        } else if(forgeType == ForgeType.reinforce) {
            emit Reinforce(operator, ids);
        } else if(forgeType == ForgeType.enchant) {
            emit Enchant(operator, ids);
        } else {
            require(false, "need define forge type");
        }
        return _ERC721_RECEIVED;
    }

    // forge 
    function initForge()
        external
    {
        require (_forgeUsers[_msgSender()].forgeType != ForgeType.none, "There should be work in progress.");
        uint256[] memory tokenIds = _forgeUsers[_msgSender()].ids;
        require (tokenIds.length > 0, "ids is empty");

        _initUserForge(_msgSender());
        _nft.safeMultiTransfer(_msgSender(), tokenIds, '');
    }

    function isRemainItems(
        address operator
    )
        external
        view
        returns (bool)
    {
        return _forgeUsers[operator].ids.length == 0 ? false : true;
    }

    function getOptionString(
        uint256 id
    )
        external
        view
        returns (bytes memory)
    {
        return _addOptions[id];
    }

    function _getArraySum(
        uint256[] memory arr
    )
        internal
        pure
        returns (uint256)
    {
        uint256 sum = 0;
        for(uint256 i = 0 ; i < arr.length ; i++) {
            sum = sum.add(arr[i]);
        }
        return sum;
    }

    function craftForge(
        address operator,
        bytes32 random,
        uint256[] calldata rate,
        string calldata jsonUrl
    )
        external onlyOwner
        returns (uint8, uint256)
    {
        require (_forgeUsers[operator].forgeType == ForgeType.craft, "There should be craft in progress.");
        require (rate.length == uint8(ForgeResult.failed) + 1, "need chance rate");

        uint256 pick = uint256(random) % _getArraySum(rate);
        uint256 createId = 0;
        uint256 accRate = 0;
        uint8 result = 0;
        for (result = 0 ; result < rate.length ; result++) {
            accRate += rate[result];
            if (pick < accRate) {
                if(result == uint8(ForgeResult.great)) {
                    createId = _nft.createItem(operator, jsonUrl);
                }
                break;
            }
        }
        _initUserForge(operator);
        return (result, createId);
    }

    function dismantleForge(
        address operator
    )
        external onlyOwner
    {
        require (_forgeUsers[operator].forgeType == ForgeType.dismantle, "There should be dismantle in progress.");
        _initUserForge(operator);
    }

    function reinforceForge(
        address operator,
        uint256 id,
        bytes32 random,
        uint256[] calldata rate
    )
        external onlyOwner
        returns (uint8)
    {
        require (_forgeUsers[operator].forgeType == ForgeType.reinforce, "There should be reinforce in progress.");
        require (rate.length == uint8(ForgeResult.failed) + 1, "need chance rate");

        uint256 pick = uint256(random) % _getArraySum(rate);
        uint256 accRate = 0;
        uint8 result = 0;
        for (result = 0 ; result < rate.length ; result++) {
            accRate += rate[result];
            if (pick < accRate) {
                if(id != 0 && (result == uint8(ForgeResult.succeeded) || result == uint8(ForgeResult.failed))) {
                    _nft.safeTransferFrom(address(this), operator, id);
                }
                break;
            }
        }
        _initUserForge(operator);
        return result;
    }

    function enchantForge(
        address operator,
        uint256 id,
        bytes calldata options
    )
        external onlyOwner
        returns (uint8)
    {
        require (_forgeUsers[operator].forgeType == ForgeType.enchant, "There should be enchant in progress.");
        _addOptions[id] = options;
        _nft.safeTransferFrom(address(this), operator, id);

        _initUserForge(operator);
        return uint8(ForgeResult.succeeded);
    }

    function _initUserForge(
        address itemOwner
    )
        internal
    {
        _forgeUsers[itemOwner].ids.length = 0;
        _forgeUsers[itemOwner].forgeType = ForgeType.none;
    }

    function setMineralNFTTokenContract(
        address addr
    )
        public onlyOwner
    {
        _nft = MineralNFT(addr);
    }
}