#!/bin/bash

# Deployment script for MinorityRuleGame across different L2 networks
# Usage: ./script/deploy.sh [network]
# Networks: mantle, mantle_testnet, arbitrum, arbitrum_sepolia, optimism, optimism_sepolia, base, base_sepolia, polygon, polygon_mumbai

set -e

NETWORK=${1:-mantle_testnet}

echo "🚀 Deploying MinorityRuleGame to $NETWORK..."

# Check if required environment variables are set
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY environment variable is not set"
    echo "Please set it with: export PRIVATE_KEY=your_private_key"
    exit 1
fi

if [ -z "$PLATFORM_FEE_RECIPIENT" ]; then
    echo "⚠️  Warning: PLATFORM_FEE_RECIPIENT not set, using deployer address"
fi

# Network-specific configurations
case $NETWORK in
    "mantle")
        RPC_URL="https://rpc.mantle.xyz"
        CHAIN_ID="5000"
        EXPLORER="https://explorer.mantle.xyz"
        NATIVE_TOKEN="MNT"
        ;;
    "mantle_testnet")
        RPC_URL="https://rpc.testnet.mantle.xyz"
        CHAIN_ID="5001"
        EXPLORER="https://explorer.testnet.mantle.xyz"
        NATIVE_TOKEN="MNT"
        ;;
    "arbitrum")
        RPC_URL="https://arb1.arbitrum.io/rpc"
        CHAIN_ID="42161"
        EXPLORER="https://arbiscan.io"
        NATIVE_TOKEN="ETH"
        ;;
    "arbitrum_sepolia")
        RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
        CHAIN_ID="421614"
        EXPLORER="https://sepolia.arbiscan.io"
        NATIVE_TOKEN="ETH"
        ;;
    "optimism")
        RPC_URL="https://mainnet.optimism.io"
        CHAIN_ID="10"
        EXPLORER="https://optimistic.etherscan.io"
        NATIVE_TOKEN="ETH"
        ;;
    "optimism_sepolia")
        RPC_URL="https://sepolia.optimism.io"
        CHAIN_ID="11155420"
        EXPLORER="https://sepolia-optimism.etherscan.io"
        NATIVE_TOKEN="ETH"
        ;;
    "base")
        RPC_URL="https://mainnet.base.org"
        CHAIN_ID="8453"
        EXPLORER="https://basescan.org"
        NATIVE_TOKEN="ETH"
        ;;
    "base_sepolia")
        RPC_URL="https://sepolia.base.org"
        CHAIN_ID="84532"
        EXPLORER="https://sepolia.basescan.org"
        NATIVE_TOKEN="ETH"
        ;;
    "polygon")
        RPC_URL="https://polygon-rpc.com"
        CHAIN_ID="137"
        EXPLORER="https://polygonscan.com"
        NATIVE_TOKEN="MATIC"
        ;;
    "polygon_mumbai")
        RPC_URL="https://rpc-mumbai.maticvigil.com"
        CHAIN_ID="80001"
        EXPLORER="https://mumbai.polygonscan.com"
        NATIVE_TOKEN="MATIC"
        ;;
    *)
        echo "❌ Error: Unknown network $NETWORK"
        echo "Supported networks: mantle, mantle_testnet, arbitrum, arbitrum_sepolia, optimism, optimism_sepolia, base, base_sepolia, polygon, polygon_mumbai"
        exit 1
        ;;
esac

echo "📍 Network: $NETWORK"
echo "🔗 RPC URL: $RPC_URL"
echo "🆔 Chain ID: $CHAIN_ID"
echo "💰 Native Token: $NATIVE_TOKEN"
echo "🔍 Explorer: $EXPLORER"
echo ""

# Run the deployment
echo "📦 Compiling contracts..."
forge build

echo "🚀 Deploying contract..."
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --chain-id $CHAIN_ID

echo ""
echo "✅ Deployment completed!"
echo ""
echo "📋 Next steps:"
echo "1. Check the deployment on the explorer: $EXPLORER"
echo "2. Save the contract address for frontend integration"
echo "3. Test the contract with some sample transactions"
echo "4. Update your frontend to use the correct network and contract address"

# Create a deployment record
DEPLOYMENT_FILE="deployments/${NETWORK}.json"
mkdir -p deployments

# Note: Contract address would need to be extracted from deployment output
# This is a placeholder structure for the deployment record
cat > $DEPLOYMENT_FILE << EOF
{
    "network": "$NETWORK",
    "chainId": $CHAIN_ID,
    "rpcUrl": "$RPC_URL",
    "explorer": "$EXPLORER",
    "nativeToken": "$NATIVE_TOKEN",
    "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
    "contracts": {
        "MinorityRuleGame": {
            "address": "TBD_FROM_DEPLOYMENT_OUTPUT",
            "constructorArgs": {
                "platformFeeRecipient": "${PLATFORM_FEE_RECIPIENT:-TBD}"
            }
        }
    }
}
EOF

echo "📝 Deployment record saved to $DEPLOYMENT_FILE"