// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { Guardian } from "../src/Guardian.sol";

/// @notice Stand-in for the Reactive system contract. The test etches its
/// code at the real system address so Guardian talks to it like it would
/// on Lasna, and every subscribe and callback request is recorded.
contract MockSystem {
    struct Subscription {
        uint256 chainId;
        address feed;
        uint256 topic0;
    }

    struct CallbackRequest {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    Subscription[] public subscriptions;
    CallbackRequest[] public callbackRequests;
    uint256 public unsubscribeCalls;

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256,
        uint256,
        uint256
    ) external {
        subscriptions.push(
            Subscription({
                chainId: chainId_,
                feed: contract_,
                topic0: topic0_
            })
        );
    }

    function unsubscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external {
        unsubscribeCalls += 1;
    }

    function requestCallback(
        ISystemContract.CallbackVersion,
        bytes memory
    ) external {}

    function requestCallbackV_1_0(
        ISystemContract.CallbackConfiguration_V_1_0 memory config_
    ) external {
        callbackRequests.push(
            CallbackRequest({
                chainId: config_.chainId,
                recipient: config_.recipient,
                gasLimit: config_.gasLimit,
                payload: config_.payload
            })
        );
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}

    function subscriptionCount() external view returns (uint256) {
        return subscriptions.length;
    }

    function callbackCount() external view returns (uint256) {
        return callbackRequests.length;
    }

    function callbackPayload(uint256 index_)
        external
        view
        returns (bytes memory)
    {
        return callbackRequests[index_].payload;
    }
}

