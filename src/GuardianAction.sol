// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title GuardianAction
/// @notice Destination chain contract that receives Guardian callbacks.
/// Each trigger is recorded on chain and emitted as an event. A real
/// follow up action plugs in here: replace the recording with a DEX swap
/// or a vault call and the rest of the loop stays the same.
contract GuardianAction is AbstractCallback {
    struct Execution {
        uint256 ruleId;
        int256 price;
        uint256 executedAt;
    }

    event ActionExecuted(
        address indexed reactive,
        uint256 indexed ruleId,
        int256 price
    );

    Execution[] private _executions;
    mapping(uint256 => uint256) public executionCount;

    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {}

    /// @notice Called by the callback proxy when a Guardian rule fires.
    /// The proxy injects the reactive contract address as the first
    /// argument, and both guards check it before anything is recorded.
    function onGuardianTrigger(
        address reactive_,
        uint256 ruleId_,
        int256 price_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        _executions.push(
            Execution({
                ruleId: ruleId_,
                price: price_,
                executedAt: block.timestamp
            })
        );
        executionCount[ruleId_] += 1;
        emit ActionExecuted(reactive_, ruleId_, price_);
    }

    /// @notice Number of executions recorded so far.
    function totalExecutions() external view returns (uint256) {
        return _executions.length;
    }

    /// @notice One recorded execution by index.
    function executionAt(uint256 index_)
        external
        view
        returns (Execution memory)
    {
        return _executions[index_];
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
