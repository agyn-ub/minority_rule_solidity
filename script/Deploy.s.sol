// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MinorityRuleGame} from "../src/MinorityRuleGame.sol";

/**
 * @title Deploy Script for MinorityRuleGame
 * @dev Deploys MinorityRuleGame contract across different L2 networks
 * 
 * Usage:
 * forge script script/Deploy.s.sol:DeployScript --rpc-url mantle_testnet --broadcast --verify
 * forge script script/Deploy.s.sol:DeployScript --rpc-url arbitrum --broadcast --verify
 * forge script script/Deploy.s.sol:DeployScript --rpc-url optimism --broadcast --verify
 */
contract DeployScript is Script {
    
    function setUp() public {}

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get platform fee recipient from environment or use deployer as fallback
        address platformFeeRecipient;
        try vm.envAddress("PLATFORM_FEE_RECIPIENT") returns (address recipient) {
            platformFeeRecipient = recipient;
        } catch {
            console.log("Warning: PLATFORM_FEE_RECIPIENT not set, using deployer address");
            platformFeeRecipient = deployer;
        }
        
        console.log("Deploying MinorityRuleGame...");
        console.log("Deployer:", deployer);
        console.log("Platform Fee Recipient:", platformFeeRecipient);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the contract
        MinorityRuleGame game = new MinorityRuleGame(platformFeeRecipient);
        
        vm.stopBroadcast();
        
        console.log("MinorityRuleGame deployed at:", address(game));
        console.log("Next Game ID:", game.nextGameId());
        console.log("Platform Fee Recipient:", game.platformFeeRecipient());
        console.log("Fee Percentage (basis points):", game.TOTAL_FEE_PERCENTAGE());
        
        // Log network-specific information
        logNetworkInfo(block.chainid);
        
        // Create verification command
        console.log("\nTo verify on Etherscan:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(game)),
                " src/MinorityRuleGame.sol:MinorityRuleGame --chain-id ",
                vm.toString(block.chainid),
                " --constructor-args $(cast abi-encode \"constructor(address)\" ",
                vm.toString(platformFeeRecipient),
                ")"
            )
        );
    }
    
    function logNetworkInfo(uint256 chainId) internal pure {
        if (chainId == 5000) {
            console.log("Network: Mantle Mainnet");
            console.log("Native Token: MNT");
            console.log("Explorer: https://explorer.mantle.xyz");
        } else if (chainId == 5001) {
            console.log("Network: Mantle Testnet");
            console.log("Native Token: MNT");
            console.log("Explorer: https://explorer.testnet.mantle.xyz");
        } else if (chainId == 42161) {
            console.log("Network: Arbitrum One");
            console.log("Native Token: ETH");
            console.log("Explorer: https://arbiscan.io");
        } else if (chainId == 421614) {
            console.log("Network: Arbitrum Sepolia");
            console.log("Native Token: ETH");
            console.log("Explorer: https://sepolia.arbiscan.io");
        } else if (chainId == 10) {
            console.log("Network: Optimism");
            console.log("Native Token: ETH");
            console.log("Explorer: https://optimistic.etherscan.io");
        } else if (chainId == 11155420) {
            console.log("Network: Optimism Sepolia");
            console.log("Native Token: ETH");
            console.log("Explorer: https://sepolia-optimism.etherscan.io");
        } else if (chainId == 8453) {
            console.log("Network: Base");
            console.log("Native Token: ETH");
            console.log("Explorer: https://basescan.org");
        } else if (chainId == 84532) {
            console.log("Network: Base Sepolia");
            console.log("Native Token: ETH");
            console.log("Explorer: https://sepolia.basescan.org");
        } else if (chainId == 137) {
            console.log("Network: Polygon");
            console.log("Native Token: MATIC");
            console.log("Explorer: https://polygonscan.com");
        } else if (chainId == 80001) {
            console.log("Network: Polygon Mumbai");
            console.log("Native Token: MATIC");
            console.log("Explorer: https://mumbai.polygonscan.com");
        } else {
            console.log("Network: Unknown Chain ID", chainId);
        }
    }
}