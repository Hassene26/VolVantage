// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title FlashblockOracle
/// @notice Internal oracle for tracking tick observations since Uniswap v4
///         removed the built-in oracle. Designed for Unichain's 200ms Flashblocks
///         to provide high-resolution TWAP data.
library FlashblockOracle {
    /// @notice Maximum number of observations stored in the circular buffer
    uint16 constant MAX_OBSERVATIONS = 64;

    /// @notice Burst detection parameters
    uint256 internal constant BURST_WINDOW = 10; // seconds to look back for burst detection
    uint256 internal constant NORMAL_BLOCKS_PER_WINDOW = 10; // ~1 block/sec on Unichain
    uint256 internal constant BURST_MULTIPLIER_BASE = 100; // 100 = 1x (no amplification)
    uint256 internal constant BURST_MULTIPLIER_MAX = 200; // 200 = 2x max amplification

    /// @notice A single tick observation recorded at a point in time
    struct Observation {
        uint32 timestamp;
        int24 tick;
    }

    /// @notice State for a pool's oracle observations
    struct OracleState {
        Observation[64] observations; // circular buffer (MAX_OBSERVATIONS)
        uint16 index; // current write index
        uint16 cardinality; // number of populated observations
        uint128 blockCount; // burst detection: blocks in current window
        uint128 lastWindowStart; // burst detection: timestamp of window start
    }

    /// @notice Record a new tick observation.
    /// @param state The oracle state to update
    /// @param tick The current tick of the pool
    function record(OracleState storage state, int24 tick) internal {
        uint32 currentTime = uint32(block.timestamp);

        // Only write a new observation if timestamp changed (avoid duplicates in same block)
        if (
            state.cardinality > 0 &&
            state.observations[state.index].timestamp == currentTime
        ) {
            // Update the tick for current timestamp (latest value in same block wins)
            state.observations[state.index].tick = tick;
        } else {
            // Advance the circular buffer
            uint16 newIndex = (state.index + 1) % MAX_OBSERVATIONS;
            state.observations[newIndex] = Observation({
                timestamp: currentTime,
                tick: tick
            });
            state.index = newIndex;

            if (state.cardinality < MAX_OBSERVATIONS) {
                state.cardinality++;
            }
        }

        // Burst detection: track block frequency
        if (currentTime - uint32(state.lastWindowStart) < BURST_WINDOW) {
            state.blockCount++;
        } else {
            state.lastWindowStart = uint128(currentTime);
            state.blockCount = 1;
        }
    }

    /// @notice Calculate the TWAP tick over a lookback period.
    /// @param state The oracle state
    /// @param twapPeriod The lookback period in seconds
    /// @return twapTick The time-weighted average tick
    /// @return valid Whether we had enough observations for a valid TWAP
    function getTWAP(
        OracleState storage state,
        uint32 twapPeriod
    ) internal view returns (int24 twapTick, bool valid) {
        if (state.cardinality < 2) {
            return (0, false);
        }

        uint32 currentTime = uint32(block.timestamp);
        uint32 targetTime = currentTime - twapPeriod;

        // Walk backwards through observations to find the TWAP
        int56 tickCumulative = 0;
        uint32 totalTime = 0;

        uint16 idx = state.index;
        int24 prevTick = state.observations[idx].tick;
        uint32 prevTimestamp = state.observations[idx].timestamp;

        for (uint16 i = 1; i < state.cardinality; i++) {
            uint16 prevIdx = idx == 0 ? state.cardinality - 1 : idx - 1;
            Observation memory obs = state.observations[prevIdx];

            // If this observation is before our target window, stop
            if (obs.timestamp < targetTime) {
                // Interpolate: count time from targetTime to prevTimestamp
                uint32 dtPartial = prevTimestamp - targetTime;
                tickCumulative += int56(prevTick) * int56(int32(dtPartial));
                totalTime += dtPartial;
                break;
            }

            // Accumulate tick * time
            uint32 dt = prevTimestamp - obs.timestamp;
            if (dt > 0) {
                tickCumulative += int56(prevTick) * int56(int32(dt));
                totalTime += dt;
            }

            prevTick = obs.tick;
            prevTimestamp = obs.timestamp;
            idx = prevIdx;
        }

        if (totalTime == 0) {
            return (0, false);
        }

        twapTick = int24(tickCumulative / int56(int32(totalTime)));
        valid = true;
    }

    /// @notice Calculate burst amplification factor.
    ///         If blocks arrive faster than normal (Flashblock activity),
    ///         the risk score is amplified.
    /// @param state The current oracle state
    /// @return amplifier The amplification factor (100 = 1x, 200 = 2x max)
    function getBurstAmplifier(
        OracleState storage state
    ) internal view returns (uint256 amplifier) {
        if (state.blockCount <= NORMAL_BLOCKS_PER_WINDOW) {
            return BURST_MULTIPLIER_BASE; // No amplification
        }

        // Linear scale from 1x to 2x based on excess blocks
        uint256 excess = state.blockCount - NORMAL_BLOCKS_PER_WINDOW;
        amplifier =
            BURST_MULTIPLIER_BASE +
            (excess * BURST_MULTIPLIER_BASE) /
            NORMAL_BLOCKS_PER_WINDOW;

        if (amplifier > BURST_MULTIPLIER_MAX) {
            amplifier = BURST_MULTIPLIER_MAX;
        }
    }
}
