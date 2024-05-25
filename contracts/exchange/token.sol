// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 
// Your token contract
contract Token is Ownable, ERC20 {
    string private constant _symbol = 'SK';
    string private constant _name = 'Simple Koin';

    bool private _disabled = false;
    constructor() ERC20(_name, _symbol) Ownable(msg.sender) {
    }

    function mint(uint amount) 
        public 
        onlyOwner
    {
        require(!_disabled, "Can not mint anymore");
        _mint(msg.sender, amount);
    }

    function disable_mint()
        public
        onlyOwner
    {
        require(!_disabled, "Can not disable anymore");
        _disabled = true;
    }
}
