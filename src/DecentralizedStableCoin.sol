// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 @title DecentralizedStableCoin
 @author:JustUzair
 Collateral: Exogenous
 Minting: ALgorithmic
 Relative Stability: Pegged to USD


 This is contract meant to be governed by DSCEngine. This is just ERC20 implementation of our stablecoin
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin_MustBeGreaterThanZero();
    error DecentralizedStableCoin_NotEnoughBalance(uint256 _amount);
    error DecentralizedStableCoin_NotZeroAddress(address _address);

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin_MustBeGreaterThanZero();
        }
        if (_amount < balance) {
            revert DecentralizedStableCoin_NotEnoughBalance(_amount);
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin_NotZeroAddress(_to);
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin_MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
