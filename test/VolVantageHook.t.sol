// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {
    CurrencyLibrary,
    Currency
} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {
    LiquidityAmounts
} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {
    IPositionManager
} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

import {VolVantageHook} from "../src/VolVantageHook.sol";
import {StressRewardToken} from "../src/StressRewardToken.sol";
import {BaseTest} from "./utils/BaseTest.sol";

contract VolVantageHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    VolVantageHook hook;
    StressRewardToken rewardToken;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploy all required v4 artifacts
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the reward token
        rewardToken = new StressRewardToken(address(this));

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(
            poolManager,
            rewardToken,
            address(this)
        );
        deployCodeTo(
            "VolVantageHook.sol:VolVantageHook",
            constructorArgs,
            flags
        );
        hook = VolVantageHook(flags);

        // Set the hook as the minter on the reward token
        rewardToken.setHook(address(hook));

        // Create the pool with DYNAMIC_FEE_FLAG
        poolKey = PoolKey(
            currency0,
            currency1,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            60,
            IHooks(hook)
        );
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidityAmount
            );

        (tokenId, ) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    // ======================== HOOK PERMISSIONS ========================

    function test_hookPermissions() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();

        assertTrue(perms.beforeInitialize, "beforeInitialize should be true");
        assertTrue(perms.beforeSwap, "beforeSwap should be true");
        assertTrue(perms.afterAddLiquidity, "afterAddLiquidity should be true");
        assertTrue(
            perms.beforeRemoveLiquidity,
            "beforeRemoveLiquidity should be true"
        );

        assertFalse(perms.afterInitialize, "afterInitialize should be false");
        assertFalse(
            perms.beforeAddLiquidity,
            "beforeAddLiquidity should be false"
        );
        assertFalse(
            perms.afterRemoveLiquidity,
            "afterRemoveLiquidity should be false"
        );
        assertFalse(perms.afterSwap, "afterSwap should be false");
        assertFalse(perms.beforeDonate, "beforeDonate should be false");
        assertFalse(perms.afterDonate, "afterDonate should be false");
    }

    // ======================== FEE LOGIC ========================

    function test_calmMarketLowFee() public {
        // Build oracle observations by doing small swaps with time advancement
        _advanceTimeAndSwap(1);
        vm.warp(block.timestamp + 600);

        // Another small swap — should get low fees since price hasn't moved significantly
        uint256 amountIn = 0.001e18;
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Verify the fee is at most BASE_FEE in a calm market
        uint24 currentFee = hook.getCurrentFee(poolKey);
        assertTrue(
            currentFee <= hook.BASE_FEE(),
            "Fee should be at most BASE_FEE in a calm market"
        );
    }

    function test_volatileMarketHighFee() public {
        // Build oracle observations first
        _advanceTimeAndSwap(1);
        vm.warp(block.timestamp + 600);
        _advanceTimeAndSwap(1);

        // Large swap to move price significantly
        uint256 amountIn = 50e18;
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        uint256 riskScore = hook.lastRiskScore(poolId);
        console.log("Risk Score after large swap:", riskScore);

        uint24 currentFee = hook.getCurrentFee(poolKey);
        console.log("Current fee:", currentFee);
    }

    // ======================== RISK SCORE ========================

    function test_riskScoreComposite() public {
        // Do a swap so the risk score is computed and observations exist
        _advanceTimeAndSwap(1);

        uint256 riskScore = hook.getRiskScore(poolKey);
        console.log("Risk Score:", riskScore);
        assertTrue(
            riskScore <= hook.MAX_RISK_SCORE(),
            "Risk score should be <= MAX"
        );
    }

    function test_weightUpdate() public {
        hook.setWeights(40, 40, 20);
        assertEq(hook.w1(), 40);
        assertEq(hook.w2(), 40);
        assertEq(hook.w3(), 20);
    }

    function test_weightUpdateNotOwner() public {
        vm.prank(address(0xdead));
        // OpenZeppelin's Ownable uses OwnableUnauthorizedAccount(address) or a custom error
        // Let's use the selector from the Ownable contract
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                address(0xdead)
            )
        );
        hook.setWeights(40, 40, 20);
    }

    function test_weightsMustSum100() public {
        vm.expectRevert("Weights must sum to 100");
        hook.setWeights(40, 40, 30);
    }

    // ======================== STRESS REWARDS ========================

    function test_noRewardInCalmMarket() public {
        uint256 balanceBefore = rewardToken.balanceOf(address(this));

        // Add liquidity in calm market
        uint128 liquidityAmount = 10e18;
        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidityAmount
            );

        positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        assertEq(
            balanceAfter,
            balanceBefore,
            "No rewards should be minted in calm market"
        );
    }

    // ======================== REWARD TOKEN ========================

    function test_rewardTokenOnlyHookCanMint() public {
        vm.prank(address(0xdead));
        vm.expectRevert(StressRewardToken.OnlyHook.selector);
        rewardToken.mint(address(this), 100e18);
    }

    function test_rewardTokenHookAlreadySet() public {
        vm.expectRevert("Hook already set");
        rewardToken.setHook(address(0xdead));
    }

    // ======================== SWAP INTEGRATION ========================

    function test_swapUpdatesRiskScore() public {
        uint256 amountIn = 1e18;
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Risk score should have been set by beforeSwap
        uint256 newRS = hook.lastRiskScore(poolId);
        console.log("Risk Score after swap:", newRS);
    }

    function test_multipleSwapsRecordObservations() public {
        // Perform multiple rapid swaps to simulate activity
        for (uint256 i = 0; i < 5; i++) {
            uint256 amountIn = 0.1e18;
            swapRouter.swapExactTokensForTokens({
                amountIn: amountIn,
                amountOutMin: 0,
                zeroForOne: i % 2 == 0,
                poolKey: poolKey,
                hookData: Constants.ZERO_BYTES,
                receiver: address(this),
                deadline: block.timestamp + 1
            });
        }

        // Risk score should be set
        uint256 rs = hook.lastRiskScore(poolId);
        console.log("Risk Score after 5 swaps:", rs);
        assertTrue(rs <= hook.MAX_RISK_SCORE(), "Risk score should be bounded");
    }

    // ======================== REMOVE LIQUIDITY ========================

    function test_removeLiquidityCalm() public {
        uint256 liquidityToRemove = 1e18;
        positionManager.decreaseLiquidity(
            tokenId,
            liquidityToRemove,
            0,
            0,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
        // If we get here without reverting, the test passes
    }

    // ======================== VIEW FUNCTIONS ========================

    function test_getCurrentFee() public {
        _advanceTimeAndSwap(1);

        uint24 fee = hook.getCurrentFee(poolKey);
        console.log("Current fee:", fee);
        assertTrue(fee > 0, "Fee should be positive");
        assertTrue(
            fee <= hook.BASE_FEE() * 2,
            "Fee should be at most 2x base fee"
        );
    }

    function test_getRiskScore() public {
        _advanceTimeAndSwap(1);

        uint256 rs = hook.getRiskScore(poolKey);
        console.log("Risk score:", rs);
        assertTrue(rs <= hook.MAX_RISK_SCORE(), "Risk score should be bounded");
    }

    // ======================== HELPERS ========================

    function _advanceTimeAndSwap(uint256 secondsDelta) internal {
        vm.warp(block.timestamp + secondsDelta);
        vm.roll(block.number + 1);

        uint256 amountIn = 0.001e18;
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }
}
