// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ProgressiveAIBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 partialRevealDeadline;
        uint256 fullRevealDeadline;
        bool finalized;
        address winner;
        string[] answers;
        address[] participants;
        mapping(address => bytes32) commitments;
        mapping(address => bool) hasRevealed;
        mapping(address => bool) hasPartialReveal;
        mapping(address => bool) hasFullReveal;
        mapping(address => string) partialAnswers;
        mapping(address => string) fullAnswers;
        mapping(address => bytes32) salts;
        mapping(address => uint256) answerIndex;
        mapping(address => mapping(address => bool)) accessLog;
        uint256 revealCount;
        uint256 partialRevealCount;
        uint256 fullRevealCount;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 partialRevealDeadline;
        uint256 fullRevealDeadline;
        bool finalized;
        address winner;
        uint256 participantCount;
        uint256 answerCount;
        uint256 revealCount;
        uint256 partialRevealCount;
        uint256 fullRevealCount;
    }

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed id, address indexed participant);
    event AnswerRevealed(uint256 indexed id, address indexed participant, string answer);
    event PartialReveal(uint256 indexed id, address indexed participant, string partialAnswer);
    event FullReveal(uint256 indexed id, address indexed participant, string fullAnswer);
    event WinnerFinalized(uint256 indexed id, address indexed winner);
    event AccessLogged(uint256 indexed id, address indexed viewer, address indexed participant);

    modifier challengeExists(uint256 id) {
        require(challenges[id].owner != address(0), "Challenge does not exist");
        _;
    }

    modifier onlyCommitPhase(uint256 id) {
        require(block.timestamp <= challenges[id].commitDeadline, "Commit phase ended");
        _;
    }

    modifier onlyRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].commitDeadline, "Not reveal phase");
        require(block.timestamp <= challenges[id].revealDeadline, "Reveal phase ended");
        _;
    }

    modifier onlyPartialRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].revealDeadline, "Not partial reveal phase");
        require(block.timestamp <= challenges[id].partialRevealDeadline, "Partial reveal phase ended");
        _;
    }

    modifier onlyFullRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].partialRevealDeadline, "Not full reveal phase");
        require(block.timestamp <= challenges[id].fullRevealDeadline, "Full reveal phase ended");
        _;
    }

    modifier onlyAfterFullReveal(uint256 id) {
        require(block.timestamp > challenges[id].fullRevealDeadline, "Full reveal phase not over");
        _;
    }

    modifier onlyOwner(uint256 id) {
        require(msg.sender == challenges[id].owner, "Not challenge owner");
        _;
    }

    modifier onlyParticipant(uint256 id) {
        require(challenges[id].commitments[msg.sender] != 0, "Not a participant");
        _;
    }

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function createChallenge(
        string calldata prompt,
        uint256 commitDeadline,
        uint256 revealDuration,
        uint256 partialRevealDuration,
        uint256 fullRevealDuration
    ) external payable {
        require(msg.value > 0, "Reward must be > 0 RIT");
        require(commitDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");
        require(partialRevealDuration > 0, "Partial reveal duration must be > 0");
        require(fullRevealDuration > 0, "Full reveal duration must be > 0");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.reward = msg.value;
        c.commitDeadline = commitDeadline;
        c.revealDeadline = commitDeadline + revealDuration;
        c.partialRevealDeadline = c.revealDeadline + partialRevealDuration;
        c.fullRevealDeadline = c.partialRevealDeadline + fullRevealDuration;

        emit ChallengeCreated(id, msg.sender, msg.value);
    }

    function submitCommitment(uint256 id, bytes32 commitment) external 
        challengeExists(id)
        onlyCommitPhase(id)
    {
        Challenge storage c = challenges[id];
        require(c.commitments[msg.sender] == 0, "Already committed");

        c.commitments[msg.sender] = commitment;
        c.participants.push(msg.sender);

        emit CommitmentSubmitted(id, msg.sender);
    }

    function revealAnswer(
        uint256 id,
        string calldata answer,
        bytes32 salt
    ) external 
        challengeExists(id)
        onlyRevealPhase(id)
    {
        Challenge storage c = challenges[id];
        bytes32 commitment = c.commitments[msg.sender];
        require(commitment != 0, "No commitment found");
        require(!c.hasRevealed[msg.sender], "Already revealed");

        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, id));
        require(computed == commitment, "Commitment mismatch");

        c.hasRevealed[msg.sender] = true;
        c.answerIndex[msg.sender] = c.answers.length;
        c.answers.push(answer);
        c.salts[msg.sender] = salt;
        c.revealCount++;

        emit AnswerRevealed(id, msg.sender, answer);
    }

    function partialRevealAnswer(
        uint256 id,
        string calldata partialAnswer
    ) external 
        challengeExists(id)
        onlyPartialRevealPhase(id)
        onlyParticipant(id)
    {
        Challenge storage c = challenges[id];
        require(c.hasRevealed[msg.sender], "Must reveal first");
        require(!c.hasPartialReveal[msg.sender], "Already partially revealed");

        c.partialAnswers[msg.sender] = partialAnswer;
        c.hasPartialReveal[msg.sender] = true;
        c.partialRevealCount++;

        emit PartialReveal(id, msg.sender, partialAnswer);
    }

    function fullRevealAnswer(
        uint256 id,
        string calldata fullAnswer
    ) external 
        challengeExists(id)
        onlyFullRevealPhase(id)
        onlyParticipant(id)
    {
        Challenge storage c = challenges[id];
        require(c.hasRevealed[msg.sender], "Must reveal first");
        require(!c.hasFullReveal[msg.sender], "Already fully revealed");

        c.fullAnswers[msg.sender] = fullAnswer;
        c.hasFullReveal[msg.sender] = true;
        c.fullRevealCount++;

        emit FullReveal(id, msg.sender, fullAnswer);
    }

    function viewParticipantAnswer(
        uint256 id,
        address participant
    ) external view returns (string memory) {
        Challenge storage c = challenges[id];
        require(msg.sender == c.owner || msg.sender == participant, "Not authorized");
        require(c.hasRevealed[participant], "Participant not revealed");
        
        return c.answers[c.answerIndex[participant]];
    }

    function viewPartialReveal(
        uint256 id,
        address participant
    ) external view returns (string memory) {
        Challenge storage c = challenges[id];
        require(block.timestamp > c.partialRevealDeadline, "Partial reveal not available");
        require(msg.sender == c.owner || c.hasPartialReveal[participant], "Not authorized");
        return c.partialAnswers[participant];
    }

    function viewFullReveal(
        uint256 id,
        address participant
    ) external view returns (string memory) {
        Challenge storage c = challenges[id];
        require(block.timestamp > c.fullRevealDeadline, "Full reveal not available");
        require(msg.sender == c.owner || c.hasFullReveal[participant], "Not authorized");
        return c.fullAnswers[participant];
    }

    function finalizeWinner(uint256 id, uint256 winnerIndex) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterFullReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.revealCount > 0, "No revealed answers");
        require(winnerIndex < c.answers.length, "Invalid winner index");

        c.finalized = true;
        c.winner = c.participants[winnerIndex];

        payable(c.winner).transfer(c.reward);

        emit WinnerFinalized(id, c.winner);
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            reward: c.reward,
            commitDeadline: c.commitDeadline,
            revealDeadline: c.revealDeadline,
            partialRevealDeadline: c.partialRevealDeadline,
            fullRevealDeadline: c.fullRevealDeadline,
            finalized: c.finalized,
            winner: c.winner,
            participantCount: c.participants.length,
            answerCount: c.answers.length,
            revealCount: c.revealCount,
            partialRevealCount: c.partialRevealCount,
            fullRevealCount: c.fullRevealCount
        });
    }

    function getAnswers(uint256 id) external view returns (string[] memory) {
        require(msg.sender == challenges[id].owner || challenges[id].finalized, "Not authorized");
        return challenges[id].answers;
    }

    function hasCommitted(uint256 id, address participant) external view returns (bool) {
        return challenges[id].commitments[participant] != 0;
    }

    function hasRevealed(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasRevealed[participant];
    }

    function hasPartialReveal(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasPartialReveal[participant];
    }

    function hasFullReveal(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasFullReveal[participant];
    }
}
