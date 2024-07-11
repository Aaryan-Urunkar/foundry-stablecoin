// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;
import {Script , console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUSDPricefeed;
        address wbtcUSDPricefeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeConfig;
    uint8 constant DECIMALS = 8;
    int256 constant ETH_USD_PRICE = 3000e8;
    int256 constant BTC_USD_PRICE = 1000e8;
    uint256 constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor(){
        if(block.chainid == 11155111){
            activeConfig = getSepoliaETHConfig();
        } else {
            activeConfig = getAnvilETHConfig();
        }
    }

    function getSepoliaETHConfig() public view returns(NetworkConfig memory) {
        return NetworkConfig({
            wethUSDPricefeed:0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUSDPricefeed:0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth:0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc:0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC,
            deployerKey:vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilETHConfig() public returns(NetworkConfig memory){
        if(activeConfig.wethUSDPricefeed != address(0)){
            return activeConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUSDPricefeed = new MockV3Aggregator(DECIMALS , ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();
        MockV3Aggregator btcUSDPricefeed = new MockV3Aggregator(DECIMALS , BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wethUSDPricefeed:address(ethUSDPricefeed),
            wbtcUSDPricefeed:address(btcUSDPricefeed),
            weth:address(wethMock),       
            wbtc:address(wbtcMock),
            deployerKey:DEFAULT_ANVIL_KEY
        });
    }
}