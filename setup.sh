#!/bin/bash
# VolVantage - Project Setup Script

set -e

echo "=== VolVantage Setup ==="

# Install OpenZeppelin uniswap-hooks (includes v4-core as transitive dep)
echo "[1/3] Installing uniswap-hooks..."
forge install openzeppelin/uniswap-hooks --commit

# Install hookmate (test helpers)
echo "[2/3] Installing hookmate..."
forge install akshatmittal/hookmate --commit

# Build to verify everything compiles
echo "[3/3] Building project..."
forge build

echo "=== Setup Complete ==="
