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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/// @title DSCEngine
/// @author JustUzair
/// The system is designed to be as minimal as possible, so that it can be easily understood and verified and have 2 tokens maintain a token === $1 peg
//  Collateral: Exogenous
//  Minting: ALgorithmic
//  Relative Stability: Pegged to USD
/// @notice This contract is the core of DSC System. It handles all the logic for minting and burning the DecentralizedStableCoin (DSC), as well as depositing and withdrawing the collateral.
/// @dev This contract is meant to be inherited by DecentralizedStableCoin contract

contract DSCEngine is ReentrancyGuard {
    //////////////
    /// ERRORS ///
    //////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndPriceFeedLengthMismatch(address[] tokenAddresses, address[] priceFeedAddresses);
    error DSCEngine__NotAllowedToken(address _tokenAddress);
    error DSCEngine__TokenTransferFailed();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__TokenMintFailed();
    error DSCEngine__NotEnoughBalance();
    error DSCEngine__CollateralRedemptionFailed();
    error DSCEngine__HealthFactorNotBroken(address _user);
    error DSCEngine__HealthFactorNotImproved();

    /////////////
    /// TYPES ///
    /////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////////
    /// STATE VARIABLES ///
    ///////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => uint256 amountDscMinted) s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    //////////////
    /// EVENTS ///
    //////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    /////////////////
    /// MODIFIERS ///
    /////////////////

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken(_tokenAddress);
        }
        _;
    }

    /////////////////
    /// FUNCTIONS ///
    /////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAndPriceFeedLengthMismatch(tokenAddresses, priceFeedAddresses);
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////
    /// EXTERNAL FUNCTIONS ///
    //////////////////////////

    /// @notice follows CEI
    /// @param tokenCollateralAddress Address of the collateral token
    /// @param amountCollateral Amount of collateral to deposit
    /// @param amountDscToMint Amount of DSC to mint
    /// @notice function will deposit collateral and mint DSC in one transaction

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /// @notice follows CEI
    /// @param _tokenCollateralAddress Address of the collateral token
    /// @param _amountCollateral Amount of collateral to deposit

    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__TokenTransferFailed();
        }
    }

    /// @param _collateralTokenAddress Address of the collateral token
    /// @param _collateralAmount Amount of collateral to redeem
    /// @param amountDscToBurn Amount of DSC to burn
    function redeemCollateralForDSC(address _collateralTokenAddress, uint256 _collateralAmount, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(_collateralTokenAddress, _collateralAmount); // redeeemCollateral checks the health factor
    }

    function redeemCollateral(address _collateralTokenAddress, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        isAllowedToken(_collateralTokenAddress)
        nonReentrant
    {
        _redeemCollateral(_collateralTokenAddress, _collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice follows CEI
    /// @param amountDscToMint Amount of DSC to mint
    /// @notice they must have more amount than minimum threshold
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__TokenMintFailed();
        }
    }

    /// @notice follows CEI : Checks, Effects, Interactions
    /// @param _collateralToken Address of the collateral token
    /// @param _user Address of the user to liquidate
    /// @param _debtToCover Amount of DSC to cover
    /// @notice If someone is almost undercollateralized, we will pay you to liquidate them
    /// @notice You can partially liquidate a user
    /// @notice you will get a portion of the collateral as reward.
    /// @notice this function assumes that the protocol will be 200% overcollateralized
    /// @notice a known bug is that if the protocol is 100% collateralized or less, then we wouldn't be able to incentivize liquidators
    // example : the price of collateral plummets before anyone could liquidate the user

    function liqiudate(address _collateralToken, address _user, uint256 _debtToCover)
        external
        nonReentrant
        moreThanZero(_debtToCover)
    {
        uint256 startingUserHealthFactor = _healthFactor(_user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotBroken(_user);
        }

        // We want to burn the DSC from the user
        // and take their collateral
        // Bad User: $100 DSC, $140 ETH
        // debtToCover = $100
        // $100 DSC = ??ETH
        // suppose value of 1 eth =  $2000
        // 100/2000 = 0.05ETH (debt/value of collateral)
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_collateralToken, _debtToCover);
        // we give 10% bonus to the liquidator
        // example : we give them $110 of weth for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent and sweep extra amounts into the treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(_collateralToken, totalCollateralToRedeem, _user, msg.sender);
        // msg.sender is liquidating the `user`, so msg.sender pays the debt
        _burnDsc(_debtToCover, _user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(_user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address _collateralToken, uint256 amountUsdInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_collateralToken]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // collateral value (eth) = 140
        // debt to cover = $100
        // $10e18 * 1e18 / ($2000 * 1e10) = 100e16
        // 10e36 / 2000e10 = 5e26
        // 5e26 = 500000000000000000000000000
        return (amountUsdInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
    /////////////////////////////////////////
    /// PRIVATE & INTERNAL VIEW FUNCTIONS ///
    /////////////////////////////////////////

    /// @dev low level internal function, do not call until the caller has checked the health factor
    /// @param amountDscToBurn Amount of DSC to burn
    /// @param onBehalfOf Address of the user to on behalf of whom the user pays the debt
    /// @param dscFrom Address of the user to burn DSC from
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) internal {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TokenTransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        _revertIfHealthFactorIsBroken(dscFrom);
    }

    function _redeemCollateral(address _collateralTokenAddress, uint256 _collateralAmount, address from, address to)
        private
    {
        s_collateralDeposited[from][_collateralTokenAddress] -= _collateralAmount;
        emit CollateralRedeemed(from, to, _collateralTokenAddress, _collateralAmount);
        bool success = IERC20(_collateralTokenAddress).transfer(to, _collateralAmount);
        if (!success) {
            revert DSCEngine__CollateralRedemptionFailed();
        }
    }
    /// @notice returns the health factor of the user, i.e. how close the user is to getting liquidated

    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValue)
    {
        totalDscMinted = s_DSCMinted[_user];
        totalCollateralValue = getAccountCollateralValue(_user);
        return (totalDscMinted, totalCollateralValue);
    }

    function _healthFactor(address _user) internal view returns (uint256) {
        // total dsc minted
        // VALUE of total collateral deposited

        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getAccountInformation(_user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // totalCollateralValue = 1e18
        // collateralAdjustedForThreshold = 1e18 * 50 / 100 = 5e17
        /*
            adjusted collateral / total DSC = health factor

            $150 worth ETH / 100 DSC = 1.5 ---> original before adjusting collateral
            150 ETH * 50 = 7500 (after health factor precision) / 100 DSC = 75 ---> adjusted collateral
                |----> 75/100 < 1 ----> below 1 -----> you can get liquidated
            
         */

        return uint256((collateralAdjustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken();
        }
    }

    ////////////////////////////////////////
    /// PUBLIC & EXTERNAL VIEW FUNCTIONS ///
    ////////////////////////////////////////

    function getAccountCollateralValue(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address _tokenAddress, uint256 _tokenAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenAddress]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = $1000
        // The returned value from the price feed is in 8 decimals

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _tokenAmount) / PRECISION; //for example : ((($1000 * 1e8)*(1e10)) * 1000) / 1e18
    }

    function getAccountInformation() external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(msg.sender);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
