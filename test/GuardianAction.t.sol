// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { GuardianAction } from "../src/GuardianAction.sol";

/// @notice Stand-in for a destination chain callback proxy.
contract MockProxy {
    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}

contract GuardianActionTest is Test {
    address internal constant GUARDIAN =
        0x00000000000000000000000000000000B0A9D1A1;

    GuardianAction internal action;
    MockProxy internal proxy;

    event ActionExecuted(
        address indexed reactive,
        uint256 indexed ruleId,
        int256 price
    );

    function setUp() public {
        proxy = new MockProxy();
        vm.deal(address(this), 10 ether);
        action = new GuardianAction{ value: 1 ether }(
            IPayable(payable(address(proxy))),
            GUARDIAN
        );
    }

    function testCallbackRecordsExecution() public {
        vm.expectEmit(true, true, false, true, address(action));
        emit ActionExecuted(GUARDIAN, 7, 3490_00000000);

        vm.prank(address(proxy));
        action.onGuardianTrigger(GUARDIAN, 7, 3490_00000000);

        assertEq(action.totalExecutions(), 1);
        assertEq(action.executionCount(7), 1);
        GuardianAction.Execution memory run = action.executionAt(0);
        assertEq(run.ruleId, 7);
        assertEq(run.price, 3490_00000000);
    }

    function testCallbackRejectsNonProxyCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractPayer.NotAuthorized.selector,
                address(this),
                address(proxy)
            )
        );
        action.onGuardianTrigger(GUARDIAN, 7, 3490_00000000);
    }

    function testCallbackRejectsWrongSender() public {
        vm.prank(address(proxy));
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractCallback.CallbackNotAuthorized.selector,
                address(0x000000000000000000000000000000000000dEaD),
                GUARDIAN
            )
        );
        action.onGuardianTrigger(
            address(0x000000000000000000000000000000000000dEaD),
            7,
            3490_00000000
        );
    }

    function testCoverDebtWithZeroDebt() public {
        action.coverDebt();
        assertEq(address(action).balance, 1 ether);
    }
}
