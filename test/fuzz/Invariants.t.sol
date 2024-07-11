//This file should have our invariants... aka properties of the system that should always hold

/** 
 * Some invariants in our project:
 * 1. The total supply of DSC should be lesser than total value of collateral
 * 2. Getter view functions should never revert
 */

// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;
import {Test , console } from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployScript} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is  StdInvariant , Test{ 
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() public {
        DeployScript deployer = new DeployScript();
        (dsc , dsce , config ) = deployer.run();
        handler = new Handler(dsce, dsc , config);
        targetContract(address(handler)); //Tells foundry to go absolutely wild on this

        ( , , weth , wbtc , ) = config.activeConfig();
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() external view {
        //get the value of all the collateral in the protocol
        // compare it to the total DSC supply

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        uint256 wethValue = dsce.getUSDAmount(weth , totalWethDeposited);
        uint256 wbtcValue = dsce.getUSDAmount(wbtc , totalWbtcDeposited);
        console.log("Times mint called: " , handler.timesMintCalled());
        assert((wethValue + wbtcValue) >= (totalSupply));
    }
}