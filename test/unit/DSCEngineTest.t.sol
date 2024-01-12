// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC delpoyer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 1e18;
    uint256 public constant STARTING_ERC20_BALANCE = 100e18;
    uint256 amountToMint = 1 ether;

    function setUp() public {
        delpoyer = new DeployDSC();
        (dsc, engine, helperConfig) = delpoyer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ////////////////////////
    ///// CONSTRUCTOR /////
    ///////////////////////
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testIfTokenLengthDoesntMathPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine_TokenAndPriceFeedLengthMismatch.selector, tokenAddresses, priceFeedAddresses
            )
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////
    ///// PRICE TEST/////
    /////////////////////

    function testGetUsdPrice() public {
        uint256 wethAmount = 15e18;
        // 15weth * 2000usd/weth = 30000usd
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, wethAmount);
        console.logUint(actualUsd); // should log 30000000000000000000000 = 30000e18
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 30000e18;
        // 15weth * 2000usd/weth = 30000usd
        uint256 expectedWethAmount = 15e18;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        console.logUint(actualWeth);
        assertEq(actualWeth, expectedWethAmount);
    }

    ///////////////////////////////////
    ///// DEPOSIT COLLATERAL TEST /////
    ///////////////////////////////////
    function testIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        engine.depositCollateral(address(weth), 0);
        console.log(ERC20Mock(weth).balanceOf(address(USER)));
        vm.stopPrank();
    }

    function testRevertsOnUnapprovedDepositCollateral() public {
        ERC20Mock newCollateral = new ERC20Mock();
        // depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_NotAllowedToken.selector, address(newCollateral)));
        engine.depositCollateral(address(newCollateral), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier withdrewCollateral() {
        vm.startPrank(USER);
        assert(ERC20Mock(weth).balanceOf(address(USER)) >= AMOUNT_COLLATERAL);
        engine.redeemCollateral(address(weth), (AMOUNT_COLLATERAL / 1e18) * 2e17);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, (AMOUNT_COLLATERAL / 1e18) * 2e17);
        vm.stopPrank();
        _;
    }

    modifier mintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.mintDSC((AMOUNT_COLLATERAL / 1e18) * 5e17);
        vm.stopPrank();
        _;
    }

    function testShouldEmitEventOnDepositCollateralAndGetAccountInformation() public depositedCollateral {
        vm.startPrank(USER);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation();
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDsc() public depositCollateralAndMintDSC {
        vm.startPrank(USER);
        (uint256 totalDscMinted,) = engine.getAccountInformation();
        uint256 expectedTotalDscMinted = (AMOUNT_COLLATERAL / 1e18) * 2e17;
        assertEq(totalDscMinted, expectedTotalDscMinted);
        vm.stopPrank();
    }

    function testRevertsOnUnapprovedWithdrawCollateral() public {
        ERC20Mock newCollateral = new ERC20Mock();
        // depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_NotAllowedToken.selector, address(newCollateral)));
        engine.redeemCollateral(address(newCollateral), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testWithdrawCollateral() public depositCollateralAndMintDSC {
        vm.startPrank(USER);

        engine.redeemCollateral(address(weth), (AMOUNT_COLLATERAL / 1e18) * 2e17);
        vm.stopPrank();
    }
    // TODO: fix this test

    // function testRedeemCollateralForDSC() public depositCollateralAndMintDSC {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    //     engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, (AMOUNT_COLLATERAL / 1e18) * 2e17);
    //     dsc.approve(address(engine), amountToMint);
    //     engine.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, amountToMint);
    //     vm.stopPrank();
    // }

    /*
    TESTS TO DO:
    - test if collateral is deposited
    - test if collateral is withdrawn
    - test if collateral is withdrawn and dsc is burned
    - test if collateral is withdrawn and dsc is burned and collateral is withdrawn
    
     */
}
