// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title StressRewardToken
/// @notice ERC-20 token minted to LPs who provide liquidity during high-stress periods.
///         Only the VolVantageHook can mint new tokens.
contract StressRewardToken is ERC20, Ownable {
    address public hook;

    error OnlyHook();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor(address _owner)
        ERC20("VolVantage Stress Reward", "vSTRESS")
        Ownable(_owner)
    {}

    /// @notice Set the hook address that is allowed to mint. Can only be called once by owner.
    function setHook(address _hook) external onlyOwner {
        require(hook == address(0), "Hook already set");
        hook = _hook;
    }

    /// @notice Mint reward tokens. Only callable by the hook contract or the owner (for bootstrapping).
    /// @param to The recipient address
    /// @param amount The amount to mint
    function mint(address to, uint256 amount) external onlyHook {
        _mint(to, amount);
    }

    /// @notice OWNER ONLY: Mint tokens for bootstrapping liquidity or testing.
    function ownerMint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
