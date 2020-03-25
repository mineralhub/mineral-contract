pragma solidity ^0.5.11;

import "../math/SafeMath.sol";
import "../token/ERC/IERC20.sol";
import "../utils/ReentrancyGuard.sol";

interface IFactory {
	function getExchange(address tokenAddr) external view returns (address);
}

interface IExchange {
	function getEthToTokenOutputPrice(uint256 tokensBought) external view returns (uint256);
	function ethToTokenTransferInput(uint256 minTokens, uint256 deadline, address recipient) external payable returns (uint256);
	function ethToTokenTransferOutput(uint256 tokensBought, uint256 deadline, address recipient) external payable returns (uint256);
}

contract Exchange is IExchange, ReentrancyGuard {
	using SafeMath for uint256;
	// Global Varaibles
	string public name;  // Uniswap V1
	string public symbol;  // UNI-V1
	uint8 public decimals;  // 18
	uint256 public totalSupply;  // total number of NUI in existence
	mapping(address => uint256) internal _balances;  // UNI balance of an address
	mapping(address => mapping(address => uint256)) internal _allowances;  // UNI allowance of on address on another
	address internal _token;  // address of the ERC20 token traded on this contract
	address internal _factory;  // interface for the factory that created this contract

	// Constants
	uint256 public constant FEE_NUMERATOR = 997;
	uint256 public constant FEE_DENOMINATOR = 1000;
	uint256 public constant MIN_ETH_REQUIRE = 1000000000;

	// Events
	event TokenPurchase(
		address indexed buyer,
		uint256 indexed ethSold,
		uint256 indexed tokensBought
	);
	event EthPurchase(
		address indexed buyer,
		uint256 indexed tokensSold,
		uint256 indexed ethBought
	);
	event AddLiquidity(
		address indexed provider,
		uint256 indexed ethAmount,
		uint256 indexed tokenAmount
	);
	event RemoveLiquidity(
		address indexed provider,
		uint256 indexed ethAmount,
		uint256 indexed tokenAmount
	);
	event Transfer(
		address indexed from,
		address indexed to,
		uint256 value
	);
	event Approval(
		address indexed owner,
		address indexed spender,
		uint256 value
	);

	modifier ensureDeadlineHasntPassed(uint256 deadline) {
		require(deadline >= now, "Deadline has passed.");
		_;
	}

	constructor(address tokenAddr) public {
		require(_factory == address(0), "Factory already set.");
		require(_token == address(0), "Token already set.");
		require(tokenAddr != address(0), "Token address cannot be zero.");
		_factory = address(msg.sender);
		_token = tokenAddr;
		name = "Uniswap V1";
		symbol = "UNI-V1";
		decimals = 18;
	}

	// @notice Deposit ETH and Tokens (self.token) at current ratio to mint UNI tokens.
	// @dev minLiquidity does nothing when total UNI supply is 0.
	// @param minLiquidity Minimum number of UNI sender will mint if total UNI supply is greater than 0.
	// @param maxTokens Maximum number of tokens deposited. Deposits max amount if total UNI supply is 0.
	// @param deadline after which this transaction can no longer be executed.
	// @return The amount of UNI minted.
	function addLiquidity(uint256 minLiquidity, uint256 maxTokens, uint256 deadline) ensureDeadlineHasntPassed(deadline) public payable returns (uint256) {
		require(maxTokens > 0, "Max tokens cannot be zero.");
		require(msg.value > 0, "No ether received.");
		uint256 totalLiquidity = totalSupply;
		if (totalLiquidity > 0) {
			require(minLiquidity > 0, "Min liquidity cannot be zero.");

			uint256 ethReserve = address(this).balance.sub(msg.value);
			uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
			uint256 tokenAmount = msg.value.mul(tokenReserve).div(ethReserve).add(1);
			uint256 liquidityMinted = msg.value.mul(totalLiquidity).div(ethReserve);
			require(maxTokens >= tokenAmount, "maximum token must be larger or equal than token amount.");
			require(liquidityMinted >= minLiquidity, "liquidity minted must be larger or equal than minimum liquidity.");

			_balances[msg.sender] = _balances[msg.sender].add(liquidityMinted);
			totalSupply = totalLiquidity.add(liquidityMinted);
			require(IERC20(_token).transferFrom(msg.sender, address(this), tokenAmount), "ETH transfer from msg.sender to self failed.");

			emit AddLiquidity(msg.sender, msg.value, tokenAmount);
			emit Transfer(address(0), msg.sender, liquidityMinted);
			return liquidityMinted;
		} else {
			//require(_factory != address(0), "Factory address must be set first.");
			//require(_token != address(0), "Token address cannot be zero.");
			require(msg.value >= MIN_ETH_REQUIRE, "Insufficient Eth sent.");
			require(IFactory(_factory).getExchange(_token) == address(this), "Token does not match with the factory.");

			uint256 tokenAmount = maxTokens;
			uint256 initialLiquidity = address(this).balance;
			totalSupply = initialLiquidity;
			_balances[msg.sender] = initialLiquidity;
			require(IERC20(_token).transferFrom(msg.sender, address(this), tokenAmount), "ETH transfer from msg.sender to self failed.");

			emit AddLiquidity(msg.sender, msg.value, tokenAmount);
			emit Transfer(address(0), msg.sender, initialLiquidity);
			return initialLiquidity;
		}
	}

	// @dev Burn UNI tokens to withdraw ETH and Tokens at current ratio.
	// @param amount Amount of UNI burned.
	// @param minETH Minimum ETH withdrawn.
	// @param minTokens Minimum Tokens withdrawn.
	// @param deadline after which this transaction can no longer be executed.
	// @return The amount of ETH and Tokens withdrawn.
	function removeLiquidity(uint256 amount, uint256 minETH, uint256 minTokens, uint256 deadline) ensureDeadlineHasntPassed(deadline) public returns (uint256, uint256) {
		require(amount > 0, "Amount must be larger than zero.");
		require(minETH > 0, "Minimum ETH must be larger than zero.");
		require(minTokens > 0, "Minimum token must be larger than zero.");

		uint256 totalLiquidity = totalSupply;
		require(totalLiquidity > 0, "No liquidity currently.");

		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 ethAmount = amount.mul(address(this).balance).div(totalLiquidity);
		uint256 tokenAmount = amount.mul(tokenReserve).div(totalLiquidity);
		require(ethAmount >= minETH && tokenAmount >= minTokens, "Insufficient token amount.");

		_balances[msg.sender] = _balances[msg.sender].sub(amount);
		totalSupply = totalLiquidity.sub(amount);
		address(msg.sender).transfer(ethAmount);
		bool success = IERC20(_token).transfer(msg.sender, tokenAmount);
		require(success, "Token transfer failed.");

		emit RemoveLiquidity(msg.sender, ethAmount, tokenAmount);
		emit Transfer(msg.sender, address(0), amount);
		return (ethAmount, tokenAmount);
	}

	// @dev Pricing function for converting between ETH and Tokens.
	// @param inputAmount Amount of ETH or Tokens being sold.
	// @param inputReserve Amount of ETH or Tokens (input type) in exchange reserves.
	// @param outputReserve Amount of ETH or Tokens (output type) in exchange reserves.
	// @return Amount of ETH or Tokens bought.
	function _getInputPrice(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) internal pure returns (uint256) {
		require(inputReserve > 0, "Input reserve must be larger than zero");
		require(outputReserve > 0, "Output reserve must be larger than zero");

		uint256 inputAmountWithFee = inputAmount.mul(FEE_NUMERATOR);
		uint256 numerator = inputAmountWithFee.mul(outputReserve);
		uint256 denominator = inputReserve.mul(FEE_DENOMINATOR).add(inputAmountWithFee);
		return numerator.div(denominator);
	}

	// @dev Pricing function for converting between ETH and Tokens.
	// @param outputAmount Amount of ETH or Tokens being bought.
	// @param inputReserve Amount of ETH or Tokens (input type) in exchange reserves.
	// @param outputReserve Amount of ETH or Tokens (output type) in exchange reserves.
	// @return Amount of ETH or Tokens sold.
	function _getOutputPrice(uint256 outputAmount, uint256 inputReserve, uint256 outputReserve) internal pure returns (uint256) {
		require(inputReserve > 0, "Input reserve must be larger than zero");
		require(outputReserve > 0, "Output reserve must be larger than zero");

		uint256 numerator = inputReserve.mul(outputAmount).mul(FEE_DENOMINATOR);
		uint256 denominator = outputReserve.sub(outputAmount).mul(FEE_NUMERATOR);
		return numerator.div(denominator).add(1);
	}

	function _ethToTokenInput(uint256 ethSold, uint256 minTokens, uint256 deadline, address buyer, address recipient) ensureDeadlineHasntPassed(deadline) internal returns (uint256) {
		require(ethSold > 0, "ETH sold must be larger than zero.");
		require(minTokens > 0, "Minimum token must be larger than zero.");

		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 tokensBought = _getInputPrice(ethSold, address(this).balance.sub(ethSold), tokenReserve);

		require(tokensBought >= minTokens, "Tokens bought should be larger than minimum token.");
		require(IERC20(_token).transfer(recipient, tokensBought), "Token transfer failed.");

		emit TokenPurchase(buyer, ethSold, tokensBought);

		return tokensBought;
	}

	// @notice Convert ETH to Tokens.
	// @dev User specifies exact input (msg.value) and minimum output.
	// @param minTokens Minimum Tokens bought.
	// @param deadline Time after which this transaction can no longer be executed.
	// @return Amount of Tokens bought.
	function ethToTokenSwapInput(uint256 minTokens, uint256 deadline) external payable returns (uint256) {
		return _ethToTokenInput(msg.value, minTokens, deadline, msg.sender, msg.sender);
	}

	function ethToTokenTransferInput(uint256 minTokens, uint256 deadline, address recipient) external payable returns (uint256 ) {
		require(recipient != address(this), "Current exchange cannot be the recipient.");
		require(recipient != address(0), "Recipient cannot be zero address");
		return _ethToTokenInput(msg.value, minTokens, deadline, msg.sender, recipient);
	}

	function _ethToTokenOutput(uint256 tokensBought, uint256 maxETH, uint256 deadline, address payable buyer, address recipient) ensureDeadlineHasntPassed(deadline) internal returns (uint256) {
		require(tokensBought > 0, "Tokens bought must be larger than zero.");
		require(maxETH > 0, "Maximum ETH must be larger than zero.");

		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 ethSold = _getOutputPrice(tokensBought, address(this).balance.sub(maxETH), tokenReserve);

		uint256 eth_refund = maxETH.sub(ethSold);
		if (eth_refund > 0) {
			buyer.transfer(eth_refund);
		}

		require(IERC20(_token).transfer(recipient, tokensBought), "Token transfer failed.");
		emit TokenPurchase(buyer, ethSold, tokensBought);
		return ethSold;
	}

	// @notice Convert ETH to Tokens.
	// @dev User specifies maximum input (msg.value) and exact output.
	// @param tokensBought Amount of tokens bought.
	// @param deadline Time after which this transaction can no longer be executed.
	// @return Amount of ETH sold.
	function ethToTokenSwapOutput(uint256 tokensBought, uint256 deadline) external payable returns (uint256) {
		return _ethToTokenOutput(tokensBought, msg.value, deadline, msg.sender, msg.sender);
	}

	// @notice Convert ETH to Tokens and transfers Tokens to recipient.
	// @dev User specifies maximum input (msg.value) and exact output.
	// @param tokensBought Amount of tokens bought.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param recipient The address that receives output Tokens.
	// @return Amount of ETH sold.
	function ethToTokenTransferOutput(uint256 tokensBought, uint256 deadline, address recipient) external payable returns (uint256) {
		require(recipient != address(this), "Current exchange cannot be the recipient.");
		require(recipient != address(0), "Recipient cannot be zero address.");
		return _ethToTokenOutput(tokensBought, msg.value, deadline, msg.sender, recipient);
	}

	function _tokenToEthInput(uint256 tokensSold, uint256 minETH, uint256 deadline, address buyer, address payable recipient) ensureDeadlineHasntPassed(deadline) internal returns (uint256) {
		require(tokensSold > 0, "Tokens sold must be larger than zero.");
		require(minETH > 0, "Minimum ETH must be larger than zero.");

		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 ethBought = _getInputPrice(tokensSold, tokenReserve, address(this).balance);
		require(ethBought >= minETH, "Minimum ETH must be must be smaller than ETH bought.");

		recipient.transfer(ethBought);
		require(IERC20(_token).transferFrom(buyer, address(this), tokensSold), "Transfer failed.");

		emit EthPurchase(buyer, tokensSold, ethBought);
		return ethBought;
	}

	// @notice Convert Tokens to ETH.
	// @dev User specifies exact input and minimum output.
	// @param tokensSold Amount of Tokens sold.
	// @param minETH Minimum ETH purchased.
	// @param deadline Time after which this transaction can no longer be executed.
	// @return Amount of ETH bought.
	function tokenToEthSwapInput(uint256 tokensSold, uint256 minETH, uint256 deadline) external returns (uint256) {
		return _tokenToEthInput(tokensSold, minETH, deadline, msg.sender, msg.sender);
	}

	// @notice Convert Tokens to ETH and transfers ETH to recipient.
	// @dev User specifies exact input and minimum output.
	// @param tokensSold Amount of Tokens sold.
	// @param minETH Minimum ETH purchased.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param recipient The address that receives output ETH.
	// @return Amount of ETH bought.
	function tokenToEthTransferInput(uint256 tokensSold, uint256 minETH, uint256 deadline, address payable recipient) external returns (uint256) {
		require(recipient != address(this), "Current exchange cannot be the recipient.");
		require(recipient != address(0), "Recipient cannot be zero address.");
		return _tokenToEthInput(tokensSold, minETH, deadline, msg.sender, recipient);
	}

	function _tokenToEthOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline, address buyer, address payable recipient) ensureDeadlineHasntPassed(deadline) internal returns (uint256) {
		require(ethBought > 0, "ETH bought must be larger than zero.");

		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 tokensSold = _getOutputPrice(ethBought, tokenReserve, address(this).balance);

		require(maxTokens >= tokensSold, "Tokens sold must always > 0.");
		recipient.transfer(ethBought);
		require(IERC20(_token).transferFrom(buyer, address(this), tokensSold), "Transfer failed.");

		emit EthPurchase(buyer, tokensSold, ethBought);
        return tokensSold;
	}


	// @notice Convert Tokens to ETH.
	// @dev User specifies exact input and minimum output.
	// @param tokensSold Amount of Tokens sold.
	// @param minETH Minimum ETH purchased.
	// @param deadline Time after which this transaction can no longer be executed.
	// @return Amount of ETH bought.

	// @notice Convert Tokens to ETH.
	// @dev User specifies maximum input and exact output.
	// @param ethBought Amount of ETH purchased.
	// @param maxTokens Maximum Tokens sold.
	// @param deadline Time after which this transaction can no longer be executed.
	// @return Amount of Tokens sold.
	function tokenToEthSwapOutput(uint256 ethBought,  uint256 maxTokens, uint256 deadline) external returns (uint256) {
		return _tokenToEthOutput(ethBought, maxTokens, deadline, msg.sender, msg.sender);
	}

	// @notice Convert Tokens to ETH and transfers ETH to recipient.
	// @dev User specifies maximum input and exact output.
	// @param ethBought Amount of ETH purchased.
	// @param maxTokens Maximum Tokens sold.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param recipient The address that receives output ETH.
	// @return Amount of Tokens sold.
	function tokenToEthTransferOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline, address payable recipient) external returns (uint256) {
		require(recipient != address(this), "Recipient cannot be self.");
		require(recipient != address(0), "Recipient cannot be zero address.");
		return _tokenToEthOutput(ethBought, maxTokens, deadline, msg.sender, recipient);
	}

	function _tokenToTokenInput(uint256 tokensSold, uint256 minTokensBought, uint256 minETHbought, uint256 deadline, address buyer, address recipient, address exchangeAddr) ensureDeadlineHasntPassed(deadline) internal nonReentrant returns (uint256) {
		require(tokensSold > 0, "Tokens sold must be larger than zero.");
		require(minTokensBought > 0, "Minimum tokens bought must be larger than zero.");
		require(minETHbought > 0, "Minimum ETH bought must be larger than zero.");
		require(exchangeAddr != address(this), "Exchange address must not be self.");
		require(exchangeAddr != address(0), "Exchange address must not be zero address.");

		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 ethBought = _getInputPrice(tokensSold, tokenReserve, address(this).balance);
		require(ethBought >= minETHbought, "Minium ETH bought must be smaller than ETH bough.");
		require(IERC20(_token).transferFrom(buyer, address(this), tokensSold), "Transfer failed.");
		uint256 tokensBought = IExchange(exchangeAddr).ethToTokenTransferInput.value(ethBought)(minTokensBought, deadline, recipient);

		emit EthPurchase(buyer, tokensSold, ethBought);
    	return tokensBought;
	}

	// @notice Convert Tokens (self.token) to Tokens (tokenAddr).
	// @dev User specifies exact input and minimum output.
	// @param tokensSold Amount of Tokens sold.
	// @param minTokensBought Minimum Tokens (tokenAddr) purchased.
	// @param minETHbought Minimum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param tokenAddr The address of the token being purchased.
	// @return Amount of Tokens (tokenAddr) bought.
	function tokenToTokenSwapInput(uint256 tokensSold, uint256 minTokensBought, uint256 minETHbought, uint256 deadline, address tokenAddr) external returns (uint256) {
		address exchangeAddr = IFactory(_factory).getExchange(tokenAddr);
		return _tokenToTokenInput(tokensSold, minTokensBought, minETHbought, deadline, msg.sender, msg.sender, exchangeAddr);
	}

	// @notice Convert Tokens (self.token) to Tokens (tokenAddr) and transfers Tokens (tokenAddr) to recipient.
	// @dev User specifies exact input and minimum output.
	// @param tokensSold Amount of Tokens sold.
	// @param minTokensBought Minimum Tokens (tokenAddr) purchased.
	// @param minETHbought Minimum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param recipient The address that receives output ETH.
	// @param tokenAddr The address of the token being purchased.
	// @return Amount of Tokens (tokenAddr) bought.
	function tokenToTokenTransferInput(uint256 tokensSold, uint256 minTokensBought, uint256 minETHbought, uint256 deadline, address recipient, address tokenAddr) external returns (uint256) {
    	address exchangeAddr = IFactory(_factory).getExchange(tokenAddr);
    	return _tokenToTokenInput(tokensSold, minTokensBought, minETHbought, deadline, msg.sender, recipient, exchangeAddr);
	}

	function _tokenToTokenOutput(uint256 tokensBought, uint256 maxtokensSold, uint256 maxETHsold, uint256 deadline, address buyer, address recipient, address exchangeAddr) ensureDeadlineHasntPassed(deadline) internal returns (uint256) {
		require(tokensBought > 0, "Tokens bought must be larger than zero.");
		require(maxETHsold > 0, "Maximum ETH sold must be larger than zero.");
		require(exchangeAddr != address(this), "Exchange address must not be self.");
		require(exchangeAddr != address(0), "Exchange address must not be zero address.");

		uint256 ethBought = IExchange(exchangeAddr).getEthToTokenOutputPrice(tokensBought);

		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 tokensSold = _getOutputPrice(ethBought, tokenReserve, address(this).balance);

		require(maxtokensSold >= tokensSold, "Maximum tokens sold must be larger than tokens sold.");
		require(maxETHsold >= ethBought, "Maximum ETH sold must be larger than ETH bought.");
		require(IERC20(_token).transferFrom(buyer, address(this), tokensSold), "Transfer failed.");

		require(IExchange(exchangeAddr).ethToTokenTransferOutput.value(ethBought)(tokensBought, deadline, recipient) > 0, "ETH sold should be larger than zero.");
		emit EthPurchase(buyer, tokensSold, ethBought);
		return tokensSold;
	}

	// @notice Convert Tokens (self.token) to Tokens (tokenAddr).
	// @dev User specifies maximum input and exact output.
	// @param tokensBought Amount of Tokens (tokenAddr) bought.
	// @param maxtokensSold Maximum Tokens (self.token) sold.
	// @param maxETHsold Maximum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param tokenAddr The address of the token being purchased.
	// @return Amount of Tokens (self.token) sold.
	function tokenToTokenSwapOutput(uint256 tokensBought, uint256 maxtokensSold, uint256 maxETHsold, uint256 deadline, address tokenAddr) external returns (uint256) {
		address exchangeAddr = IFactory(_factory).getExchange(tokenAddr);
		return _tokenToTokenOutput(tokensBought, maxtokensSold, maxETHsold, deadline, msg.sender, msg.sender, exchangeAddr);
	}

	// @notice Convert Tokens (self.token) to Tokens (tokenAddr) and transfers Tokens (tokenAddr) to recipient.
	// @dev User specifies maximum input and exact output.
	// @param tokensBought Amount of Tokens (tokenAddr) bought.
	// @param maxtokensSold Maximum Tokens (self.token) sold.
	// @param maxETHsold Maximum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param recipient The address that receives output ETH.
	// @param tokenAddr The address of the token being purchased.
	// @return Amount of Tokens (self.token) sold.
	function tokenToTokenTransferOutput(uint256 tokensBought, uint256 maxtokensSold, uint256 maxETHsold, uint256 deadline, address recipient, address tokenAddr) public returns (uint256) {
		address exchangeAddr = IFactory(_factory).getExchange(tokenAddr);
		return _tokenToTokenOutput(tokensBought, maxtokensSold, maxETHsold, deadline, msg.sender, recipient, exchangeAddr);
	}


	// @notice Convert Tokens (self.token) to Tokens (exchangeAddr.token).
	// @dev Allows trades through contracts that were not deployed from the same factory.
	// @dev User specifies exact input and minimum output.
	// @param tokensSold Amount of Tokens sold.
	// @param minTokensBought Minimum Tokens (tokenAddr) purchased.
	// @param minETHbought Minimum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param exchangeAddr The address of the exchange for the token being purchased.
	// @return Amount of Tokens (exchangeAddr.token) bought.
	function tokenToExchangeSwapInput(uint256 tokensSold, uint256 minTokensBought, uint256 minETHbought, uint256 deadline, address exchangeAddr) external returns (uint256) {
    	return _tokenToTokenInput(tokensSold, minTokensBought, minETHbought, deadline, msg.sender, msg.sender, exchangeAddr);
	}

	// @notice Convert Tokens (self.token) to Tokens (exchangeAddr.token) and transfers Tokens (exchangeAddr.token) to recipient.
	// @dev Allows trades through contracts that were not deployed from the same factory.
	// @dev User specifies exact input and minimum output.
	// @param tokensSold Amount of Tokens sold.
	// @param minTokensBought Minimum Tokens (tokenAddr) purchased.
	// @param minETHbought Minimum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param recipient The address that receives output ETH.
	// @param exchangeAddr The address of the exchange for the token being purchased.
	// @return Amount of Tokens (exchangeAddr.token) bought.
	function tokenToExchangeTransferInput(uint256 tokensSold, uint256 minTokensBought, uint256 minETHbought, uint256 deadline, address recipient, address exchangeAddr) external returns (uint256) {
    	require(recipient != address(this), "Recipient cannot be self.");
    	return _tokenToTokenInput(tokensSold, minTokensBought, minETHbought, deadline, msg.sender, recipient, exchangeAddr);
	}

	// @notice Convert Tokens (self.token) to Tokens (exchangeAddr.token).
	// @dev Allows trades through contracts that were not deployed from the same factory.
	// @dev User specifies maximum input and exact output.
	// @param tokensBought Amount of Tokens (tokenAddr) bought.
	// @param maxtokensSold Maximum Tokens (self.token) sold.
	// @param maxETHsold Maximum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param exchangeAddr The address of the exchange for the token being purchased.
	// @return Amount of Tokens (self.token) sold.
	function tokenToExchangeSwapOutput(uint256 tokensBought, uint256 maxtokensSold, uint256 maxETHsold, uint256 deadline, address exchangeAddr) external returns (uint256) {
		return _tokenToTokenOutput(tokensBought, maxtokensSold, maxETHsold, deadline, msg.sender, msg.sender, exchangeAddr);
	}

	// @notice Convert Tokens (self.token) to Tokens (exchangeAddr.token) and transfers Tokens (exchangeAddr.token) to recipient.
	// @dev Allows trades through contracts that were not deployed from the same factory.
	// @dev User specifies maximum input and exact output.
	// @param tokensBought Amount of Tokens (tokenAddr) bought.
	// @param maxtokensSold Maximum Tokens (self.token) sold.
	// @param maxETHsold Maximum ETH purchased as intermediary.
	// @param deadline Time after which this transaction can no longer be executed.
	// @param recipient The address that receives output ETH.
	// @param tokenAddr The address of the token being purchased.
	// @return Amount of Tokens (self.token) sold.
	function tokenToExchangeTransferOutput(uint256 tokensBought, uint256 maxtokensSold, uint256 maxETHsold, uint256 deadline, address recipient, address exchangeAddr) external returns (uint256) {
		require(recipient != address(this), "Recipient cannot be self.");
		return _tokenToTokenOutput(tokensBought, maxtokensSold, maxETHsold, deadline, msg.sender, recipient, exchangeAddr);
	}

	// @notice Public price function for ETH to Token trades with an exact input.
	// @param ethSold Amount of ETH sold.
	// @return Amount of Tokens that can be bought with input ETH.
	function getEthToTokenInputPrice(uint256 ethSold) external view returns (uint256) {
		require(ethSold > 0, "ETH sold must be larger than zero.");
		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		return _getInputPrice(ethSold, address(this).balance, tokenReserve);
	}

	// @notice Public price function for ETH to Token trades with an exact output.
	// @param tokensBought Amount of Tokens bought.
	// @return Amount of ETH needed to buy output Tokens.
	function getEthToTokenOutputPrice(uint256 tokensBought) external view returns (uint256) {
		require(tokensBought > 0, "ETH bought must be larger than zero.");
		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 ethSold = _getOutputPrice(tokensBought, address(this).balance, tokenReserve);
		return ethSold;
	}

	// @notice Public price function for Token to ETH trades with an exact input.
	// @param tokensSold Amount of Tokens sold.
	// @return Amount of ETH that can be bought with input Tokens.
	function getTokenToEthInputPrice(uint256 tokensSold) external view returns (uint256) {
		require(tokensSold > 0, "Tokens sold must be larger than zero.");
		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		uint256 ethBought = _getInputPrice(tokensSold, tokenReserve, address(this).balance);
		return ethBought;
	}

	// @notice Public price function for Token to ETH trades with an exact output.
	// @param ethBought Amount of output ETH.
	// @return Amount of Tokens needed to buy output ETH.
	function getTokenToEthOutputPrice(uint256 ethBought) external view returns (uint256) {
		require(ethBought > 0, "ETH bought must be larger than zero.");
		uint256 tokenReserve = IERC20(_token).balanceOf(address(this));
		return _getOutputPrice(ethBought, tokenReserve, address(this).balance);
	}

	// @return Address of Token that is sold on this exchange.
	function tokenAddress() external view returns (address) {
		return _token;
	}

	// @return Address of factory that created this exchange.
	function factoryAddress() external view returns (address) {
		return _factory;
	}

	// ERC20 compatibility for exchange liquidity modified from https://github.com/ethereum/vyper/blob/master/examples/tokens/ERC20.vy
	function balanceOf(address owner) public view returns (uint256) {
		return _balances[owner];
	}

	function transfer(address to, uint256 value) public returns (bool) {
        require(to != address(0), "Recipient cannot be zero address.");
		_balances[msg.sender] = _balances[msg.sender].sub(value);
		_balances[to] = _balances[to].add(value);

		emit Transfer(msg.sender, to, value);
		return true;
	}

	function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(to != address(0), "Recipient cannot be zero address.");
		_balances[from] = _balances[from].sub(value);
		_balances[to] = _balances[to].add(value);
		_allowances[from][msg.sender] = _allowances[from][msg.sender].sub(value);

		emit Transfer(from, to, value);
		return true;
	}

	function approve(address spender, uint256 value) public returns (bool) {
		_allowances[msg.sender][spender] = value;

		emit Approval(msg.sender, spender, value);
		return true;
	}

	function allowance(address owner, address spender) public view returns (uint256) {
		return _allowances[owner][spender];
	}

	// @notice Convert ETH to Tokens.
	// @dev User specifies exact input (msg.value).
	// @dev User cannot specify minimum output or deadline.
	// function () external payable {
	// 	_ethToTokenInput(msg.value, 1, now, msg.sender, msg.sender);
	// }
}