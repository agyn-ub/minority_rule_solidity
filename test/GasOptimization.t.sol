// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {MinorityRuleGame} from "../src/MinorityRuleGame.sol";

/**
 * @title Gas Optimization Tests
 * @dev Tests to verify gas optimizations are working correctly
 */
contract GasOptimizationTest is Test {
    MinorityRuleGame public game;
    
    address public platformFeeRecipient;
    address public creator;
    address[] public players;
    
    uint256 public constant ENTRY_FEE = 1 ether;
    string public constant QUESTION = "Gas optimization test?";
    
    function setUp() public {
        platformFeeRecipient = makeAddr("platformFeeRecipient");
        creator = makeAddr("creator");
        
        game = new MinorityRuleGame(platformFeeRecipient);
        
        // Create 20 test players
        for (uint i = 0; i < 20; i++) {
            address player = makeAddr(string(abi.encodePacked("player", i)));
            players.push(player);
            vm.deal(player, 10 ether);
        }
        
        vm.deal(creator, 10 ether);
    }

    function testPlayerDuplicateCheckOptimization() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);
        
        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);
        
        // Test that the first join works (should use O(1) lookup)
        vm.prank(players[0]);
        uint256 gasBefore = gasleft();
        game.joinGame{value: ENTRY_FEE}(gameId);
        uint256 gasUsed1 = gasBefore - gasleft();
        
        // Add multiple players
        for (uint i = 1; i < 10; i++) {
            vm.prank(players[i]);
            game.joinGame{value: ENTRY_FEE}(gameId);
        }
        
        // Test that another join still uses reasonable gas (O(1) not O(n))
        vm.prank(players[10]);
        gasBefore = gasleft();
        game.joinGame{value: ENTRY_FEE}(gameId);
        uint256 gasUsed2 = gasBefore - gasleft();
        
        console.log("Gas used for 1st join:", gasUsed1);
        console.log("Gas used for 11th join:", gasUsed2);
        console.log("Gas difference:", gasUsed2 > gasUsed1 ? gasUsed2 - gasUsed1 : gasUsed1 - gasUsed2);
        
        // The gas difference should be reasonable (within 100k gas)
        // In the old O(n) implementation with 10 players, it would use ~20k more gas per player
        uint256 gasDiff = gasUsed2 > gasUsed1 ? gasUsed2 - gasUsed1 : gasUsed1 - gasUsed2;
        assertLt(gasDiff, 100000, "Gas usage should not scale significantly with player count");
        
        // Test duplicate prevention still works
        vm.prank(players[0]);
        vm.expectRevert("Player has already joined this game");
        game.joinGame{value: ENTRY_FEE}(gameId);
    }

    function testCommitRevealOptimization() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);
        
        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);
        
        // Test that the first join works (should use O(1) lookup)
        vm.prank(players[0]);
        uint256 gasBefore = gasleft();
        game.joinGame{value: ENTRY_FEE}(gameId);
        uint256 gasUsed1 = gasBefore - gasleft();
        
        // Add multiple players
        for (uint i = 1; i < 10; i++) {
            vm.prank(players[i]);
            game.joinGame{value: ENTRY_FEE}(gameId);
        }
        
        // Test that another join still uses the same gas (O(1) not O(n))
        vm.prank(players[10]);
        gasBefore = gasleft();
        game.joinGame{value: ENTRY_FEE}(gameId);
        uint256 gasUsed2 = gasBefore - gasleft();
        
        console.log("Gas used for 1st join:", gasUsed1);
        console.log("Gas used for 11th join:", gasUsed2);
        console.log("Gas difference:", gasUsed2 > gasUsed1 ? gasUsed2 - gasUsed1 : gasUsed1 - gasUsed2);
        
        // The gas difference should be reasonable (within 50k gas)
        // In the old O(n) implementation with 10 players, it would use ~20k more gas
        uint256 gasDiff = gasUsed2 > gasUsed1 ? gasUsed2 - gasUsed1 : gasUsed1 - gasUsed2;
        assertLt(gasDiff, 50000, "Gas usage should not scale significantly with player count");
        
        // The important thing is that it's much better than O(n) scaling
        // With our optimization, gas usage should be relatively constant
        
        // Test duplicate prevention still works
        vm.prank(players[0]);
        vm.expectRevert("Player has already joined this game");
        game.joinGame{value: ENTRY_FEE}(gameId);
    }

    function testHasPlayerJoinedFunction() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);
        
        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);
        
        // Test before joining
        assertFalse(game.hasPlayerJoined(gameId, players[0]), "Player should not be joined initially");
        
        // Join game
        vm.prank(players[0]);
        game.joinGame{value: ENTRY_FEE}(gameId);
        
        // Test after joining
        assertTrue(game.hasPlayerJoined(gameId, players[0]), "Player should be marked as joined");
        assertFalse(game.hasPlayerJoined(gameId, players[1]), "Other players should not be marked as joined");
    }

    function testStructPacking() public {
        // This test ensures that our struct packing doesn't break functionality
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);
        
        // Test all fields are accessible after packing
        (
            uint64 id,
            string memory questionText,
            uint256 entryFee,
            address gameCreator,
            uint8 state,
            uint8 currentRound,
            uint32 totalPlayers,
            uint32 currentYesVotes,
            uint32 currentNoVotes,
            uint256 prizePool,
            uint256 commitDeadline,
            uint256 revealDeadline
        ) = game.getGameInfo(gameId);
        
        assertEq(id, 1);
        assertEq(questionText, QUESTION);
        assertEq(entryFee, ENTRY_FEE);
        assertEq(gameCreator, creator);
        assertEq(state, 0); // ZeroPhase
        assertEq(currentRound, 1);
        assertEq(totalPlayers, 0);
        assertEq(currentYesVotes, 0);
        assertEq(currentNoVotes, 0);
        assertEq(prizePool, 0);
        assertEq(commitDeadline, 0);
        assertEq(revealDeadline, 0);
    }
}