// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/ProgressiveAIBounty.sol";

contract ProgressiveAIBountyTest is Test {
    ProgressiveAIBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    uint256 challengeId;
    bytes32 aliceCommitment;
    bytes32 bobCommitment;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    string aliceAnswer = "Alice's full solution";
    string bobAnswer = "Bob's full solution";
    string alicePartial = "Alice's partial solution";
    string bobPartial = "Bob's partial solution";
    string aliceFull = "Alice's complete solution";
    string bobFull = "Bob's complete solution";
    uint256 reward = 1 ether;

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        bounty = new ProgressiveAIBounty();
        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", commitDeadline, 2 days, 2 days, 2 days);
        challengeId = 0;
        vm.stopPrank();
        aliceCommitment = keccak256(abi.encodePacked(aliceAnswer, aliceSalt, alice, challengeId));
        bobCommitment = keccak256(abi.encodePacked(bobAnswer, bobSalt, bob, challengeId));
    }

    function testFullFlow() public {
        // Commit
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.submitCommitment(challengeId, bobCommitment);
        vm.stopPrank();

        // Move to reveal phase (after commit deadline)
        vm.warp(block.timestamp + 1 days + 1);

        // Reveal
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAnswer(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        // Move to partial reveal phase (after reveal deadline)
        // revealDeadline = commitDeadline + revealDuration = 1 day + 2 days = 3 days
        vm.warp(block.timestamp + 2 days + 1);

        // Partial reveal
        vm.startPrank(alice);
        bounty.partialRevealAnswer(challengeId, alicePartial);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.partialRevealAnswer(challengeId, bobPartial);
        vm.stopPrank();

        // Move to full reveal phase (after partial reveal deadline)
        // partialRevealDeadline = revealDeadline + partialRevealDuration = 3 days + 2 days = 5 days
        vm.warp(block.timestamp + 2 days + 1);

        // Full reveal
        vm.startPrank(alice);
        bounty.fullRevealAnswer(challengeId, aliceFull);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.fullRevealAnswer(challengeId, bobFull);
        vm.stopPrank();

        // Move after full reveal deadline
        // fullRevealDeadline = partialRevealDeadline + fullRevealDuration = 5 days + 2 days = 7 days
        vm.warp(block.timestamp + 2 days + 1);

        // Finalize
        vm.startPrank(owner);
        bounty.finalizeWinner(challengeId, 1);
        vm.stopPrank();

        ProgressiveAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.finalized);
        assertEq(info.winner, bob);
        assertEq(bob.balance, 1 ether + reward);
    }

    function testCannotRevealBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.expectRevert("Not reveal phase");
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
    }

    function testCannotPartialRevealBeforeTime() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        // Try partial reveal before phase starts (still in reveal phase)
        vm.startPrank(alice);
        vm.expectRevert("Not partial reveal phase");
        bounty.partialRevealAnswer(challengeId, alicePartial);
        vm.stopPrank();
    }

    function testCannotFullRevealBeforeTime() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        bounty.partialRevealAnswer(challengeId, alicePartial);
        vm.stopPrank();

        // Try full reveal before phase starts (still in partial reveal phase)
        vm.startPrank(alice);
        vm.expectRevert("Not full reveal phase");
        bounty.fullRevealAnswer(challengeId, aliceFull);
        vm.stopPrank();
    }

    function testOnlyOwnerCanFinalize() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        bounty.partialRevealAnswer(challengeId, alicePartial);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        bounty.fullRevealAnswer(challengeId, aliceFull);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        vm.expectRevert("Not challenge owner");
        bounty.finalizeWinner(challengeId, 0);
        vm.stopPrank();
    }
}
