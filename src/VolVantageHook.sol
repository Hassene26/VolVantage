// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {
    IPoolManager,
    SwapParams,
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {
    Currency,
    CurrencyLibrary
} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import {FlashblockOracle} from "./FlashblockOracle.sol";
import {StressRewardToken} from "./StressRewardToken.sol";

/// @title VolVantageHook — Risk-Adjusted Dynamic Incentive Hook (RAD-IH)
/// @notice A Uniswap v4 Hook that monitors pool "stress" in real-time and:
///         1. Dynamically adjusts LP fees based on a composite Risk Score
///         2. Mints reward tokens to LPs who add liquidity during high stress
///         3. Applies a volatility tax to discourage LP flight during stress
///         Built for Unichain with Flashblock-aware sub-second risk updates.
contract VolVantageHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // ======================== ERRORS ========================

    error OnlyOwner();

    // ======================== EVENTS ========================

    event RiskScoreUpdated(
        PoolId indexed poolId,
        uint256 riskScore,
        uint24 dynamicFee
    );
    event StressRewardMinted(
        PoolId indexed poolId,
        address indexed lp,
        uint256 amount
    );
    event VolatilityTaxApplied(
        PoolId indexed poolId,
        address indexed lp,
        uint256 taxBps
    );
    event WeightsUpdated(uint256 w1, uint256 w2, uint256 w3);

    // ======================== CONSTANTS ========================

    /// @notice Base fee in hundredths of a bip (30 bps = 3000)
    uint24 public constant BASE_FEE = 3000;

    /// @notice TWAP lookback period (shorter on Unichain for Flashblock granularity)
    uint32 public constant TWAP_PERIOD = 300; // 5 minutes

    /// @notice Risk score thresholds (scaled by 1e18)
    uint256 public constant LOW_THRESHOLD = 0.2e18; // 20%
    uint256 public constant HIGH_THRESHOLD = 0.5e18; // 50%
    uint256 public constant MAX_RISK_SCORE = 1e18;

    /// @notice Base liquidity reference for the liquidity component
    uint128 public constant BASE_LIQUIDITY = 1000e18;

    /// @notice Reward tokens per unit of Risk Score
    uint256 public constant BASE_REWARD = 100e18;

    /// @notice Volatility tax rate (1% = 100 basis points out of 10000)
    uint256 public constant VOLATILITY_TAX_BPS = 100;
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ======================== STATE ========================

    address public owner;

    /// @notice Risk Score weights (must sum to 100)
    uint256 public w1 = 50; // Volatility weight
    uint256 public w2 = 30; // Liquidity weight
    uint256 public w3 = 20; // Imbalance weight

    /// @notice The stress reward token
    StressRewardToken public rewardToken;

    /// @notice Internal oracle state per pool (replaces v4's removed built-in oracle)
    mapping(PoolId => FlashblockOracle.OracleState) public oracleStates;

    /// @notice Last computed risk score per pool (for afterAddLiquidity to read)
    mapping(PoolId => uint256) public lastRiskScore;

    // ======================== CONSTRUCTOR ========================

    constructor(
        IPoolManager _poolManager,
        StressRewardToken _rewardToken
    ) BaseHook(_poolManager) {
        owner = msg.sender;
        rewardToken = _rewardToken;
    }

    // ======================== MODIFIERS ========================

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ======================== HOOK PERMISSIONS ========================

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // ======================== HOOK CALLBACKS ========================

    /// @notice beforeInitialize: Record the initial tick observation
    function _beforeInitialize(
        address,
        PoolKey calldata,
        uint160
    ) internal override returns (bytes4) {
        return BaseHook.beforeInitialize.selector;
    }

    /// @notice beforeSwap: Record observation, calculate Risk Score, return dynamic fee
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();

        // Get current tick and record observation in our internal oracle
        (, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        FlashblockOracle.record(oracleStates[poolId], currentTick);

        // Calculate the composite Risk Score
        uint256 riskScore = _calculateRiskScore(key, poolId, currentTick);
        lastRiskScore[poolId] = riskScore;

        // Determine dynamic fee based on risk score
        uint24 dynamicFee = _getDynamicFee(riskScore);

        emit RiskScoreUpdated(poolId, riskScore, dynamicFee);

        // Return the fee with the OVERRIDE flag set
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            dynamicFee | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    /// @notice afterAddLiquidity: Mint stress rewards if Risk Score is high
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        uint256 riskScore = lastRiskScore[poolId];

        // Only mint rewards if the pool is under stress
        if (riskScore >= HIGH_THRESHOLD) {
            // Scale reward by how stressed the pool is
            uint256 rewardAmount = (BASE_REWARD * riskScore) / MAX_RISK_SCORE;
            rewardToken.mint(sender, rewardAmount);

            emit StressRewardMinted(poolId, sender, rewardAmount);
        }

        return (
            BaseHook.afterAddLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    /// @notice beforeRemoveLiquidity: Emit volatility tax event during high-stress periods
    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        PoolId poolId = key.toId();
        uint256 riskScore = lastRiskScore[poolId];

        if (riskScore >= HIGH_THRESHOLD) {
            emit VolatilityTaxApplied(poolId, sender, VOLATILITY_TAX_BPS);
        }

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    // ======================== RISK ENGINE ========================

    /// @notice Calculate the composite Risk Score for a pool.
    ///         RS = w1 * Volatility + w2 * LiquidityDepth + w3 * Imbalance
    ///         All components are normalized to [0, 1e18] range.
    function _calculateRiskScore(
        PoolKey calldata key,
        PoolId poolId,
        int24 currentTick
    ) internal view returns (uint256 riskScore) {
        // 1. Volatility component: deviation of current tick from TWAP
        uint256 volatilityScore = _calculateVolatility(poolId, currentTick);

        // 2. Liquidity component: inverse depth (shallow pools = higher risk)
        uint256 liquidityScore = _calculateLiquidityRisk(poolId);

        // 3. Imbalance component: based on tick position relative to range
        uint256 imbalanceScore = _calculateImbalance(currentTick);

        // Weighted sum (weights sum to 100)
        riskScore =
            (w1 * volatilityScore + w2 * liquidityScore + w3 * imbalanceScore) /
            100;

        // Apply Flashblock burst amplification
        uint256 amplifier = FlashblockOracle.getBurstAmplifier(
            oracleStates[poolId]
        );
        riskScore =
            (riskScore * amplifier) /
            FlashblockOracle.BURST_MULTIPLIER_BASE;

        // Cap at MAX_RISK_SCORE
        if (riskScore > MAX_RISK_SCORE) {
            riskScore = MAX_RISK_SCORE;
        }
    }

    /// @notice Volatility: abs(currentTick - twapTick) / maxDeviation
    function _calculateVolatility(
        PoolId poolId,
        int24 currentTick
    ) internal view returns (uint256) {
        (int24 twapTick, bool valid) = FlashblockOracle.getTWAP(
            oracleStates[poolId],
            TWAP_PERIOD
        );

        if (!valid) {
            return 0; // Not enough observations yet
        }

        // Calculate absolute deviation
        int24 deviation = currentTick - twapTick;
        uint256 absDeviation = deviation >= 0
            ? uint256(int256(deviation))
            : uint256(int256(-deviation));

        // Normalize: 100 ticks deviation = max volatility score (1e18)
        // 100 ticks ≈ ~1% price move for most pools
        uint256 maxDeviation = 100;
        uint256 score = (absDeviation * 1e18) / maxDeviation;
        return score > 1e18 ? 1e18 : score;
    }

    /// @notice Liquidity Risk: inverse of current pool depth
    function _calculateLiquidityRisk(
        PoolId poolId
    ) internal view returns (uint256) {
        uint128 liquidity = poolManager.getLiquidity(poolId);

        if (liquidity == 0) return 1e18; // Max risk if no liquidity
        if (liquidity >= BASE_LIQUIDITY) return 0; // Deep pool = no risk

        // Linear scale: less liquidity = higher risk
        return
            ((uint256(BASE_LIQUIDITY) - uint256(liquidity)) * 1e18) /
            uint256(BASE_LIQUIDITY);
    }

    /// @notice Imbalance: uses tick position as a proxy for reserve imbalance.
    function _calculateImbalance(
        int24 currentTick
    ) internal pure returns (uint256) {
        uint256 absTick = currentTick >= 0
            ? uint256(int256(currentTick))
            : uint256(int256(-currentTick));

        // Normalize: 1000 ticks from center = max imbalance
        uint256 maxTick = 1000;
        uint256 score = (absTick * 1e18) / maxTick;
        return score > 1e18 ? 1e18 : score;
    }

    // ======================== FEE LOGIC ========================

    /// @notice Determine the dynamic fee based on the Risk Score
    function _getDynamicFee(uint256 riskScore) internal pure returns (uint24) {
        if (riskScore >= HIGH_THRESHOLD) {
            return BASE_FEE * 2; // 60 bps — protect LPs from toxic flow
        } else if (riskScore < LOW_THRESHOLD) {
            return BASE_FEE / 2; // 15 bps — attract volume in calm market
        } else {
            return BASE_FEE; // 30 bps — standard fee
        }
    }

    // ======================== ADMIN ========================

    /// @notice Update the Risk Score weights. Must sum to 100.
    function setWeights(
        uint256 _w1,
        uint256 _w2,
        uint256 _w3
    ) external onlyOwner {
        require(_w1 + _w2 + _w3 == 100, "Weights must sum to 100");
        w1 = _w1;
        w2 = _w2;
        w3 = _w3;
        emit WeightsUpdated(_w1, _w2, _w3);
    }

    // ======================== VIEW FUNCTIONS ========================

    /// @notice Get the current risk score for a pool (view function for frontend)
    function getRiskScore(
        PoolKey calldata key
    ) external view returns (uint256) {
        PoolId poolId = key.toId();
        (, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        return _calculateRiskScore(key, poolId, currentTick);
    }

    /// @notice Get the dynamic fee that would be charged for the current risk level
    function getCurrentFee(
        PoolKey calldata key
    ) external view returns (uint24) {
        PoolId poolId = key.toId();
        (, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        return _getDynamicFee(_calculateRiskScore(key, poolId, currentTick));
    }
}
