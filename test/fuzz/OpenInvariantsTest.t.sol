// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;

// // System Invariants
// //  - Total supply of DSC is always less than the total amount of collateral locked in the system
// // - Getter shouldnt revert

// import {Test} from "forge-std/Test.sol";
// import "forge-std/console.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC delpoyer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() public {
//         delpoyer = new DeployDSC();
//         (dsc, dsce, config) = delpoyer.run();

//         (,, weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(dsce));
//         uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

//         uint256 wethValue = dsce.getUsdValue(weth, wethDeposted);
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcDeposited);

//         // console.log("wethValue: %s", wethValue);
//         // console.log("wbtcValue: %s", wbtcValue);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
