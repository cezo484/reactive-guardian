// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { GuardianAction } from "../src/GuardianAction.sol";
import { PriceBeacon } from "../src/PriceBeacon.sol";

/// @notice Deploys the Sepolia side: the PriceBeacon demo publisher and
/// the GuardianAction callback receiver. Reads PRIVATE_KEY and
/// GUARDIAN_ADDRESS from the environment. Deploy Guardian to Lasna first,
/// then pass its address here.
contract DeploySepolia is Script {
    IPayable internal constant SEPOLIA_PROXY =
        IPayable(payable(0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");

        vm.startBroadcast(deployerKey);

        PriceBeacon beacon = new PriceBeacon();
        console.log("PriceBeacon deployed at:", address(beacon));

        GuardianAction action = new GuardianAction{ value: 0.01 ether }(
            SEPOLIA_PROXY,
            guardian
        );
        console.log("GuardianAction deployed at:", address(action));

        vm.stopBroadcast();
    }
}
