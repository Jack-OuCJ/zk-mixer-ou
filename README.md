# ZK Mixer (Noir & Foundry)

A privacy-focused mixer implementation using **Noir** for zero-knowledge circuits and **Foundry** for Ethereum smart contracts. This project demonstrates how to break the on-chain link between deposits and withdrawals using zk-SNARKs (UltraHonk).

## Features

- **Privacy**: Deposit ETH and withdraw it to a fresh address without revealing the link.
- **Zero-Knowledge Proofs**: Uses Noir circuits to prove membership in a Merkle Tree without revealing the leaf index.
- **UltraHonk**: Utilizes the UltraHonk proving system via Barretenberg.
- **Foundry Integration**: Full test suite in Solidity using `vm.ffi` to generate proofs via Node.js scripts.

## Prerequisites

Ensure you have the following installed:

- **Node.js** (v18+) & **npm**
- **Rust** (for Nargo)
- **Nargo** (Noir compiler)
- **bb** (Barretenberg CLI)
- **Foundry** (Forge, Cast, Anvil)

## Installation

1.  **Install Node.js dependencies:**
    ```bash
    npm install
    ```

2.  **Install Foundry dependencies:**
    ```bash
    cd contracts
    forge install
    ```

## Usage

### 1. Compile Circuits & Generate Verifier

The circuits are located in `circuits/`. You need to compile them and generate the Solidity verifier contract.

```bash
# Compile the Noir circuit
nargo compile

# Generate Verification Key (vk)
bb write_vk --oracle_hash keccak -b ./target/circuits.json -o ./target

# Generate Solidity Verifier
bb write_solidity_verifier -k ./target/vk -o ./target/Verifier.sol

# Copy the verifier to the contracts source directory
cp target/Verifier.sol contracts/src/Verifier.sol
```

### 2. Run Tests

The tests use `vm.ffi` to call Node.js scripts for generating commitments and proofs.

```bash
cd contracts
forge test -vvv
```

**Note:** `vm.ffi` requires permission to execute external commands. If you encounter permission issues, check your `foundry.toml` configuration or allow read/write access.

## Project Structure

- `circuits/`: Noir circuit source code (`src/main.nr`).
- `contracts/`: Solidity smart contracts and Foundry tests.
  - `src/Mixer.sol`: The main mixer contract.
  - `src/Verifier.sol`: The generated verifier contract.
  - `js-scripts/`: Helper scripts for generating proofs and commitments off-chain.
  - `test/`: Foundry test suite.
- `notes/`: Documentation and notes (including Chinese overview).

## How it Works

1.  **Deposit**: A user generates a `secret` and `nullifier`, computes the `commitment` (Poseidon hash), and sends it to the `Mixer` contract along with ETH.
2.  **Merkle Tree**: The contract adds the commitment to an on-chain Merkle Tree.
3.  **Withdraw**: The user generates a ZK proof showing they know the `secret` and `nullifier` for a commitment in the tree, without revealing which one.
4.  **Verification**: The contract verifies the proof and ensures the `nullifier` hasn't been used before, then releases the funds.
