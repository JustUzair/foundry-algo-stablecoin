// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// import {bound} from "forge-std/StdUtils.sol";

contract Handler is Test {
    DeployDSC delpoyer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint96 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintDSCCalled;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc, ERC20Mock _weth, ERC20Mock _wbtc) {
        dsce = _dscEngine;
        dsc = _dsc;
        weth = _weth;
        wbtc = _wbtc;
    }
    // redeem Collateral

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // vm.startPrank(msg.sender);
        ERC20Mock collateral = _getCollateralSeed(collateralSeed);

        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
        // vm.stopPrank();
    }

    function mintDsc(uint256 amount) public {
        vm.startPrank(msg.sender);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation();
        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;
        // ERC20Mock(weth).approve(address(dsce), MAX_DEPOSIT_SIZE);
        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        dsce.mintDSC(amount);
        vm.stopPrank();
        timesMintDSCCalled++;
    }
    // Helper function

    function _getCollateralSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return ERC20Mock(weth);
        }
        return ERC20Mock(wbtc);
    }
}
