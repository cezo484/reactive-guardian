// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { Guardian } from "../src/Guardian.sol";

/// @notice Deploys Guardian to Reactive Lasna and funds it so it can pay
/// for reactive transactions. Reads PRIVATE_KEY from the environment.
/// The key must hold lREACT on Lasna before this runs.
contract DeployGuardian is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        Guardian guardian = new Guardian{ value: 0.01 ether }();
        console.log("Guardian deployed at:", address(guardian));

        vm.stopBroadcast();
    }
}
