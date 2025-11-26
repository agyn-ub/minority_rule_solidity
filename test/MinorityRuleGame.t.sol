// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {MinorityRuleGame} from "../src/MinorityRuleGame.sol";

contract MinorityRuleGameTest is Test {
    MinorityRuleGame public game;

    address public platformFeeRecipient;
    address public creator;
    address public player1;
    address public player2;
    address public player3;
    address public player4;

    uint256 public constant ENTRY_FEE = 1 ether;
    string public constant QUESTION = "Is the sky blue?";

    // Events for testing
    event GameCreated(
        uint64 indexed gameId,
        uint256 entryFee,
        address indexed creator,
        string questionText
    );
    event PlayerJoined(
        uint64 indexed gameId,
        address indexed player,
        uint256 amount,
        uint32 totalPlayers
    );
    event VoteCommitted(
        uint64 indexed gameId,
        uint8 round,
        address indexed player
    );
    event VoteRevealed(
        uint64 indexed gameId,
        uint8 round,
        address indexed player,
        bool vote
    );
    event RoundCompleted(
        uint64 indexed gameId,
        uint8 round,
        uint32 yesCount,
        uint32 noCount,
        bool minorityVote,
        uint32 votesRemaining
    );
    event GameCompleted(
        uint64 indexed gameId,
        uint8 totalRounds,
        uint256 finalPrize,
        uint256 platformFee
    );
    event PrizeDistributed(
        uint64 indexed gameId,
        address indexed winner,
        uint256 amount
    );

    function setUp() public {
        platformFeeRecipient = makeAddr("platformFeeRecipient");
        creator = makeAddr("creator");
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");
        player4 = makeAddr("player4");

        game = new MinorityRuleGame(platformFeeRecipient);

        // Fund test accounts
        vm.deal(creator, 10 ether);
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(player4, 10 ether);
    }

    function testCreateGame() public {
        vm.prank(creator);

        vm.expectEmit(true, false, false, true);
        emit GameCreated(1, ENTRY_FEE, creator, QUESTION);

        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        assertEq(gameId, 1);
        assertEq(game.nextGameId(), 2);

        // Check game info
        (
            uint64 id,
            string memory questionText,
            uint256 entryFee,
            address gameCreator,
            uint8 state,
            uint8 currentRound,
            uint32 totalPlayers,
            ,
            ,
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
        assertEq(prizePool, 0);
        assertEq(commitDeadline, 0);
        assertEq(revealDeadline, 0);
    }

    function testSetCommitDeadlineAndJoinGame() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        // Set commit deadline
        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600); // 1 hour

        // Check state changed to CommitPhase
        (, , , , uint8 state, , , , , , uint256 commitDeadline, ) = game
            .getGameInfo(gameId);
        assertEq(state, 1); // CommitPhase
        assertEq(commitDeadline, block.timestamp + 3600);

        // Players join game
        vm.prank(player1);
        vm.expectEmit(true, true, false, true);
        emit PlayerJoined(gameId, player1, ENTRY_FEE, 1);
        game.joinGame{value: ENTRY_FEE}(gameId);

        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}(gameId);

        vm.prank(player3);
        game.joinGame{value: ENTRY_FEE}(gameId);

        // Check game state
        (, , , , , , uint32 totalPlayers, , , uint256 prizePool, , ) = game
            .getGameInfo(gameId);
        assertEq(totalPlayers, 3);
        assertEq(prizePool, 3 * ENTRY_FEE);

        // Check players array
        address[] memory players = game.getGamePlayers(gameId);
        assertEq(players.length, 3);
        assertEq(players[0], player1);
        assertEq(players[1], player2);
        assertEq(players[2], player3);

        // Check user game history
        uint64[] memory history = game.getUserGameHistory(player1);
        assertEq(history.length, 1);
        assertEq(history[0], gameId);
    }

    function testCommitRevealVoting() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        // Players join
        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);

        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}(gameId);

        // Create commits
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 commit1 = keccak256(abi.encodePacked(true, salt1)); // Yes vote
        bytes32 commit2 = keccak256(abi.encodePacked(false, salt2)); // No vote

        // Submit commits
        vm.prank(player1);
        vm.expectEmit(true, false, false, true);
        emit VoteCommitted(gameId, 1, player1);
        game.submitCommit(gameId, commit1);

        vm.prank(player2);
        game.submitCommit(gameId, commit2);

        // Check commit status
        assertTrue(game.hasPlayerCommitted(gameId, player1));
        assertTrue(game.hasPlayerCommitted(gameId, player2));
        assertFalse(game.hasPlayerRevealed(gameId, player1));

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 3601);

        // Set reveal deadline
        vm.prank(creator);
        game.setRevealDeadline(gameId, 1800); // 30 minutes

        // Check state changed to RevealPhase
        (, , , , uint8 state, , , , , , , ) = game.getGameInfo(gameId);
        assertEq(state, 2); // RevealPhase

        // Submit reveals
        vm.prank(player1);
        vm.expectEmit(true, false, false, true);
        emit VoteRevealed(gameId, 1, player1, true);
        game.submitReveal(gameId, true, salt1);

        vm.prank(player2);
        game.submitReveal(gameId, false, salt2);

        // Check reveal status
        assertTrue(game.hasPlayerRevealed(gameId, player1));
        assertTrue(game.hasPlayerRevealed(gameId, player2));

        // Check vote counts
        (, , , , , , , uint32 yesVotes, uint32 noVotes, , , ) = game
            .getGameInfo(gameId);
        assertEq(yesVotes, 1);
        assertEq(noVotes, 1);
    }

    function testProcessRoundAndGameCompletion() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        // Players join
        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);

        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}(gameId);

        vm.prank(player3);
        game.joinGame{value: ENTRY_FEE}(gameId);

        // Create commits (2 yes, 1 no - minority is no)
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");
        bytes32 commit1 = keccak256(abi.encodePacked(true, salt1)); // Yes
        bytes32 commit2 = keccak256(abi.encodePacked(true, salt2)); // Yes
        bytes32 commit3 = keccak256(abi.encodePacked(false, salt3)); // No (minority)

        // Submit commits
        vm.prank(player1);
        game.submitCommit(gameId, commit1);
        vm.prank(player2);
        game.submitCommit(gameId, commit2);
        vm.prank(player3);
        game.submitCommit(gameId, commit3);

        vm.warp(block.timestamp + 3601);

        vm.prank(creator);
        game.setRevealDeadline(gameId, 1800);

        // Submit reveals
        vm.prank(player1);
        game.submitReveal(gameId, true, salt1);
        vm.prank(player2);
        game.submitReveal(gameId, true, salt2);
        vm.prank(player3);
        game.submitReveal(gameId, false, salt3);

        // Process round
        vm.expectEmit(true, false, false, true);
        emit RoundCompleted(gameId, 1, 2, 1, false, 1); // false is minority vote, 1 remaining
        game.processRound(gameId);

        // Check remaining players (only player3 who voted minority)
        address[] memory remainingPlayers = game.getRemainingPlayers(gameId);
        assertEq(remainingPlayers.length, 1);
        assertEq(remainingPlayers[0], player3);

        // Game should be completed since only 1 player remains
        (, , , , uint8 state, , , , , , , ) = game.getGameInfo(gameId);
        assertEq(state, 4); // Completed

        // Check winners
        address[] memory winners = game.getGameWinners(gameId);
        assertEq(winners.length, 1);
        assertEq(winners[0], player3);
    }

    function testPrizeDistribution() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        // Three players join
        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player3);
        game.joinGame{value: ENTRY_FEE}(gameId);

        uint256 initialPlayer3Balance = player3.balance;
        uint256 initialPlatformBalance = platformFeeRecipient.balance;

        // Setup voting (player3 wins as minority)
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        vm.prank(player1);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt1)));
        vm.prank(player2);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt2)));
        vm.prank(player3);
        game.submitCommit(gameId, keccak256(abi.encodePacked(false, salt3)));

        vm.warp(block.timestamp + 3601);

        vm.prank(creator);
        game.setRevealDeadline(gameId, 1800);

        vm.prank(player1);
        game.submitReveal(gameId, true, salt1);
        vm.prank(player2);
        game.submitReveal(gameId, true, salt2);
        vm.prank(player3);
        game.submitReveal(gameId, false, salt3);

        // Process round - this should trigger game completion and prize distribution
        game.processRound(gameId);

        // Calculate expected amounts
        uint256 totalPrize = 3 * ENTRY_FEE;
        uint256 platformFee = (totalPrize * 200) / 10000; // 2%
        uint256 winnerPrize = totalPrize - platformFee;

        // Check balances after prize distribution
        // Player3 initial balance was 10 ETH, paid 1 ETH entry fee, received 2.94 ETH prize
        // Final balance should be 10 - 1 + 2.94 = 11.94 ETH
        assertEq(
            player3.balance,
            initialPlayer3Balance - ENTRY_FEE + winnerPrize
        );
        assertEq(
            platformFeeRecipient.balance,
            initialPlatformBalance + platformFee
        );
    }

    function testInvalidReveal() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);

        bytes32 salt = keccak256("salt");
        bytes32 commit = keccak256(abi.encodePacked(true, salt));

        vm.prank(player1);
        game.submitCommit(gameId, commit);

        vm.warp(block.timestamp + 3601);

        vm.prank(creator);
        game.setRevealDeadline(gameId, 1800);

        // Try to reveal with wrong vote (should fail)
        vm.prank(player1);
        vm.expectRevert("Reveal does not match commitment");
        game.submitReveal(gameId, false, salt); // Committed true, revealing false
    }

    function testCannotJoinAfterRound1() public {
        // Create additional players to ensure game continues to round 2
        address player5 = makeAddr("player5");
        address player6 = makeAddr("player6"); 
        vm.deal(player5, 10 ether);
        vm.deal(player6, 10 ether);
        
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        // Six players join to ensure more than 2 remain
        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player3);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player4);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player5);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player6);
        game.joinGame{value: ENTRY_FEE}(gameId);

        // Round 1: 3 yes, 3 no (tie, yes is minority since <= comparison) - 3 advance to round 2
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");
        bytes32 salt4 = keccak256("salt4");
        bytes32 salt5 = keccak256("salt5");
        bytes32 salt6 = keccak256("salt6");

        vm.prank(player1);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt1))); // yes (minority)
        vm.prank(player2);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt2))); // yes (minority)
        vm.prank(player3);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt3))); // yes (minority)
        vm.prank(player4);
        game.submitCommit(gameId, keccak256(abi.encodePacked(false, salt4))); // no  
        vm.prank(player5);
        game.submitCommit(gameId, keccak256(abi.encodePacked(false, salt5))); // no
        vm.prank(player6);
        game.submitCommit(gameId, keccak256(abi.encodePacked(false, salt6))); // no

        vm.warp(block.timestamp + 3601);

        vm.prank(creator);
        game.setRevealDeadline(gameId, 1800);

        vm.prank(player1);
        game.submitReveal(gameId, true, salt1);
        vm.prank(player2);
        game.submitReveal(gameId, true, salt2);
        vm.prank(player3);
        game.submitReveal(gameId, true, salt3);
        vm.prank(player4);
        game.submitReveal(gameId, false, salt4);
        vm.prank(player5);
        game.submitReveal(gameId, false, salt5);
        vm.prank(player6);
        game.submitReveal(gameId, false, salt6);

        // Process round 1 - should advance to round 2 with 3 players
        game.processRound(gameId);
        
        // Verify game continues to round 2
        (, , , , uint8 state, uint8 currentRound, , , , , , ) = game.getGameInfo(gameId);
        assertEq(state, 0); // ZeroPhase
        assertEq(currentRound, 2); // Round 2
        
        // Set commit deadline for round 2
        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        // Now try to join in round 2 - should fail with round check
        address newPlayer = makeAddr("newPlayer");
        vm.deal(newPlayer, 10 ether);
        vm.prank(newPlayer);
        vm.expectRevert("Can only join during Round 1");
        game.joinGame{value: ENTRY_FEE}(gameId);
    }

    function testMultipleRounds() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        // Four players join
        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player3);
        game.joinGame{value: ENTRY_FEE}(gameId);
        vm.prank(player4);
        game.joinGame{value: ENTRY_FEE}(gameId);

        // Round 1: 3 yes, 1 no (no is minority)
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");
        bytes32 salt4 = keccak256("salt4");

        vm.prank(player1);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt1)));
        vm.prank(player2);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt2)));
        vm.prank(player3);
        game.submitCommit(gameId, keccak256(abi.encodePacked(true, salt3)));
        vm.prank(player4);
        game.submitCommit(gameId, keccak256(abi.encodePacked(false, salt4)));

        vm.warp(block.timestamp + 3601);

        vm.prank(creator);
        game.setRevealDeadline(gameId, 1800);

        vm.prank(player1);
        game.submitReveal(gameId, true, salt1);
        vm.prank(player2);
        game.submitReveal(gameId, true, salt2);
        vm.prank(player3);
        game.submitReveal(gameId, true, salt3);
        vm.prank(player4);
        game.submitReveal(gameId, false, salt4);

        game.processRound(gameId);

        // Check game completed state (only 1 player remains, so game ends immediately)
        (, , , , uint8 state, uint8 currentRound, , , , , , ) = game
            .getGameInfo(gameId);
        assertEq(state, 4); // Completed due to <= 2 players remaining
        assertEq(currentRound, 1); // Game ended in round 1

        address[] memory winners = game.getGameWinners(gameId);
        assertEq(winners.length, 1);
        assertEq(winners[0], player4);
    }

    function testCannotCreateGameWithInvalidParameters() public {
        vm.prank(creator);

        // Empty question
        vm.expectRevert("Question text cannot be empty");
        game.createGame("", ENTRY_FEE);

        // Zero entry fee
        vm.expectRevert("Entry fee must be greater than 0");
        game.createGame(QUESTION, 0);
    }

    function testDeadlineEnforcement() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 3601);

        // Try to join after deadline (should fail)
        vm.prank(player2);
        vm.expectRevert("Commit deadline has passed");
        game.joinGame{value: ENTRY_FEE}(gameId);

        // Try to commit after deadline (should fail)
        vm.prank(player1);
        vm.expectRevert("Commit deadline has passed");
        game.submitCommit(gameId, keccak256("test"));
    }

    function testOnlyCreatorCanSetDeadlines() public {
        vm.prank(creator);
        uint64 gameId = game.createGame(QUESTION, ENTRY_FEE);

        // Non-creator tries to set commit deadline
        vm.prank(player1);
        vm.expectRevert("Only creator can set deadlines");
        game.setCommitDeadline(gameId, 3600);

        vm.prank(creator);
        game.setCommitDeadline(gameId, 3600);

        vm.prank(player1);
        game.joinGame{value: ENTRY_FEE}(gameId);

        vm.prank(player1);
        game.submitCommit(gameId, keccak256("test"));

        vm.warp(block.timestamp + 3601);

        // Non-creator tries to set reveal deadline
        vm.prank(player1);
        vm.expectRevert("Only creator can set deadlines");
        game.setRevealDeadline(gameId, 1800);
    }

    function testViewFunctions() public {
        vm.prank(creator);
        game.createGame(QUESTION, ENTRY_FEE);

        // Test getTotalGamesCount
        assertEq(game.getTotalGamesCount(), 1);

        vm.prank(creator);
        game.createGame("Another question?", 2 ether);

        assertEq(game.getTotalGamesCount(), 2);
    }
}
