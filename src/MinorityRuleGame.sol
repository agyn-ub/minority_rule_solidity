// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MinorityRuleGame
 * @dev A blockchain-based game where players vote on yes/no questions,
 *      and only those who vote with the minority advance to the next round.
 *      Uses commit-reveal scheme for vote privacy.
 */
contract MinorityRuleGame {
    // Events - Full game history stored on-chain
    event GameCreated(uint64 indexed gameId, uint256 entryFee, address indexed creator, string questionText);
    event PlayerJoined(uint64 indexed gameId, address indexed player, uint256 amount, uint32 totalPlayers);
    event GameStarted(uint64 indexed gameId, uint32 totalPlayers);
    event VoteCommitted(uint64 indexed gameId, uint8 round, address indexed player);
    event VoteRevealed(uint64 indexed gameId, uint8 round, address indexed player, bool vote);
    event CommitPhaseStarted(uint64 indexed gameId, uint8 round, uint256 deadline);
    event RevealPhaseStarted(uint64 indexed gameId, uint8 round, uint256 deadline);
    event NewRoundStarted(uint64 indexed gameId, uint8 round);
    event CommitDeadlineSet(uint64 indexed gameId, uint8 round, uint256 duration, uint256 deadline);
    event RevealDeadlineSet(uint64 indexed gameId, uint8 round, uint256 duration, uint256 deadline);
    event InvalidReveal(uint64 indexed gameId, uint8 round, address indexed player);
    event RoundCompleted(uint64 indexed gameId, uint8 round, uint32 yesCount, uint32 noCount, bool minorityVote, uint32 votesRemaining);
    event GameCompleted(uint64 indexed gameId, uint8 totalRounds, uint256 finalPrize, uint256 platformFee);
    event PrizeDistributed(uint64 indexed gameId, address indexed winner, uint256 amount);

    // Game states
    enum GameState {
        ZeroPhase,     // 0 - Initial state, waiting for commit deadline
        CommitPhase,   // 1 - Players submit vote commitments
        RevealPhase,   // 2 - Players reveal their votes
        ProcessingRound, // 3 - Determining round results
        Completed      // 4 - Game ended, prizes distributed
    }

    // Player vote record
    struct VoteRecord {
        uint8 round;
        bool vote;
        uint256 timestamp;
    }

    // Player commit record (stores hash of vote + salt)
    struct CommitRecord {
        uint8 round;
        bytes32 commitHash;
        uint256 timestamp;
    }

    // Player reveal record (stores revealed vote + salt)
    struct RevealRecord {
        uint8 round;
        bool vote;
        bytes32 salt;
        uint256 timestamp;
    }

    // Game struct - stores all game data (optimized for storage packing)
    struct Game {
        // Slot 1: Pack small types together
        uint64 gameId;              // 8 bytes
        GameState state;            // 1 byte  
        uint8 currentRound;         // 1 byte
        uint32 totalPlayers;        // 4 bytes
        uint32 currentRoundYesVotes; // 4 bytes
        uint32 currentRoundNoVotes; // 4 bytes
        uint32 currentCommitCount; // 4 bytes - track commit count  
        uint16 currentRevealCount; // 2 bytes - track reveal count
        // Total: 28 bytes (fits in 32-byte slot)
        
        // Slot 2: Address (20 bytes) + padding
        address creator;            // 20 bytes
        
        // Slot 3-4: 256-bit values (each takes full slot)
        uint256 entryFee;
        uint256 prizePool;
        
        // Slot 5-6: Deadline values
        uint256 commitDeadline;
        uint256 revealDeadline;
        
        // Dynamic types and mappings (separate storage)
        string questionText;
        address[] players;
        address[] remainingPlayers;
        address[] winners;
        
        // Round results - which answer was minority
        mapping(uint8 => bool) roundResults;
        
        // Commit-reveal mappings
        mapping(address => CommitRecord) currentRoundCommits;
        mapping(address => RevealRecord) currentRoundReveals;
        
        // Player vote history
        mapping(address => VoteRecord[]) playerVoteHistory;
        
        // Efficient player membership tracking
        mapping(address => bool) hasJoined;
        mapping(address => bool) isRemainingPlayer;
    }

    // Contract state
    uint64 public nextGameId;
    uint256 public constant TOTAL_FEE_PERCENTAGE = 200; // 2% (basis points: 200/10000)
    address public immutable platformFeeRecipient;
    
    // Games storage
    mapping(uint64 => Game) public games;
    
    // User game history
    mapping(address => uint64[]) public userGameHistory;

    constructor(address _platformFeeRecipient) {
        require(_platformFeeRecipient != address(0), "Invalid platform fee recipient");
        nextGameId = 1;
        platformFeeRecipient = _platformFeeRecipient;
    }

    /**
     * @dev Create a new game
     * @param questionText The yes/no question for the game
     * @param entryFee Entry fee in native tokens (wei)
     * @return gameId The ID of the created game
     */
    function createGame(
        string memory questionText,
        uint256 entryFee
    ) external returns (uint64 gameId) {
        require(bytes(questionText).length > 0, "Question text cannot be empty");
        require(entryFee > 0, "Entry fee must be greater than 0");
        
        gameId = nextGameId;
        nextGameId++;
        
        Game storage game = games[gameId];
        game.gameId = gameId;
        game.questionText = questionText;
        game.entryFee = entryFee;
        game.creator = msg.sender;
        game.state = GameState.ZeroPhase;
        game.currentRound = 1;
        game.totalPlayers = 0;
        game.currentRoundYesVotes = 0;
        game.currentRoundNoVotes = 0;
        game.commitDeadline = 0;
        game.revealDeadline = 0;
        game.prizePool = 0;
        
        emit GameCreated(gameId, entryFee, msg.sender, questionText);
        emit CommitPhaseStarted(gameId, 1, 0); // Deadline will be set manually
    }

    /**
     * @dev Join a game by paying the entry fee
     * @param gameId The ID of the game to join
     */
    function joinGame(uint64 gameId) external payable {
        Game storage game = games[gameId];
        
        require(game.gameId != 0, "Game does not exist");
        require(game.currentRound == 1, "Can only join during Round 1");
        require(game.state == GameState.CommitPhase, "Game must be in commit phase to join");
        require(game.commitDeadline == 0 || block.timestamp <= game.commitDeadline, "Commit deadline has passed");
        require(msg.value == game.entryFee, "Payment amount does not match entry fee");
        
        // Check if player already joined (O(1) lookup)
        require(!game.hasJoined[msg.sender], "Player has already joined this game");
        
        // Add entry fee to prize pool
        game.prizePool += msg.value;
        game.totalPlayers++;
        
        // Store player in array and mark as joined/remaining
        game.players.push(msg.sender);
        game.hasJoined[msg.sender] = true;
        game.isRemainingPlayer[msg.sender] = true; // All players start as remaining
        
        // Add game to user's history
        userGameHistory[msg.sender].push(gameId);
        
        emit PlayerJoined(gameId, msg.sender, msg.value, game.totalPlayers);
    }

    /**
     * @dev Set commit deadline and transition to commit phase
     * @param gameId The game ID
     * @param durationSeconds Duration in seconds for commit phase
     */
    function setCommitDeadline(uint64 gameId, uint256 durationSeconds) external {
        Game storage game = games[gameId];
        
        require(game.gameId != 0, "Game does not exist");
        require(msg.sender == game.creator, "Only creator can set deadlines");
        require(game.state == GameState.ZeroPhase, "Game must be in zero phase");
        require(durationSeconds > 0, "Duration must be positive");
        
        uint256 deadline = block.timestamp + durationSeconds;
        game.commitDeadline = deadline;
        game.state = GameState.CommitPhase;
        
        emit CommitDeadlineSet(gameId, game.currentRound, durationSeconds, deadline);
    }

    /**
     * @dev Submit a vote commitment (hash of vote + salt)
     * @param gameId The game ID
     * @param commitHash SHA3-256 hash of vote + salt
     */
    function submitCommit(uint64 gameId, bytes32 commitHash) external {
        Game storage game = games[gameId];
        
        require(game.gameId != 0, "Game does not exist");
        require(game.state == GameState.CommitPhase, "Commit phase is not active");
        require(game.commitDeadline == 0 || block.timestamp <= game.commitDeadline, "Commit deadline has passed");
        require(commitHash != bytes32(0), "Invalid commit hash");
        
        // Check player eligibility (O(1) lookup)
        bool isEligible = game.currentRound == 1 
            ? game.hasJoined[msg.sender] 
            : game.isRemainingPlayer[msg.sender];
        require(isEligible, "Player not eligible to commit in current round");
        require(game.currentRoundCommits[msg.sender].commitHash == bytes32(0), "Already committed this round");
        
        // Store commitment and increment counter
        game.currentRoundCommits[msg.sender] = CommitRecord({
            round: game.currentRound,
            commitHash: commitHash,
            timestamp: block.timestamp
        });
        game.currentCommitCount++; // Increment commit counter
        
        emit VoteCommitted(gameId, game.currentRound, msg.sender);
    }

    /**
     * @dev Set reveal deadline and transition to reveal phase
     * @param gameId The game ID
     * @param durationSeconds Duration in seconds for reveal phase
     */
    function setRevealDeadline(uint64 gameId, uint256 durationSeconds) external {
        Game storage game = games[gameId];
        
        require(game.gameId != 0, "Game does not exist");
        require(msg.sender == game.creator, "Only creator can set deadlines");
        require(game.state == GameState.CommitPhase, "Game must be in commit phase");
        require(durationSeconds > 0, "Duration must be positive");
        require(block.timestamp >= game.commitDeadline, "Commit deadline must have passed");
        
        // Check if anyone committed (O(1) check using counter)
        require(game.currentCommitCount > 0, "Cannot transition to reveal phase - no commits submitted");
        
        uint256 deadline = block.timestamp + durationSeconds;
        game.revealDeadline = deadline;
        game.state = GameState.RevealPhase;
        
        emit RevealDeadlineSet(gameId, game.currentRound, durationSeconds, deadline);
    }

    /**
     * @dev Submit a vote reveal (actual vote + salt for verification)
     * @param gameId The game ID
     * @param vote The actual vote (true = yes, false = no)
     * @param salt The salt used in commitment
     */
    function submitReveal(uint64 gameId, bool vote, bytes32 salt) external {
        Game storage game = games[gameId];
        
        require(game.gameId != 0, "Game does not exist");
        require(game.state == GameState.RevealPhase, "Reveal phase is not active");
        require(game.revealDeadline == 0 || block.timestamp <= game.revealDeadline, "Reveal deadline has passed");
        require(game.currentRoundCommits[msg.sender].commitHash != bytes32(0), "No commitment found for player");
        require(game.currentRoundReveals[msg.sender].timestamp == 0, "Already revealed this round");
        require(salt != bytes32(0), "Invalid salt");
        
        // Verify the reveal matches the commitment
        bytes32 calculatedHash = keccak256(abi.encodePacked(vote, salt));
        bytes32 commitment = game.currentRoundCommits[msg.sender].commitHash;
        
        if (calculatedHash != commitment) {
            emit InvalidReveal(gameId, game.currentRound, msg.sender);
            revert("Reveal does not match commitment");
        }
        
        // Store valid reveal
        game.currentRoundReveals[msg.sender] = RevealRecord({
            round: game.currentRound,
            vote: vote,
            salt: salt,
            timestamp: block.timestamp
        });
        
        // Update vote counts and reveal counter
        if (vote) {
            game.currentRoundYesVotes++;
        } else {
            game.currentRoundNoVotes++;
        }
        game.currentRevealCount++; // Increment reveal counter
        
        // Store vote in history
        game.playerVoteHistory[msg.sender].push(VoteRecord({
            round: game.currentRound,
            vote: vote,
            timestamp: block.timestamp
        }));
        
        emit VoteRevealed(gameId, game.currentRound, msg.sender, vote);
    }

    /**
     * @dev Process the current round - can be called by anyone after reveal deadline
     * @param gameId The game ID
     */
    function processRound(uint64 gameId) external {
        Game storage game = games[gameId];
        
        require(game.gameId != 0, "Game does not exist");
        require(game.state == GameState.RevealPhase, "Must be in reveal phase to process round");
        
        // Check if all remaining players have revealed OR deadline has passed (O(1) check)
        uint256 expectedReveals = game.currentRound == 1 ? game.players.length : game.remainingPlayers.length;
        uint256 actualReveals = game.currentRevealCount;
        
        require(
            actualReveals == expectedReveals || 
            (game.revealDeadline > 0 && block.timestamp >= game.revealDeadline),
            "All players must reveal or deadline must be passed"
        );
        
        game.state = GameState.ProcessingRound;
        
        // Determine minority vote
        bool minorityVote = game.currentRoundYesVotes <= game.currentRoundNoVotes;
        uint32 votesRemaining = minorityVote ? game.currentRoundYesVotes : game.currentRoundNoVotes;
        
        // Store round result
        game.roundResults[game.currentRound] = minorityVote;
        
        emit RoundCompleted(
            gameId,
            game.currentRound,
            game.currentRoundYesVotes,
            game.currentRoundNoVotes,
            minorityVote,
            votesRemaining
        );
        
        // Update remaining players - only those who voted minority vote continue
        address[] memory currentPlayers = game.currentRound == 1 ? game.players : game.remainingPlayers;
        
        // First, mark all current players as not remaining
        for (uint256 i = 0; i < currentPlayers.length; i++) {
            game.isRemainingPlayer[currentPlayers[i]] = false;
        }
        
        // Clear the array and rebuild with minority voters only
        delete game.remainingPlayers;
        
        for (uint256 i = 0; i < currentPlayers.length; i++) {
            address player = currentPlayers[i];
            if (game.currentRoundReveals[player].timestamp > 0 && 
                game.currentRoundReveals[player].vote == minorityVote) {
                game.remainingPlayers.push(player);
                game.isRemainingPlayer[player] = true; // Mark as remaining for next round
            }
        }
        
        // Check if game should end
        if (votesRemaining <= 2 || votesRemaining == 0) {
            game.winners = game.remainingPlayers;
            _endGame(gameId);
        } else {
            // Start next round
            game.currentRound++;
            game.currentRoundYesVotes = 0;
            game.currentRoundNoVotes = 0;
            game.currentCommitCount = 0; // Reset commit counter
            game.currentRevealCount = 0; // Reset reveal counter
            
            // Clear commit-reveal data for next round
            address[] memory playersToReset = game.remainingPlayers;
            for (uint256 i = 0; i < playersToReset.length; i++) {
                delete game.currentRoundCommits[playersToReset[i]];
                delete game.currentRoundReveals[playersToReset[i]];
            }
            
            // Reset deadlines - creator will set new ones manually
            game.commitDeadline = 0;
            game.revealDeadline = 0;
            
            // Start in zero phase for creator to set commit deadline
            game.state = GameState.ZeroPhase;
            
            emit NewRoundStarted(gameId, game.currentRound);
        }
    }

    /**
     * @dev Internal function to end the game and distribute prizes
     * @param gameId The game ID
     */
    function _endGame(uint64 gameId) internal {
        Game storage game = games[gameId];
        game.state = GameState.Completed;
        
        uint256 totalPrize = game.prizePool;
        uint256 platformFee = 0;
        
        if (totalPrize > 0) {
            // Calculate and send platform fee (2%)
            platformFee = (totalPrize * TOTAL_FEE_PERCENTAGE) / 10000;
            
            // Send platform fee
            (bool success,) = platformFeeRecipient.call{value: platformFee}("");
            require(success, "Platform fee transfer failed");
            game.prizePool -= platformFee;
            
            // Handle prize distribution
            if (game.winners.length > 0) {
                // Normal case: distribute remaining prizes to winners
                uint256 remainingPrize = game.prizePool;
                uint256 prizePerWinner = remainingPrize / game.winners.length;
                
                for (uint256 i = 0; i < game.winners.length; i++) {
                    address winner = game.winners[i];
                    (bool winnerSuccess,) = winner.call{value: prizePerWinner}("");
                    if (winnerSuccess) {
                        game.prizePool -= prizePerWinner;
                        emit PrizeDistributed(gameId, winner, prizePerWinner);
                    }
                    // If transfer fails, prize remains in contract - winner can claim later
                }
            } else {
                // No winners case: platform gets all remaining money (penalty for failed game)
                uint256 remainingPrize = game.prizePool;
                if (remainingPrize > 0) {
                    (bool success2,) = platformFeeRecipient.call{value: remainingPrize}("");
                    require(success2, "Additional fee transfer failed");
                    game.prizePool = 0;
                    platformFee += remainingPrize; // Update total platform fee for accurate logging
                }
            }
        }
        
        emit GameCompleted(gameId, game.currentRound, game.prizePool, platformFee);
    }

    // View functions

    /**
     * @dev Get basic game information
     */
    function getGameInfo(uint64 gameId) external view returns (
        uint64 id,
        string memory questionText,
        uint256 entryFee,
        address creator,
        uint8 state,
        uint8 currentRound,
        uint32 totalPlayers,
        uint32 currentYesVotes,
        uint32 currentNoVotes,
        uint256 prizePool,
        uint256 commitDeadline,
        uint256 revealDeadline
    ) {
        Game storage game = games[gameId];
        return (
            game.gameId,
            game.questionText,
            game.entryFee,
            game.creator,
            uint8(game.state),
            game.currentRound,
            game.totalPlayers,
            game.currentRoundYesVotes,
            game.currentRoundNoVotes,
            game.prizePool,
            game.commitDeadline,
            game.revealDeadline
        );
    }

    /**
     * @dev Get game players
     */
    function getGamePlayers(uint64 gameId) external view returns (address[] memory) {
        return games[gameId].players;
    }

    /**
     * @dev Get remaining players
     */
    function getRemainingPlayers(uint64 gameId) external view returns (address[] memory) {
        return games[gameId].remainingPlayers;
    }

    /**
     * @dev Get game winners
     */
    function getGameWinners(uint64 gameId) external view returns (address[] memory) {
        return games[gameId].winners;
    }

    /**
     * @dev Get user's game history
     */
    function getUserGameHistory(address player) external view returns (uint64[] memory) {
        return userGameHistory[player];
    }

    /**
     * @dev Get round result
     */
    function getRoundResult(uint64 gameId, uint8 round) external view returns (bool) {
        return games[gameId].roundResults[round];
    }

    /**
     * @dev Get player vote history
     */
    function getPlayerVoteHistory(uint64 gameId, address player) external view returns (VoteRecord[] memory) {
        return games[gameId].playerVoteHistory[player];
    }

    /**
     * @dev Check if player has committed in current round
     */
    function hasPlayerCommitted(uint64 gameId, address player) external view returns (bool) {
        return games[gameId].currentRoundCommits[player].commitHash != bytes32(0);
    }

    /**
     * @dev Check if player has revealed in current round
     */
    function hasPlayerRevealed(uint64 gameId, address player) external view returns (bool) {
        return games[gameId].currentRoundReveals[player].timestamp > 0;
    }

    /**
     * @dev Check if a player has joined a specific game
     */
    function hasPlayerJoined(uint64 gameId, address player) external view returns (bool) {
        return games[gameId].hasJoined[player];
    }

    /**
     * @dev Get total games created
     */
    function getTotalGamesCount() external view returns (uint64) {
        return nextGameId - 1;
    }
}