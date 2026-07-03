# Test Plan – ProgressiveAIBounty

- Happy path: 2 participants commit → reveal → partial reveal → full reveal → finalize
- Cannot reveal before deadline (reverts)
- Cannot partial reveal before phase starts (reverts)
- Cannot full reveal before phase starts (reverts)
- Only owner can finalize (reverts for others)
