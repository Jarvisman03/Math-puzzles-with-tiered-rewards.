// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MathPuzzleRewards is ERC721URIStorage, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // Structs
    struct Puzzle {
        bytes32 questionHash;    // Hash of the puzzle question
        bytes32 answerHash;     // Hash of the puzzle answer
        uint256 difficulty;     // 1: Easy, 2: Medium, 3: Hard
        uint256 timeLimit;      // Time limit in seconds
        uint256 pointsReward;   // Points awarded for completion
        bool isActive;          // Whether puzzle is currently playable
    }

    struct PlayerStats {
        uint256 totalPoints;    // Total points earned
        uint256 puzzlesSolved;  // Number of puzzles completed
        uint256 currentTier;    // Current player tier
        uint256 lastPuzzleTime; // Timestamp of last puzzle attempt
    }

    // State variables
    mapping(uint256 => Puzzle) public puzzles;               // puzzleId => Puzzle
    mapping(address => PlayerStats) public playerStats;      // player => PlayerStats
    mapping(uint256 => string) public tierRewardURIs;       // tier => IPFS URI for tier NFT
    mapping(address => mapping(uint256 => bool)) public hasAttempted; // player => puzzleId => attempted

    uint256 public puzzleCount;
    uint256 public constant TIER_1_THRESHOLD = 100;  // Points needed for Tier 1
    uint256 public constant TIER_2_THRESHOLD = 250;  // Points needed for Tier 2
    uint256 public constant TIER_3_THRESHOLD = 500;  // Points needed for Tier 3

    // Events
    event PuzzleAdded(uint256 puzzleId, uint256 difficulty, uint256 timeLimit);
    event PuzzleSolved(address indexed player, uint256 puzzleId, uint256 pointsEarned);
    event TierUpgrade(address indexed player, uint256 newTier, uint256 tokenId);
    event RewardMinted(address indexed player, uint256 tokenId, uint256 tier);

    constructor() ERC721("Math Puzzle Rewards", "MPR") Ownable(msg.sender) {}

    // Admin functions
    function addPuzzle(
        string memory question,
        string memory answer,
        uint256 difficulty,
        uint256 timeLimit,
        uint256 pointsReward
    ) external onlyOwner {
        require(difficulty > 0 && difficulty <= 3, "Invalid difficulty level");
        require(timeLimit > 0, "Time limit must be positive");

        bytes32 questionHash = keccak256(abi.encodePacked(question));
        bytes32 answerHash = keccak256(abi.encodePacked(answer));

        puzzles[puzzleCount] = Puzzle({
            questionHash: questionHash,
            answerHash: answerHash,
            difficulty: difficulty,
            timeLimit: timeLimit,
            pointsReward: pointsReward,
            isActive: true
        });

        emit PuzzleAdded(puzzleCount, difficulty, timeLimit);
        puzzleCount++;
    }

    function setTierRewardURI(uint256 tier, string memory uri) external onlyOwner {
        require(tier > 0 && tier <= 3, "Invalid tier");
        tierRewardURIs[tier] = uri;
    }

    // Player functions
    function solvePuzzle(uint256 puzzleId, string memory answer) external nonReentrant {
        require(puzzleId < puzzleCount, "Puzzle does not exist");
        require(puzzles[puzzleId].isActive, "Puzzle is not active");
        require(!hasAttempted[msg.sender][puzzleId], "Already attempted this puzzle");

        Puzzle storage puzzle = puzzles[puzzleId];
        PlayerStats storage stats = playerStats[msg.sender];

        require(
            block.timestamp - stats.lastPuzzleTime >= puzzle.timeLimit,
            "Time limit not met"
        );

        // Verify answer
        require(
            keccak256(abi.encodePacked(answer)) == puzzle.answerHash,
            "Incorrect answer"
        );

        // Update player stats
        stats.totalPoints += puzzle.pointsReward;
        stats.puzzlesSolved++;
        stats.lastPuzzleTime = block.timestamp;
        hasAttempted[msg.sender][puzzleId] = true;

        emit PuzzleSolved(msg.sender, puzzleId, puzzle.pointsReward);

        // Check for tier upgrade
        _checkAndUpgradeTier(msg.sender);
    }

    // Internal functions
    function _checkAndUpgradeTier(address player) internal {
        PlayerStats storage stats = playerStats[player];
        uint256 newTier = 0;

        if (stats.totalPoints >= TIER_3_THRESHOLD && stats.currentTier < 3) {
            newTier = 3;
        } else if (stats.totalPoints >= TIER_2_THRESHOLD && stats.currentTier < 2) {
            newTier = 2;
        } else if (stats.totalPoints >= TIER_1_THRESHOLD && stats.currentTier < 1) {
            newTier = 1;
        }

        if (newTier > 0 && newTier > stats.currentTier) {
            _mintTierReward(player, newTier);
            stats.currentTier = newTier;
        }
    }

    function _mintTierReward(address player, uint256 tier) internal {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _safeMint(player, newTokenId);
        _setTokenURI(newTokenId, tierRewardURIs[tier]);

        emit RewardMinted(player, newTokenId, tier);
        emit TierUpgrade(player, tier, newTokenId);
    }

    // View functions
    function getPlayerStats(address player) external view returns (
        uint256 totalPoints,
        uint256 puzzlesSolved,
        uint256 currentTier
    ) {
        PlayerStats memory stats = playerStats[player];
        return (stats.totalPoints, stats.puzzlesSolved, stats.currentTier);
    }

    function validatePuzzleAnswer(uint256 puzzleId, string memory answer) public view returns (bool) {
        require(puzzleId < puzzleCount, "Puzzle does not exist");
        return keccak256(abi.encodePacked(answer)) == puzzles[puzzleId].answerHash;
    }
}