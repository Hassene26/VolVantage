// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {VolVantageHook} from "../src/VolVantageHook.sol";
import {StressRewardToken} from "../src/StressRewardToken.sol";

/// @notice Deploys VolVantageHook and StressRewardToken to Unichain Sepolia
contract DeployHook is Script {
    // CREATE2 Proxy used by forge scripts
    address constant CREATE2_DEPLOYER =
        0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        // Get the PoolManager address based on the chain
        address poolManagerAddress;
        if (block.chainid == 1301) {
            // Unichain Sepolia
            poolManagerAddress = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
        } else if (block.chainid == 31337) {
            // Local Anvil — use a placeholder (tests deploy their own)
            poolManagerAddress = address(0x1);
        } else {
            revert("Unsupported chain");
        }

        IPoolManager poolManager = IPoolManager(poolManagerAddress);

        vm.startBroadcast();

        // Capture the broadcaster address. 
        // Forge set ETH_FROM if --sender is provided, which is needed for correct simulation.
        address deployer = vm.envOr("ETH_FROM", msg.sender);
        console.log("Deploying from address:", deployer);

        // 1. Deploy the reward token
        // Pass the captured deployer address as the owner
        StressRewardToken rewardToken = new StressRewardToken(deployer);
        console.log("StressRewardToken deployed at:", address(rewardToken));

        // 2. Mine the correct salt for the hook address
        // The hook address must have the correct permission bits in its low 14 bits
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        // VolVantageHook constructor now takes (poolManager, rewardToken, owner)
        bytes memory constructorArgs = abi.encode(
            poolManager,
            rewardToken,
            deployer
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(VolVantageHook).creationCode,
            constructorArgs
        );
        console.log("Hook will deploy to:", hookAddress);

        // 3. Deploy the hook with the mined salt
        VolVantageHook hook = new VolVantageHook{salt: salt}(
            poolManager,
            rewardToken,
            deployer
        );
        require(address(hook) == hookAddress, "Hook address mismatch");
        console.log("VolVantageHook deployed at:", address(hook));

        // 4. Set the hook as the minter on the reward token
        rewardToken.setHook(address(hook));
        console.log("Reward token minter set to hook");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("PoolManager:", poolManagerAddress);
        console.log("StressRewardToken:", address(rewardToken));
        console.log("VolVantageHook:", address(hook));
    }
}
