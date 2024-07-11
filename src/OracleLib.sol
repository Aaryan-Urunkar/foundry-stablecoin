// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Aaryan Urunkar
 * @notice This library is used to check the chainlink data feed for stale data
 * If a price is stale, the function will revert and render the DSC engine unusable
 * This is because we want the DSCEngine to freeze is prices become stale
 */
library OracleLib {
    error OracleLibStalePrice();

    uint256 private constant HEARTBEAT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > HEARTBEAT) {
            revert OracleLibStalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
