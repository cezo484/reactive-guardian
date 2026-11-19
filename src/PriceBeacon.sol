// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

/// @title PriceBeacon
/// @notice Demo price publisher for Sepolia. Anyone can publish a price,
/// which emits the event Guardian subscribes to. It exists so the full
/// loop can be shown on demand: publish a price past a threshold and
/// watch Guardian fire. It is a demo aid, not a price oracle.
contract PriceBeacon {
    event PriceUpdated(address indexed token, uint256 price);

    mapping(address => uint256) public latestPrice;

    /// @notice Publishes a price for a token. The price uses 8 decimals,
    /// the same scale Chainlink feeds use.
    function publish(address token_, uint256 price_) external {
        latestPrice[token_] = price_;
        emit PriceUpdated(token_, price_);
    }
}
