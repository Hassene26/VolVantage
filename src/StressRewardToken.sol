// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title StressRewardToken
/// @notice ERC-20 token minted to LPs who provide liquidity during high-stress periods.
///         Only the VolVantageHook can mint new tokens.
contract StressRewardToken is ERC20 {
    address public hook;
    address public owner;

    error OnlyHook();
    error OnlyOwner();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _owner) ERC20("VolVantage Stress Reward", "vSTRESS") {
        owner = _owner;
    }

    /// @notice Set the hook address that is allowed to mint. Can only be called once by owner.
    function setHook(address _hook) external onlyOwner {
        require(hook == address(0), "Hook already set");
        hook = _hook;
    }

    /// @notice Mint reward tokens to a recipient. Only callable by the hook contract.
    /// @param to The LP address to receive rewards
    /// @param amount The reward amount, scaled by the Risk Score
    function mint(address to, uint256 amount) external onlyHook {
        _mint(to, amount);
    }
}