contract GuardianTest is Test {
    address internal constant SYSTEM_ADDR =
        0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11155111;
    address internal constant FEED =
        0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address internal constant BEACON =
        0x00000000000000000000000000000000bEAC0001;
    address internal constant TOKEN =
        0x000000000000000000000000000000000000E771;
    address internal constant ACTION =
        0x00000000000000000000000000000000000AC710;

    int256 internal constant PRICE_3600 = 3600_00000000;
    int256 internal constant PRICE_3500 = 3500_00000000;
    int256 internal constant PRICE_3490 = 3490_00000000;
    int256 internal constant PRICE_3000 = 3000_00000000;
    int256 internal constant PRICE_2900 = 2900_00000000;

    Guardian internal guardian;
    MockSystem internal system;

    event RuleTriggered(
        uint256 indexed ruleId,
        address indexed owner,
        int256 price,
        int256 threshold,
        uint256 triggerCount
    );

    function setUp() public {
        MockSystem mock = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        system = MockSystem(payable(SYSTEM_ADDR));

        vm.deal(address(this), 10 ether);
        guardian = new Guardian{ value: 1 ether }();
    }

    function _createBelowRule(
        int256 threshold_,
        bool oneShot_
    ) internal returns (uint256) {
        return
            guardian.createRule(
                SEPOLIA,
                FEED,
                guardian.CHAINLINK_TOPIC0(),
                address(0),
                threshold_,
                Guardian.Direction.Below,
                oneShot_,
                SEPOLIA,
                ACTION
            );
    }

    function _chainlinkLog(
        int256 price_
    ) internal view returns (IReactive.LogRecord memory) {
        return
            IReactive.LogRecord({
                chainId: SEPOLIA,
                contractAddress: FEED,
                topic0: guardian.CHAINLINK_TOPIC0(),
                topic1: uint256(price_),
                topic2: 1,
                topic3: 0,
                data: "",
                blockNumber: 1,
                opCode: 3,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            });
    }

    function _beaconLog(
        address token_,
        uint256 price_
    ) internal view returns (IReactive.LogRecord memory) {
        return
            IReactive.LogRecord({
                chainId: SEPOLIA,
                contractAddress: BEACON,
                topic0: guardian.BEACON_TOPIC0(),
                topic1: uint256(uint160(token_)),
                topic2: 0,
                topic3: 0,
                data: abi.encode(price_),
                blockNumber: 1,
                opCode: 2,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            });
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM_ADDR);
        guardian.react(log_);
    }

    function testCreateRuleStoresRuleAndSubscribes() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);

        assertEq(ruleId, 1);
        Guardian.Rule memory rule = guardian.getRule(ruleId);
        assertEq(rule.owner, address(this));
        assertEq(rule.feed, FEED);
        assertEq(rule.threshold, PRICE_3500);
        assertTrue(rule.active);
        assertEq(rule.triggerCount, 0);
        assertEq(system.subscriptionCount(), 1);

        (uint256 chainId, address feed, uint256 topic0) = system
            .subscriptions(0);
        assertEq(chainId, SEPOLIA);
        assertEq(feed, FEED);
        assertEq(topic0, guardian.CHAINLINK_TOPIC0());
    }

    function testSecondRuleOnSameFeedDoesNotResubscribe() public {
        _createBelowRule(PRICE_3500, false);
        _createBelowRule(PRICE_3000, false);
        assertEq(system.subscriptionCount(), 1);
        assertEq(guardian.rulesForFeed(SEPOLIA, FEED, guardian.CHAINLINK_TOPIC0()).length, 2);
    }

    function testCreateRuleValidation() public {
        uint256 chainlinkTopic = guardian.CHAINLINK_TOPIC0();
        vm.expectRevert(Guardian.InvalidThreshold.selector);
        guardian.createRule(
            SEPOLIA,
            FEED,
            chainlinkTopic,
            address(0),
            0,
            Guardian.Direction.Below,
            false,
            SEPOLIA,
            ACTION
        );

        vm.expectRevert(Guardian.InvalidFeed.selector);
        guardian.createRule(
            SEPOLIA,
            address(0),
            chainlinkTopic,
            address(0),
            PRICE_3500,
            Guardian.Direction.Below,
            false,
            SEPOLIA,
            ACTION
        );

        vm.expectRevert(Guardian.UnsupportedTopic.selector);
        guardian.createRule(
            SEPOLIA,
            FEED,
            uint256(keccak256("Nope(uint256)")),
            address(0),
            PRICE_3500,
            Guardian.Direction.Below,
            false,
            SEPOLIA,
            ACTION
        );
    }

    function testBelowThresholdTriggersAndRequestsCallback() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);

        vm.expectEmit(true, true, false, true, address(guardian));
        emit RuleTriggered(ruleId, address(this), PRICE_3490, PRICE_3500, 1);
        _react(_chainlinkLog(PRICE_3490));

        Guardian.Rule memory rule = guardian.getRule(ruleId);
        assertEq(rule.triggerCount, 1);
        assertEq(rule.lastPrice, PRICE_3490);
        assertTrue(rule.tripped);
        assertTrue(rule.active);

        assertEq(system.callbackCount(), 1);
        (uint256 chainId, address recipient, uint64 gasLimit, ) = system
            .callbackRequests(0);
        assertEq(chainId, SEPOLIA);
        assertEq(recipient, ACTION);
        assertEq(gasLimit, guardian.CALLBACK_GAS_LIMIT());
        assertEq(
            system.callbackPayload(0),
            abi.encodeWithSignature(
                "onGuardianTrigger(address,uint256,int256)",
                address(0),
                ruleId,
                PRICE_3490
            )
        );
    }

    function testNoTriggerInsideRange() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);

        _react(_chainlinkLog(PRICE_3600));
        _react(_chainlinkLog(PRICE_3500));

        Guardian.Rule memory rule = guardian.getRule(ruleId);
        assertEq(rule.triggerCount, 0);
        assertEq(system.callbackCount(), 0);
    }

    function testRepeatRuleRearmsAfterPriceReturns() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);

        _react(_chainlinkLog(PRICE_3490));
        _react(_chainlinkLog(PRICE_3490));
        _react(_chainlinkLog(PRICE_3000));
        assertEq(guardian.getRule(ruleId).triggerCount, 1);

        _react(_chainlinkLog(PRICE_3600));
        assertFalse(guardian.getRule(ruleId).tripped);

        _react(_chainlinkLog(PRICE_3490));
        assertEq(guardian.getRule(ruleId).triggerCount, 2);
        assertEq(system.callbackCount(), 2);
    }

    function testOneShotRuleFiresOnceThenDeactivates() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, true);

        _react(_chainlinkLog(PRICE_3490));
        Guardian.Rule memory rule = guardian.getRule(ruleId);
        assertEq(rule.triggerCount, 1);
        assertFalse(rule.active);
        assertEq(system.unsubscribeCalls(), 1);

        _react(_chainlinkLog(PRICE_3600));
        _react(_chainlinkLog(PRICE_3490));
        assertEq(guardian.getRule(ruleId).triggerCount, 1);
        assertEq(system.callbackCount(), 1);
    }

    function testAboveDirectionTriggersOnRise() public {
        uint256 ruleId = guardian.createRule(
            SEPOLIA,
            FEED,
            guardian.CHAINLINK_TOPIC0(),
            address(0),
            PRICE_3500,
            Guardian.Direction.Above,
            false,
            SEPOLIA,
            ACTION
        );

        _react(_chainlinkLog(PRICE_3490));
        assertEq(guardian.getRule(ruleId).triggerCount, 0);

        _react(_chainlinkLog(PRICE_3600));
        assertEq(guardian.getRule(ruleId).triggerCount, 1);
    }

    function testBeaconEventDecodingAndTokenMatch() public {
        uint256 ruleId = guardian.createRule(
            SEPOLIA,
            BEACON,
            guardian.BEACON_TOPIC0(),
            TOKEN,
            PRICE_3500,
            Guardian.Direction.Below,
            false,
            SEPOLIA,
            ACTION
        );

        address otherToken = address(0x1234);
        _react(_beaconLog(otherToken, uint256(PRICE_3490)));
        assertEq(guardian.getRule(ruleId).triggerCount, 0);

        _react(_beaconLog(TOKEN, uint256(PRICE_3490)));
        assertEq(guardian.getRule(ruleId).triggerCount, 1);
        assertEq(guardian.getRule(ruleId).lastPrice, PRICE_3490);
    }

    function testRemoveRuleStopsItAndUnsubscribes() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);

        guardian.removeRule(ruleId);
        assertFalse(guardian.getRule(ruleId).active);
        assertEq(system.unsubscribeCalls(), 1);

        _react(_chainlinkLog(PRICE_3490));
        assertEq(guardian.getRule(ruleId).triggerCount, 0);
        assertEq(system.callbackCount(), 0);
    }

    function testRemoveRuleOnlyOwner() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);

        address stranger = address(0xBEEF);
        vm.prank(stranger);
        vm.expectRevert(Guardian.NotRuleOwner.selector);
        guardian.removeRule(ruleId);

        vm.expectRevert(Guardian.RuleNotFound.selector);
        guardian.removeRule(999);
    }

    function testReactOnlySystem() public {
        _createBelowRule(PRICE_3500, false);
        IReactive.LogRecord memory log_ = _chainlinkLog(PRICE_3490);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractPayer.NotAuthorized.selector,
                address(this),
                SYSTEM_ADDR
            )
        );
        guardian.react(log_);
    }

    function testUnknownTopicIsIgnored() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);

        IReactive.LogRecord memory log_ = _chainlinkLog(PRICE_3490);
        log_.topic0 = uint256(keccak256("SomethingElse(uint256)"));
        _react(log_);

        assertEq(guardian.getRule(ruleId).triggerCount, 0);
        assertEq(system.callbackCount(), 0);
    }

    function testAlertOnlyRuleSkipsCallback() public {
        uint256 ruleId = guardian.createRule(
            SEPOLIA,
            FEED,
            guardian.CHAINLINK_TOPIC0(),
            address(0),
            PRICE_3500,
            Guardian.Direction.Below,
            false,
            0,
            address(0)
        );

        _react(_chainlinkLog(PRICE_3490));
        assertEq(guardian.getRule(ruleId).triggerCount, 1);
        assertEq(system.callbackCount(), 0);
    }

    function testMultipleRulesOnSameFeed() public {
        uint256 stopLoss = _createBelowRule(PRICE_3500, false);
        uint256 deepStop = _createBelowRule(PRICE_3000, false);

        _react(_chainlinkLog(PRICE_3490));
        assertEq(guardian.getRule(stopLoss).triggerCount, 1);
        assertEq(guardian.getRule(deepStop).triggerCount, 0);

        _react(_chainlinkLog(PRICE_2900));
        assertEq(guardian.getRule(stopLoss).triggerCount, 1);
        assertEq(guardian.getRule(deepStop).triggerCount, 1);
    }

    function testSetRuleTargetChangesCallbackRecipient() public {
        uint256 ruleId = _createBelowRule(PRICE_3500, false);
        address newAction = address(0xCA11);
        guardian.setRuleTarget(ruleId, SEPOLIA, newAction);

        _react(_chainlinkLog(PRICE_3490));
        (, address recipient, , ) = system.callbackRequests(0);
        assertEq(recipient, newAction);
    }

    function testCoverDebtWithZeroDebt() public {
        guardian.coverDebt();
        assertEq(address(guardian).balance, 1 ether);
    }
}
