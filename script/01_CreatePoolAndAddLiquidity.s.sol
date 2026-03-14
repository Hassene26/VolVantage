// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {
    CurrencyLibrary,
    Currency
} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IPositionManager
} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {VolVantageHook} from "../src/VolVantageHook.sol";

interface IERC20Metadata is IERC20 {
    function decimals() external view returns (uint8);
}

/// @notice Creates a pool with the VolVantageHook and adds initial liquidity
contract CreatePoolAndAddLiquidity is Script {
    using CurrencyLibrary for Currency;

    // Unichain Sepolia Addresses
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant POSITION_MANAGER =
        0xf969Aee60879C54bAAed9F3eD26147Db216Fd664;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external {
        // Read from environment variables
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");

        vm.startBroadcast();

        address deployer = vm.envOr("ETH_FROM", msg.sender);
        console.log("Acting from address:", deployer);

        IPoolManager poolManager = IPoolManager(POOL_MANAGER);
        IPositionManager posm = IPositionManager(POSITION_MANAGER);
        IPermit2 permit2 = IPermit2(PERMIT2);

        // Sort tokens if necessary (Uniswap v4 requires token0 < token1)
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });

        // 1. Initialize the pool at price 1:1 (Only if not already initialized)
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96
        try poolManager.initialize(poolKey, sqrtPriceX96) {
            console.log("Pool initialized!");
        } catch {
            console.log("Pool already initialized or initialization failed - skipping");
        }

        // 2. Handle Approvals (Permit2 is required for V4 PositionManager)
        uint256 amount0Used;
        uint256 amount1Used;
        {
            uint256 maxAmount = type(uint256).max;
            uint160 maxAmount160 = type(uint160).max;

            // ERC20 Approve Permit2
            IERC20(token0).approve(PERMIT2, maxAmount);
            IERC20(token1).approve(PERMIT2, maxAmount);
            
            // Permit2 Approve PositionManager
            permit2.approve(token0, address(posm), maxAmount160, type(uint48).max);
            permit2.approve(token1, address(posm), maxAmount160, type(uint48).max);
            
            // Set safer amounts: 2 USDC (6 dec) or 0.001 WETH (18 dec)
            uint8 dec0 = IERC20Metadata(token0).decimals();
            uint8 dec1 = IERC20Metadata(token1).decimals();
            
            amount0Used = (dec0 == 6) ? 10e6 : 1e15; 
            amount1Used = (dec1 == 6) ? 10e6 : 1e15;

            console.log("Permit2 approvals completed");
        }

        // 3. Add initial full-range liquidity
        {
            // Encode the actions: Mint, Settle tokens, and Sweep any dust back
            bytes memory actions = abi.encodePacked(
                uint8(Actions.MINT_POSITION),
                uint8(Actions.SETTLE_PAIR),
                uint8(Actions.SWEEP),
                uint8(Actions.SWEEP)
            );

            // Liquidity L = amount0 * sqrt(P) at initialization
            // Since sqrt(P) = 1 in raw units for our price, L = amount0
            uint256 liquidityAmount = (amount0Used < amount1Used) ? amount0Used : amount1Used;

            bytes[] memory params = new bytes[](4);
            params[0] = abi.encode(
                poolKey,
                int24(-887220), // tickLower
                int24(887220),  // tickUpper
                liquidityAmount,
                amount0Used,
                amount1Used,
                deployer,
                ""
            );
            params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
            params[2] = abi.encode(poolKey.currency0, deployer);
            params[3] = abi.encode(poolKey.currency1, deployer);

            posm.modifyLiquidities(
                abi.encode(actions, params),
                block.timestamp + 600 // 10 min deadline
            );
        }

        console.log("Liquidity added to VolVantageHook pool!");
        console.log("PoolKey Currency0:", token0);
        console.log("PoolKey Currency1:", token1);
        console.log("Hook Address:", hookAddress);

        vm.stopBroadcast();
    }
}
