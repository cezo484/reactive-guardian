// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title Guardian
/// @notice A reactive contract that watches price events and acts when a
/// user rule crosses its threshold. It lives on Reactive Network (Lasna
/// testnet or mainnet) and subscribes to price feeds on origin chains.
///
/// Two event sources are supported. A Chainlink aggregator emits
/// AnswerUpdated on every price update, with the price in topic 1.
/// A PriceBeacon emits PriceUpdated on demand, with the price in the log
/// data, so the full loop can be shown without waiting for the market.
///
/// A rule fires on the edge: the first observation past the threshold
/// triggers it, and it stays quiet while the price remains past the
/// threshold. A repeat rule re-arms when the price comes back inside the
/// range. A one-shot rule deactivates after its first trigger.
contract Guardian is AbstractReactive {
    /// @notice Chainlink AnswerUpdated(int256,uint256,uint256). The price
    /// is topic 1, an int256 with 8 decimals.
    uint256 public constant CHAINLINK_TOPIC0 =
        uint256(keccak256("AnswerUpdated(int256,uint256,uint256)"));

    /// @notice PriceBeacon PriceUpdated(address,uint256). The token is
    /// topic 1 and the price (8 decimals) is the log data.
    uint256 public constant BEACON_TOPIC0 =
        uint256(keccak256("PriceUpdated(address,uint256)"));

    /// @notice Gas limit requested for each callback delivery.
    uint64 public constant CALLBACK_GAS_LIMIT = 500_000;

    enum Direction {
        Below,
        Above
    }

    struct Rule {
        address owner;
        bytes32 feedKey;
        uint256 originChainId;
        address feed;
        uint256 topic0;
        address token;
        int256 threshold;
        Direction direction;
        bool oneShot;
        bool active;
        bool tripped;
        uint256 destChainId;
        address actionTarget;
        uint256 triggerCount;
        int256 lastPrice;
        uint256 lastTriggerAt;
    }

    event RuleCreated(
        uint256 indexed ruleId,
        address indexed owner,
        address indexed feed,
        int256 threshold,
        Direction direction,
        bool oneShot
    );
    event RuleRemoved(uint256 indexed ruleId, address indexed owner);
    event RuleTriggered(
        uint256 indexed ruleId,
        address indexed owner,
        int256 price,
        int256 threshold,
        uint256 triggerCount
    );

    error InvalidThreshold();
    error InvalidFeed();
    error UnsupportedTopic();
    error RuleNotFound();
    error NotRuleOwner();
    error RuleNotActive();

    uint256 public nextRuleId = 1;

    mapping(uint256 => Rule) private _rules;
    mapping(bytes32 => uint256[]) private _feedRules;
    mapping(uint256 => uint256) private _ruleIndex;

    constructor() payable {}

    /// @notice Registers a rule. Subscribes to the feed when this is the
    /// first active rule watching it.
    /// @param originChainId_ Chain where the price feed lives.
    /// @param feed_ Price feed contract (Chainlink aggregator or beacon).
    /// @param topic0_ CHAINLINK_TOPIC0 or BEACON_TOPIC0.
    /// @param token_ Token the beacon price refers to. Ignored for
    /// Chainlink feeds. Zero means any token on the beacon.
    /// @param threshold_ Price that trips the rule, 8 decimals.
    /// @param direction_ Below for a stop-loss, Above for a take-profit.
    /// @param oneShot_ True when the rule should fire once and stop.
    /// @param destChainId_ Chain that receives the callback. Ignored when
    /// actionTarget_ is zero.
    /// @param actionTarget_ Contract to call on the destination chain.
    /// Zero means alert only: the trigger is recorded, no callback.
    function createRule(
        uint256 originChainId_,
        address feed_,
        uint256 topic0_,
        address token_,
        int256 threshold_,
        Direction direction_,
        bool oneShot_,
        uint256 destChainId_,
        address actionTarget_
    ) external returns (uint256 ruleId) {
        if (threshold_ <= 0) revert InvalidThreshold();
        if (feed_ == address(0)) revert InvalidFeed();
        if (topic0_ != CHAINLINK_TOPIC0 && topic0_ != BEACON_TOPIC0) {
            revert UnsupportedTopic();
        }

        ruleId = nextRuleId++;
        bytes32 feedKey = _feedKey(originChainId_, feed_, topic0_);

        _rules[ruleId] = Rule({
            owner: msg.sender,
            feedKey: feedKey,
            originChainId: originChainId_,
            feed: feed_,
            topic0: topic0_,
            token: token_,
            threshold: threshold_,
            direction: direction_,
            oneShot: oneShot_,
            active: true,
            tripped: false,
            destChainId: destChainId_,
            actionTarget: actionTarget_,
            triggerCount: 0,
            lastPrice: 0,
            lastTriggerAt: 0
        });

        uint256[] storage ids = _feedRules[feedKey];
        if (ids.length == 0) {
            SYSTEM.subscribe(
                originChainId_,
                feed_,
                topic0_,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
        ids.push(ruleId);
        _ruleIndex[ruleId] = ids.length;

        emit RuleCreated(
            ruleId,
            msg.sender,
            feed_,
            threshold_,
            direction_,
            oneShot_
        );
    }

    /// @notice Removes a rule. Unsubscribes from the feed when no active
    /// rule watches it anymore.
    function removeRule(uint256 ruleId_) external {
        Rule storage rule = _rules[ruleId_];
        if (rule.owner == address(0)) revert RuleNotFound();
        if (rule.owner != msg.sender) revert NotRuleOwner();
        if (!rule.active) revert RuleNotActive();
        _deactivate(ruleId_, rule);
        emit RuleRemoved(ruleId_, msg.sender);
    }

    /// @notice Changes where a rule sends its callback. Used after the
    /// destination contract is deployed, since it needs this contract's
    /// address at construction.
    function setRuleTarget(
        uint256 ruleId_,
        uint256 destChainId_,
        address actionTarget_
    ) external {
        Rule storage rule = _rules[ruleId_];
        if (rule.owner == address(0)) revert RuleNotFound();
        if (rule.owner != msg.sender) revert NotRuleOwner();
        rule.destChainId = destChainId_;
        rule.actionTarget = actionTarget_;
    }

    /// @notice Returns a rule by id.
    function getRule(uint256 ruleId_) external view returns (Rule memory) {
        if (_rules[ruleId_].owner == address(0)) revert RuleNotFound();
        return _rules[ruleId_];
    }

    /// @notice Returns the active rule ids watching one feed.
    function rulesForFeed(
        uint256 originChainId_,
        address feed_,
        uint256 topic0_
    ) external view returns (uint256[] memory) {
        return _feedRules[_feedKey(originChainId_, feed_, topic0_)];
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external override onlySystem {
        int256 price;
        address token;
        if (log_.topic0 == CHAINLINK_TOPIC0) {
            if (log_.opCode != 3) return;
            price = int256(log_.topic1);
        } else if (log_.topic0 == BEACON_TOPIC0) {
            if (log_.opCode != 2) return;
            if (log_.data.length < 32) return;
            price = int256(abi.decode(log_.data, (uint256)));
            // casting to 'uint160' is safe because topic 1 holds an address
            // forge-lint: disable-next-line(unsafe-typecast)
            token = address(uint160(log_.topic1));
        } else {
            return;
        }

        bytes32 feedKey = _feedKey(
            log_.chainId,
            log_.contractAddress,
            log_.topic0
        );
        uint256[] memory ids = _feedRules[feedKey];
        for (uint256 i = 0; i < ids.length; i++) {
            _evaluate(ids[i], price, token);
        }
    }

    function _evaluate(
        uint256 ruleId_,
        int256 price_,
        address token_
    ) internal {
        Rule storage rule = _rules[ruleId_];
        if (!rule.active) return;
        if (
            rule.topic0 == BEACON_TOPIC0 &&
            rule.token != address(0) &&
            rule.token != token_
        ) {
            return;
        }

        bool past = rule.direction == Direction.Below
            ? price_ < rule.threshold
            : price_ > rule.threshold;
        rule.lastPrice = price_;

        if (!past) {
            rule.tripped = false;
            return;
        }
        if (rule.tripped) return;

        rule.tripped = true;
        rule.triggerCount += 1;
        rule.lastTriggerAt = block.timestamp;
        emit RuleTriggered(
            ruleId_,
            rule.owner,
            price_,
            rule.threshold,
            rule.triggerCount
        );

        if (rule.actionTarget != address(0)) {
            bytes memory payload = abi.encodeWithSignature(
                "onGuardianTrigger(address,uint256,int256)",
                address(0),
                ruleId_,
                price_
            );
            SYSTEM.requestCallbackV_1_0(
                ISystemContract.CallbackConfiguration_V_1_0({
                    chainId: rule.destChainId,
                    recipient: rule.actionTarget,
                    gasLimit: CALLBACK_GAS_LIMIT,
                    payload: payload
                })
            );
        }

        if (rule.oneShot) {
            _deactivate(ruleId_, rule);
        }
    }

    function _deactivate(uint256 ruleId_, Rule storage rule) internal {
        rule.active = false;
        bytes32 feedKey = rule.feedKey;
        uint256[] storage ids = _feedRules[feedKey];
        uint256 index = _ruleIndex[ruleId_] - 1;
        uint256 last = ids[ids.length - 1];
        ids[index] = last;
        _ruleIndex[last] = index + 1;
        ids.pop();
        delete _ruleIndex[ruleId_];
        if (ids.length == 0) {
            SYSTEM.unsubscribe(
                rule.originChainId,
                rule.feed,
                rule.topic0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function _feedKey(
        uint256 chainId_,
        address feed_,
        uint256 topic0_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainId_, feed_, topic0_));
    }
}
