// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;
import {ERC20Burnable , ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralized Stablecoin
 * @author Aaryan Urunkar
 * Collateral: Exgoneous(ETH or BTC)
 * Minting: Algorithmic
 * Relative stability: Pegged to USD
 * @notice This is the contract meant tot e ogverned by DSCEngine. This contract is just
 * the ERC20 implementation of our stablecoin.
 */

contract DecentralizedStableCoin is ERC20Burnable , Ownable {

    error DecentralizedStableCoinMustBeMoreThanZero();
    error DecentralizedStableCoinMustHaveEnoguhBalance();
    error DecentralizedStableCoinInvalidReciever();



    constructor() ERC20("DecentralizedStableCoin","DSC") Ownable(msg.sender){}

    function burn(uint256 _amount)public override onlyOwner { //Only the DSCEngine(aka the logic that we give it) can mint and burn
        uint256 balance = balanceOf(msg.sender);
        if( _amount <= 0){
            revert DecentralizedStableCoinMustBeMoreThanZero();
        } else if(balance < _amount){
            revert DecentralizedStableCoinMustHaveEnoguhBalance();
        } else {
            super.burn(_amount);
        }
    }

    function mint(address to , uint256 _value) external onlyOwner returns(bool){ 
        if(to == address(0)){ //Address 0 is a special address whch cannot accept nor transact ETH
            revert DecentralizedStableCoinInvalidReciever();
        }
        if(_value < 0){
            revert DecentralizedStableCoinMustBeMoreThanZero();
        }
        _mint( to, _value );
        return true;
    }
}