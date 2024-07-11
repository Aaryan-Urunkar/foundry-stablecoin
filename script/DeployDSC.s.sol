// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;
import {Script , console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployScript is Script {

    address[] public tokenAddresses;
    address[] public pricefeedAddresses;

    function run() external returns(DecentralizedStableCoin , DSCEngine , HelperConfig){
        HelperConfig helperConfig = new HelperConfig();
        (address wethUSDPricefeed,
        address wbtcUSDPricefeed,
        address weth,
        address wbtc,
        ) = helperConfig.activeConfig();

        tokenAddresses = [weth , wbtc];
        pricefeedAddresses = [wethUSDPricefeed , wbtcUSDPricefeed];


        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine( tokenAddresses, pricefeedAddresses , address(dsc)); 
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (dsc , engine , helperConfig);
    }
}