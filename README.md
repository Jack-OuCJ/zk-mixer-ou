# ZK Mixer Project

- Deposit: users can deposit ETH into the mixer to break the connection between depositor and withdrawer.
- Withdraw: users will withdraw using a ZK proof (Noir - generated off-chain) of knowledge of their deposit.
- We will only allow users to deposit a fixed amount of ETH (0.001 ETH)

## Proof
- we need to check that the comnmitment is present in the merkle tree of commitments 
  - proposed root
  - Merkle proof
- check the nullifier hash match the one in the proof and has not been used before

### Private Inputs
- secret
- nullifier
- Merkle proof (intermediate nodes required to reconstruct the tree)
- Boolean to say whether node has an even index 

### Public Inputs
- proposed root 
- nullifier hash