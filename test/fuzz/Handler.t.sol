//Handler is going to narrow down the ways that we call functions so that we don't waste runs

// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployScript} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsc_engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    uint256 constant MAX_DEPOSIT_NUMBER = type(uint96).max;
    address user = makeAddr("user");
    MockV3Aggregator ethUSDPricefeed;


    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintCalled;

    constructor(DSCEngine _dsc_engine, DecentralizedStableCoin _dsc, HelperConfig _config) {
        dsc = _dsc;
        dsc_engine = _dsc_engine;
        config = _config;
        (,, weth, wbtc,) = config.activeConfig();
        timesMintCalled = 0;

        ethUSDPricefeed = MockV3Aggregator(dsc_engine.getCollateralTokenPriceFeed(weth));
    }

    //redeem collateral

    //call when u have collateral

    function depositCollateral(uint256 collateral_seed, uint256 amount_collateral) public {

        amount_collateral = bound(amount_collateral, 1, MAX_DEPOSIT_SIZE);

        ERC20Mock collateraltoken = _getCollateralfromSeed(collateral_seed);
        vm.startPrank(user);
        collateraltoken.mint(user, amount_collateral);
        collateraltoken.approve(address(dsc_engine), amount_collateral);
        dsc_engine.depositCollateral(address(collateraltoken), amount_collateral);
        vm.stopPrank();
    }

    function _getCollateralfromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        ERC20Mock token_to_deposit;
        if (collateralSeed % 2 == 0) {
            token_to_deposit = ERC20Mock(weth);
        } else {
            token_to_deposit = ERC20Mock(wbtc);
        }
        return token_to_deposit;
    }

    function redeemCollateral(uint256 collateralSeed , uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralfromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsc_engine.getCollateralBalanceOfUser( address(collateral), user);
        amountCollateral = bound(amountCollateral , 0, maxCollateralToRedeem);
        if(amountCollateral == 0){
            return;
        }
        vm.prank(user);
        dsc_engine.reedemCollateral( address(collateral) , amountCollateral);
    }

    //If fail_on_revert is false you can run this
    // function mintDSC(uint256 amount) public {
    //     amount = bound(amount , 1 , MAX_DEPOSIT_NUMBER);
    //     vm.startPrank(user);
    //     dsc_engine.mintDSC(amount);
    //     vm.stopPrank();
    // }


    //If fail on revert is true try running this
    function mintDSC(uint256 amount) public {

        
        (uint256 totalDSCMinted , uint256 totalCollateralValue) = dsc_engine.getAccountInformation(user);

        int256 maxDSCToMint = (int256(totalCollateralValue)/2) - int256(totalDSCMinted);
        if(maxDSCToMint < 0){
            return;
        }
        amount = bound(amount , 0 , uint256(maxDSCToMint));
        if( amount == 0){
            return ;
        }
        vm.startPrank(user);
        dsc_engine.mintDSC(amount);
        vm.stopPrank();
        timesMintCalled++;
    }

    // This function does not work if newPrice breaks protocol
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 price = int256(uint256(newPrice));
    //     ethUSDPricefeed.updateAnswer(price);
    // }
}
