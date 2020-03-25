pragma solidity ^0.5.11;

import "./Exchange.sol";
import "../utils/Address.sol";

contract Factory is IFactory {
	using Address for address;

	// Global Variables
	uint256 public tokenCount;
	mapping (address => address) internal _tokenToExchange;
	mapping (address => address) internal _exchangeToToken;
	mapping (uint256 => address) internal _idToToken;

	// Events
	event NewExchange(
		address indexed token,
		address indexed exchange
	);

	constructor() public {}

	function createExchange(address token) external returns (address) {
		require(token != address(0), "Token address cannot be zero.");
		require(_tokenToExchange[token] == address(0), "Exchange for token already created.");
		require(token.isContract(), "token is not contract");
		Exchange exchange = new Exchange(token);
		_tokenToExchange[token] = address(exchange);
		_exchangeToToken[address(exchange)] = token;

		uint256 tokenId = tokenCount + 1;
		tokenCount = tokenId;
		_idToToken[tokenId] = token;

		emit NewExchange(token, address(exchange));
		return address(exchange);
	}

	function getExchange(address token) external view returns (address) {
		return _tokenToExchange[token];
	}

	function getToken(address exchange) external view returns (address) {
		return _exchangeToToken[exchange];
	}

	function getTokenWithId(uint256 tokenId) external view returns (address) {
		return _idToToken[tokenId];
	}
}