// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;
import {Test , console} from "forge-std/Test.sol";
import {DeployScript} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract DSCEngineTest is Test{

    event CollateralDeposited(address user, address token, uint256 amount);

    DeployScript deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address wethUSDPricefeed;
    address wbtcUSDPricefeed;
    address weth;
    address wbtc;
    
    address USER = makeAddr("user");
    uint256 constant AMOUNT_COLLATERAL = 10 ether;
    uint256 constant STARTING_ERC20_BALANCE = 10 ether;

    address LIQUIDATOR = makeAddr("liquidator");

    

    function setUp() external{
        deployer = new DeployScript();
        (dsc , engine ,helperConfig) = deployer.run();
        ( wethUSDPricefeed,
        wbtcUSDPricefeed,
        weth,
        wbtc,
        ) = helperConfig.activeConfig();

        ERC20Mock(weth).mint(USER , STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR , 2* STARTING_ERC20_BALANCE);
    }

    ////////////////////////////// 
    /// Constructor tests////////
    //////////////////////////// 

    address[] tokenAddresses ;
    address[] pricefeedAddresses;
    function testRevertsIfTokenLengthDoesntMatchPricefeed() external {
        tokenAddresses.push(weth);
        pricefeedAddresses.push(wethUSDPricefeed);
        pricefeedAddresses.push(wbtcUSDPricefeed);
        vm.expectRevert(DSCEngine.DSCEngineTokenAddressAndPricefeedAddressMustBeOfSameLength.selector);
        new DSCEngine(tokenAddresses , pricefeedAddresses ,address(dsc));
    }

    ////////////////////// 
    ////Price tests////// 
    //////////////////// 
    function testGetUSDValue() external view{
        uint256 ethAmount = 15e18;
        uint256 expectedUSD = 15e18 * 3000;
        uint256 actualUSD = engine.getUSDAmount(weth , ethAmount);
        console.log("Expected: " ,expectedUSD);
        console.log("Actual: " ,actualUSD);
        assertEq(actualUSD , expectedUSD);
    }

    function testGetTokenAmountFromUSD() external view {
        uint256 usdAmount = 300 ether;
        uint256 expectedWeth = 0.1 ether;
        uint256 actualWeth = engine.getTokenAmountFromUSD(weth , usdAmount);
        assertEq(expectedWeth ,actualWeth );
    }

    /////////////////////
    //Health Factor/////
    ///////////////////

    function testGetHealthFactorReturnsCorrect() external depositedCollateral{
        //When 0 DSC is minted, the health factor is the maximum

        uint256 mintAmt = 5000e18;
        uint256 PRECISION = 1e18;
        assertEq(engine.getHealthFactor(USER) , type(uint256).max);

        vm.prank(USER);
        engine.mintDSC(mintAmt);
        (uint256 totalDSCMinted , uint256 totalCollateral) = engine.getAccountInformation(USER);
        uint256 expectedHealthFactor = ((totalCollateral/2) * PRECISION) / totalDSCMinted ;  
        assertEq(engine.getHealthFactor(USER) , expectedHealthFactor );
    }

    //////////////////////
    //depositCollateral//
    ////////////////////

    function testDepositCollateralRevertsIfZero() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(USER , AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngineNeedsMoreThanZero.selector);
        engine.depositCollateral(weth , 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() external {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngineTokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken) , AMOUNT_COLLATERAL);
    }

    modifier depositedCollateral {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine) , AMOUNT_COLLATERAL);
        engine.depositCollateral( weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() external depositedCollateral{
        (uint256 totalDSCMinted , uint256 totalCollateralValue ) = engine.getAccountInformation(USER);
        assertEq(engine.getUSDAmount(weth ,  AMOUNT_COLLATERAL ) , totalCollateralValue);
        assertEq( 0, totalDSCMinted);
    }
    
    function testDepositCollateralEmitsEvent() external{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine) , AMOUNT_COLLATERAL);
        vm.expectEmit(true , true, true, false , address(engine));
        emit CollateralDeposited(USER , weth ,AMOUNT_COLLATERAL);       
        engine.depositCollateral( weth, AMOUNT_COLLATERAL);
        vm.stopPrank();        
    }

    //////////////////////
    //reedemCollateral///
    ////////////////////

    function testReedemAmountEqualsZero() external depositedCollateral{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngineNeedsMoreThanZero.selector);
        engine.reedemCollateral(weth , 0 );
    }

    function testReedemAmountAndGetAccountInformation() external depositedCollateral{
        vm.startPrank(USER);
        engine.reedemCollateral(weth , 5 ether);
        uint256 expectedCollateralValue = 5 ether;
        ( , uint256 totalCollateralValue ) = engine.getAccountInformation(USER);
        assertEq(engine.getTokenAmountFromUSD(weth , totalCollateralValue) ,expectedCollateralValue );
    }

    function testGetAccountCollateralValueFunction() external depositedCollateral{
        uint256 initialExpectedCollateral = engine.getUSDAmount(weth , AMOUNT_COLLATERAL);
        uint256 initialActualCollateral = engine.getAccountCollateralValue(USER);

        vm.startPrank(USER);
        engine.reedemCollateral(weth , 5 ether);
        vm.stopPrank();

        uint256 finalExpectedCollateral = engine.getUSDAmount(weth , AMOUNT_COLLATERAL - 5 ether);
        uint256 finalActualCollateral = engine.getAccountCollateralValue(USER);

        assertEq(initialActualCollateral , initialExpectedCollateral);
        assertEq(finalActualCollateral , finalExpectedCollateral );
    }

    function testDepositCollateralMintDSCReedemCollateral()external depositedCollateral{

        uint256 reedemAmount = 5 ether;
        uint256  mintAmount = 5000e18;

        (uint256 initialMintedDSC , uint256 initialCollateralValue) = engine.getAccountInformation(USER);
        vm.startPrank(USER);
        engine.mintDSC(mintAmount);
        engine.reedemCollateral(weth , reedemAmount);
        vm.stopPrank();
        (uint256 finalMintedDSC , uint256 finalCollateralValue) = engine.getAccountInformation(USER);
        assertEq(finalMintedDSC , initialMintedDSC + mintAmount);
        assertEq(initialCollateralValue , finalCollateralValue + engine.getUSDAmount(weth , reedemAmount));
    }



    //////////////
    //mintDSC////
    ////////////

    function testMintingTooMuchDSC() external depositedCollateral{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngineBreaksHealthFactor.selector);
        engine.mintDSC(16000e18);
        vm.stopPrank();
    }

    function testMintingUpdatesMapping() external depositedCollateral {
        uint256  mintAmount = 5000e18;
        vm.startPrank(USER);
        engine.mintDSC(mintAmount);
        ( uint256 mintedDSC, ) = engine.getAccountInformation(USER);
        assertEq(mintAmount , mintedDSC);
        vm.stopPrank();
    }

    ////////////////
    ///liquidate///
    //////////////

    function testLiquidateRevertsIfHealthFactorIsSufficient() external depositedCollateral {
        uint256  mintAmount = 5000e18;
        vm.startPrank(USER);
        engine.mintDSC(mintAmount);
        vm.stopPrank();
        vm.startPrank(LIQUIDATOR);
        ( ,uint256 totalCollateralValue ) = engine.getAccountInformation(USER);
        vm.expectRevert(DSCEngine.DSCEngineHealthFactorOk.selector);
        engine.liquidate(weth , USER, totalCollateralValue);
        vm.stopPrank();
    }

    /////////////
    ///Burn/////
    ///////////

    function testRevertIfUserBurnsMoreDSCThanPosesses() external depositedCollateral{
        uint256  mintAmount = 5000e18;
        uint256 burnAmount = 6000e18;
        vm.startPrank(USER);
        engine.mintDSC(mintAmount);
        vm.expectRevert(DSCEngine.DSCEngineNotEnoughDSCToBurn.selector);
        engine.burnDSC(burnAmount);
        vm.stopPrank();
    }

    function testBurnDSCSuccessful() external depositedCollateral {
        
        uint256  mintAmount = 5000e18;
        uint256 burnAmount = 50e18;
        vm.startPrank(USER);
        engine.mintDSC(mintAmount);
        ( uint256 totalDSCMintedInitial, ) = engine.getAccountInformation(USER);
        dsc.approve(address(engine) , mintAmount);
        engine.burnDSC( burnAmount );
        vm.stopPrank();
        ( uint256 totalDSCMintedFinal, ) = engine.getAccountInformation(USER);
        assertEq(totalDSCMintedInitial - burnAmount , totalDSCMintedFinal);
    }

    ///////////////////////////
    //redeemCollateralForDSC//
    /////////////////////////

    function testIfAccountHoldingsAreUpdated() external depositedCollateral{
        uint256  mintAmount = 10000e18;
        uint256 burnAmount = 3000e18;
        uint256 collateralRedeemed = 5 ether;
        vm.startPrank(USER);
        engine.mintDSC(mintAmount);
        ( uint256 totalDSCMintedInitial, uint256 totalCollateralValueInitial) = engine.getAccountInformation(USER);
        dsc.approve(address(engine) , mintAmount);
        engine.redeemCollateralForDSC( weth,collateralRedeemed , burnAmount);
        vm.stopPrank();
        ( uint256 totalDSCMintedFinal, uint256 totalCollateralValueFinal) = engine.getAccountInformation(USER);
        assertEq(totalDSCMintedInitial - burnAmount , totalDSCMintedFinal);
        assertEq( totalCollateralValueInitial - engine.getUSDAmount(weth , collateralRedeemed), totalCollateralValueFinal);
    }

    function testRevertsIfResultantHealthFactorIsBad() external depositedCollateral{
        uint256  mintAmount = 10000e18;
        uint256 burnAmount = 2000e18;
        uint256 collateralRedeemed = 5 ether;
        vm.startPrank(USER);
        engine.mintDSC(mintAmount);
        dsc.approve(address(engine) , mintAmount);
        vm.expectRevert(DSCEngine.DSCEngineBreaksHealthFactor.selector);
        engine.redeemCollateralForDSC( weth,collateralRedeemed , burnAmount);
        vm.stopPrank();
    }
}