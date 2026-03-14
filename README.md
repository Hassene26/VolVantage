# 🛡️ VolVantage: RAD-IH Security Protocol

**VolVantage** is a Risk-Adjusted Dynamic Incentive Hook (RAD-IH) for Uniswap v4, specifically designed for the **Unichain** ecosystem. It protects Liquidity Providers (LPs) from toxic volatility and "stress" events by dynamically adjusting fees and automating secondary rewards.

Built for the **UHI8 Hookathon**.

## 🚀 Live on Unichain Sepolia

| Component | Address |
| :--- | :--- |
| **VolVantageHook** | [`0x14BED34ccE878e72Bd4d3b40c0E803597BF2E680`](https://sepolia.uniscan.xyz/address/0x14BED34ccE878e72Bd4d3b40c0E803597BF2E680) |
| **StressRewardToken (vSTRESS)** | [`0xA1D1B5ee47886f745707213C65073ff0BC61d7C7`](https://sepolia.uniscan.xyz/address/0xA1D1B5ee47886f745707213C65073ff0BC61d7C7) |
| **WETH/USDC Pool** | Active with RAD-IH Monitoring |

## ✨ Features

- **Composite Risk Engine:** Monitors pool "stress" using a weighted average of Volatility (TWAP deviation), Liquidity Depth, and Volume Imbalance.
- **Dynamic Fee Adjustment:** Escalates swap fees during high-risk periods to compensate LPs for toxic order flow.
- **Stress-Based Rewards:** Automatically mints `vSTRESS` tokens to LPs who provide "bravery liquidity" during high-stress windows.
- **Volatility Tax:** Applies a temporary exit tax during extreme volatility to discourage LP flight and preserve secondary market stability.

## 💻 Showcase Dashboard

I have included a high-fidelity frontend to visualize the RAD-IH system in action.

### Local Setup

1.  **Navigate to the frontend directory:**
    ```bash
    cd frontend
    ```
2.  **Install dependencies:**
    ```bash
    npm install
    ```
3.  **Run the development server:**
    ```bash
    npm run dev
    ```
4.  **Visit `http://localhost:5173`** to see the Risk Intelligence gauge and Fee Tracker.

## 🏗️ Development & Testing

### Prequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js & NPM](https://nodejs.org/)

### Smart Contracts
```bash
# Build contracts
forge build

# Run security tests
forge test

# Deploy Hook (Custom Salt Required)
forge script script/00_DeployHook.s.sol:DeployHook --rpc-url $RPC_URL --broadcast
```

## 📜 License
MIT
