// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";

contract TokenExchange is Ownable {
    string public exchange_name = '';

    address tokenAddr = 0x132A0153251d865942D8001998396738FFfddBa4;
    Token public token = Token(tokenAddr);

    // Liquidity pool for the exchange
    uint256 private token_reserves = 0;
    uint256 private eth_reserves = 0;

    // Fee Pools
    uint256 private token_fee_reserves = 0;
    uint256 private eth_fee_reserves = 0;

    // Liquidity pool shares
    mapping(address => uint256) public lps;

    struct Reward {
        uint256 eth_reward;
        uint256 token_reward;
    }
    mapping(address => Reward) public lp_reward;

    //
    address[] public lp_providers;

    // Total Pool Shares
    uint256 public total_shares = 0;

    // liquidity rewards
    uint256 private swap_fee_numerator = 3;
    uint256 private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint256 private k;

    uint256 private multiplier = 10**10;

    constructor() Ownable(msg.sender) {}


    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint256 amountTokens)
    external
    payable
    onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint256 tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;

        // Pool shares set to a large value to minimize round-off errors
        total_shares = 10**5;
        // Pool creator has some low amount of shares to allow autograder to run
        lps[msg.sender] = 100;
    }

    // For use for ExtraCredit ONLY
    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint256 index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint256, uint256) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // Function getReserves
    function getReserves() public view returns (uint256, uint256) {
        return (eth_reserves, token_reserves);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================

    /* ========================= Liquidity Provider Functions =========================  */

    function updateReward() internal {
        uint256 _total_share = total_shares;
        uint256 _length = lp_providers.length;
        uint256 _token_reserves_fee = token_fee_reserves;
        uint256 _eth_reserves_fee = eth_fee_reserves;

        if (_token_reserves_fee > 0 || _eth_reserves_fee > 0) {
            for (uint256 i = 0; i<_length; i++) {
                address _provider = lp_providers[i];
                uint256 _liquidity = lps[_provider];

                uint256 _eth_reward = _eth_reserves_fee * _liquidity / _total_share;
                uint256 _token_reward = _token_reserves_fee * _liquidity / _total_share;

                lp_reward[_provider].eth_reward += _eth_reward;
                lp_reward[_provider].token_reward += _token_reward;
            }

            token_fee_reserves = 0;
            eth_fee_reserves = 0;
        }
    }

    function addProvider (address provider) internal {
        uint256 length = lp_providers.length;
        for (uint256 i=0; i<length; i++) {
            if (lp_providers[i] == provider) {
                return;
            }
        }
        lp_providers.push(provider);
    }

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(
        uint256 amountToken
    )
    external
    payable
    {
        require(eth_reserves > 0 && token_reserves > 0, "Eth and Token reserves must be not 0");
        require(msg.value > 0, "Invalid Eth Value");

        uint256 amountEth = msg.value;
        uint256 _eth_reserves = eth_reserves;
        uint256 _token_reserves = token_reserves;

        uint256 _expect_amount_token = amountEth * _token_reserves / _eth_reserves;
        require(_expect_amount_token <= amountToken, "Invalid Token Value");

        updateReward(); /// must be update before add another liquidity provider
        token.transferFrom(msg.sender, address(this), _expect_amount_token);

        uint user_share = total_shares * _expect_amount_token / _token_reserves;

        eth_reserves += amountEth;
        token_reserves += _expect_amount_token;
        total_shares += user_share;
        lps[msg.sender] += user_share;
        addProvider(msg.sender);
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(
        uint256 withdrawLiquidity
    )
    public
    payable
    {
        address sender = msg.sender;
        uint256 _liquidity = lps[sender];
        uint256 _total_share = total_shares;

        uint256 _eth_reserve = eth_reserves;
        uint256 _token_reserve = token_reserves;

        require(withdrawLiquidity > 0 && withdrawLiquidity <= _liquidity && _liquidity < _total_share, "Invalid Amount Liquidity");

        updateReward();

        uint256 _eth_withdraw = _eth_reserve * withdrawLiquidity / _total_share;
        uint256 _token_withdraw = _token_reserve * withdrawLiquidity / _total_share;

        uint256 _eth_reward = lp_reward[sender].eth_reward * withdrawLiquidity / _liquidity;
        uint256 _token_reward = lp_reward[sender].token_reward * withdrawLiquidity / _liquidity;

        eth_reserves -= _eth_withdraw;
        token_reserves -= _token_withdraw;

        lp_reward[sender].eth_reward -= _eth_reward;
        lp_reward[sender].token_reward -= _token_reward;

        lps[sender] -= withdrawLiquidity;
        total_shares -= withdrawLiquidity;

        uint256 _token_receive = _token_reward + _token_withdraw;
        uint256 _eth_receive = _eth_reward + _eth_withdraw;
        token.transfer(sender, _token_receive);
        payable(msg.sender).transfer(_eth_receive);
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity()
    external
    payable
    {
        address sender = msg.sender;
        uint256 _liquidity = lps[sender];
        uint256 index;
        uint256 _length = lp_providers.length;
        for (uint256 i=0; i<_length; i++) {
            if (lp_providers[i] == sender) {
                index = i;
            }
        }

        removeLiquidity(_liquidity);
        removeLP(index);
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint256 amountTokens, uint256 amountETHMin)
    external
    payable
    {
        uint256 _reserveToken = token_reserves; /// save gas
        uint256 _reserveEth = eth_reserves; /// save gas

        require(amountTokens > 0 && amountTokens < _reserveToken, "Invalid Amount In");
        require(token_reserves > 0 && eth_reserves > 0, "Insufficient reserves");

        uint256 _feeAmountToken = amountTokens * swap_fee_numerator / swap_fee_denominator;
        uint256 _exactAmountToken = amountTokens - _feeAmountToken;

        uint256 amount_out_numerator = _exactAmountToken * _reserveEth;
        uint256 amount_out_denominator = _reserveToken + _exactAmountToken;
        uint256 _exactAmountEth = amount_out_numerator / amount_out_denominator;

        require(_exactAmountEth >= amountETHMin && _exactAmountEth < _reserveEth, "Insufficient ETH");
        token_reserves = _reserveToken + _exactAmountToken;
        eth_reserves = _reserveEth - _exactAmountEth;
        k = token_reserves * eth_reserves;
        token_fee_reserves += _feeAmountToken;

        token.transferFrom(msg.sender, address(this), amountTokens);
        payable(msg.sender).transfer(_exactAmountEth);
    } /// chinh xac fee da hoat dong



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint256 amountTokenMin)
    external
    payable
    {
        uint256 _reserveToken = token_reserves;
        uint256 _reserveEth = eth_reserves;

        uint256 amountEth = msg.value;
        require(amountEth > 0 && amountEth < _reserveEth, "Invalid Amount In");
        require(token_reserves > 0 && eth_reserves > 0, "Insufficient reserves");

        uint256 _feeAmountEth = amountEth * swap_fee_numerator / swap_fee_denominator;
        uint256 _exactAmountEth = amountEth - _feeAmountEth;

        uint256 amount_out_numerator = _exactAmountEth * _reserveToken;
        uint256 amount_out_denominator = _exactAmountEth + _reserveEth;
        uint256 _exactAmountToken = amount_out_numerator / amount_out_denominator;

        require(_exactAmountToken >= amountTokenMin && _exactAmountToken < _reserveToken, "Insufficient Token");

        eth_reserves = _reserveEth + _exactAmountEth;
        token_reserves = _reserveToken - _exactAmountToken;
        k = token_reserves * eth_reserves;
        eth_fee_reserves += _feeAmountEth;

        token.transfer(msg.sender, _exactAmountToken);
    } /// Chinh xac, fee da hoat dong

    function getFeeReserves() public view returns (uint256, uint256) {
        return (eth_fee_reserves, token_fee_reserves);
    }
}

