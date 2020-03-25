pragma solidity ^0.5.11;

/**
 * @title ERC721 multi token receiver interface
 * @dev Interface for any contract that wants to support safeMultiTransfers
 * from ERC721 asset contracts.
 */
contract IERC721MultiReceiver {
    /**
     * @notice Handle the receipt of NFT list
     * @param operator The address which called `safeTransferFrom` function
     * @param ids NFT list identifier which is being transferred
     * @param data Additional data with no specified format
     * @return bytes4 `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
     */
    function onERC721MultiReceived(address operator, uint256[] calldata ids, bytes calldata data)
    external returns (bytes4);
}
