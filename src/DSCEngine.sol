// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./OracleLib.sol";

/**
 * @title DSCEngine
 * @author Aaryan Urunkar
 *
 * This system is designed to be as minimal as possible and maintain a 1 token == 1 USD peg
 * This stable has the following properties:
 *  - Algorithmic minting
 *  - Dollar pegged
 *  - Exogenous collateral
 *
 * Our DSC system should always be "overcollateralized". At no point should the value of all collateral <= the USD backed value of all DSC
 *
 * @notice It is the core of the DSC System. Handles all the logic for minting and redeeming DSC, as well as withdrawing collateral
 * @notice This contract is very loosely based on the MakerDAO DSS(DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngineNeedsMoreThanZero();
    error DSCEngineTokenAddressAndPricefeedAddressMustBeOfSameLength();
    error DSCEngineTokenNotAllowed();
    error DSCEngineTransferFailed();
    error DSCEngineBreaksHealthFactor();
    error DSCEngineMintFailed();
    error DSCEngineNotEnoughDSCToBurn();
    error DSCEngineHealthFactorOk();
    error DSCEngineHealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;


    event CollateralDeposited(address user, address token, uint256 amount);
    event CollateralReedemed(address redeemedFron, address reedemedTo, address token, uint256 amount);

    uint256 private constant FEED_PRECISION_CONSTANT = 1e10;
    uint256 private constant FEED_AMOUNT_PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //If this is 50, it means users need to be 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS_PERCENTAGE = 10;

    mapping(address token => address priceFeed) private s_pricefeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin immutable i_dsc;

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngineNeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_pricefeeds[tokenAddress] == address(0)) {
            revert DSCEngineTokenNotAllowed();
        }
        _;
    }
    /**
     * @dev Sets the s_pricefeeds and s_collateralDeposited
     * @param tokenAddress Stores the token addresses for different tokens
     * @param pricefeedAddresses Stores the pricefeed addresses for different tokens(ex: pricefeed address for BTC/USD)
     * @param dscAddress Address of the deployed DecentralizedStableCoin.sol contract
     */

    constructor(address[] memory tokenAddress, address[] memory pricefeedAddresses, address dscAddress) {
        if (tokenAddress.length != pricefeedAddresses.length) {
            revert DSCEngineTokenAddressAndPricefeedAddressMustBeOfSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_pricefeeds[tokenAddress[i]] = pricefeedAddresses[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////////////
    ///External and public functions///
    //////////////////////////////////

    /**
     * @notice The function which people can call to store collateral and mint DSC in one transaction
     * @param tokenCollateralAddress Address of the collateral token to be passed
     * @param amountCollateral Amount of the collateral
     * @param amountDSCToMint Amount of DSC to be minted
     *
     * Combination of depositCollateral() and mintDSC()
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @dev follows CEI : Checks, Effects, Interactions
     * @param tokenCollateralAddress The address of the token to use as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngineTransferFailed();
        }
    }

    /**
     * In order to redeem collateral, their health factor must be 1 AFTER collaterall is taken
     *
     * @param tokenCollateralAddress Address of token collateral
     * @param amountCollateral Amount of collateral
     */
    function reedemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _reedemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev To mint DSC, first :
     *  - Check if collateral value > DSC amount
     *
     * @param amountDSCToMint The amount of DSC to mint
     * @notice They must have more collateral so that they can mine DSC
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngineMintFailed();
        }
    }

    /**
     * @notice A function to burn some DSC from supply
     * @param amount Amount of DSC that has to burned
     */
    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
    }

    /**
     * @param tokenCollateralAddress Address of token of collateral to be reedemed
     * @param amountCollateral Amount of collateral of token to be reedemed
     * @param amountDSCToBurn Amount of DSC to be burned
     *
     * @notice This function burns DSC and reedems underlying collateral
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        burnDSC(amountDSCToBurn);
        reedemCollateral(tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @dev A function other users can call to remove people's positions to save the protocol
     *
     * Requirements -
     *  The person who is liquidated must be over a certain limit, a.k.a be perilously close to "undercollateralization"
     *  with his holdings of the stablecoin
     *
     * Whoever is the liquidator takes the collateral of the person whose health factor is not met and pays off the entire debt
     *
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who might get liquidated
     * @param debtToCover The debt/DSC held by the one to be liquidated
     *
     * @notice The function assumes that the protocol is always "overcollaterizalized" by 200%
     *
     * @notice A known bug would be that if the protocol is collateralized by 100% or less, liquidators wouldn't be
     *         incentivized to liquidate users
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external {
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngineHealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);
        //We are giving our liquidator a 10% bonus.
        //Example: A bad user has 140$ ETH and holds 100$ of DSC
        //         Liquidator liquidates those $100 and should recieve 110$ back for that liquidation
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATOR_BONUS_PERCENTAGE) / 100;
        uint256 totalCollateralToReedem = bonusCollateral + tokenAmountFromDebtCovered;
        _reedemCollateral(collateral, totalCollateralToReedem, user, msg.sender);
        _burnDSC(debtToCover, user, msg.sender);
        uint256 endingHealthFactor = _getHealthFactor(user);
        if (endingHealthFactor <= startingUserHealthFactor) {
            revert DSCEngineHealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor( address user )public view returns(uint256){
        return _getHealthFactor(user);
    }

    /**
     * @param user User to fetch collateral value for
     * @notice This function returns the USD equivalent of the total collateral of a user
     */
    function getAccountCollateralValue(address user) public view returns (uint256) {
        address token;
        uint256 amount;
        uint256 totalCollateralValueInUSD;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            token = s_collateralTokens[i];
            amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDAmount(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /**
     *
     * @param token The token address whose value is to be converted to USD
     * @param amount The amount to be converted to USD
     *
     * @dev Uses chainink data feeds for price conversion
     *  Returned answer will ideally have 8 decimal places if we use BTC/USD or ETH/USD so multiply by 1e8
     *  But our amount when converted will be of 1e18 form
     *  So multiply by an additional 1e18( or FEED_PRECISION_CONSTANT)
     */
    function getUSDAmount(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(s_pricefeeds[token]);
        (, int256 answer,,,) = dataFeed.staleCheckLatestRoundData();
        return ((uint256(answer) * FEED_PRECISION_CONSTANT) * amount) / FEED_AMOUNT_PRECISION;
        //answer already has 8 decimal places hence we multiply by 1e10 for precision
    }

    /**
     * @notice Calculates the total USD from the amount of tokens held in the collateral
     */
    function getTokenAmountFromUSD(address token, uint256 amountUsdInWei) public view returns (uint256) {
        AggregatorV3Interface datafeed = AggregatorV3Interface(s_pricefeeds[token]);
        (, int256 answer,,,) = datafeed.staleCheckLatestRoundData();
        return (amountUsdInWei * FEED_AMOUNT_PRECISION) / (uint256(answer) * FEED_PRECISION_CONSTANT);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValue)
    {
        ( totalDSCMinted, totalCollateralValue) =  _getAccountInformation(user);
    }

    function getCollateralTokens() public view returns(address[] memory){
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_pricefeeds[token];
    }

    ////////////////////////
    ///Internal functions//
    //////////////////////

    /**
     *
     * @param user Address of user to get account information
     * @return totalDSCMinted The amount of DSC minted by the user
     * @return totalCollateralValue The total collateral value deposited by the user
     */
    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValue)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValue = getAccountCollateralValue(user);
        return (totalDSCMinted, totalCollateralValue);
    }

    /**
     * @param user User in question
     *
     * Returns how close to liqidation a user is
     */
    function _getHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = _getAccountInformation(user);
        if(totalDSCMinted == 0){
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * FEED_AMOUNT_PRECISION / totalDSCMinted);

        //Example:
        //User 150 USD in ETH(say x) -> 100 DSC minted
        // collateralValue = (x * 50)/100= x/2
        // (x/2) /100 = x/200 = 150/200 < 1
        //We can say a safe value would be 200USD in ETH
        //Hence users need to be 200% overcollateralized
    }

    /**
     * @notice Check if the user has enough collateral or not
     * @param user The user whose positions are to be examined
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        if(s_DSCMinted[user] != 0){
            uint256 userHealthFactor = _getHealthFactor(user);
            if (userHealthFactor < MIN_HEALTH_FACTOR) {
                revert DSCEngineBreaksHealthFactor();
            }
        }
    }

    /**
     * A low-level function which basically lets someone reedeem someone else's collateral
     * @param tokenCollateralAddress Address of token collateral
     * @param amountCollateral The amount of collateral to be transferred
     * @param from The address from which collateral will be transferred
     * @param to The address to which collateral will be transferred
     */
    function _reedemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralReedemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngineTransferFailed();
        }
    }

    /**
     * @dev Low-level function. Do not call unless function calling it is checking for health factors
     *      being broken
     *
     * @param amountDSCToBurn Amount to be burned
     * @param onBehalfOf Who's initiating the burn
     * @param dscFrom Whose positions are being burned
     */
    function _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address dscFrom) private {
        if (s_DSCMinted[onBehalfOf] < amountDSCToBurn) {
            revert DSCEngineNotEnoughDSCToBurn();
        }
        s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngineTransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
    }
}
