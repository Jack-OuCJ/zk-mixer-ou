// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IVerifier} from "./Verifier.sol";
import {IncrementalMerkleTree} from "./IncrementalMerkleTree.sol";
import {Poseidon2} from "@poseidon/src/Poseidon2.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
contract Mixer is IncrementalMerkleTree, ReentrancyGuard{
    IVerifier public i_verifier;
    mapping(bytes32 => bool) public s_commitments;
    mapping(bytes32 => bool) public s_nullifierHashes;
    mapping(bytes32 => bool) public s_historicalRoots;
    bytes32[30] public s_recentRoots;
    uint256 public s_currentRootIndex;

    uint256 public constant DENOMINATION = 0.001 ether;

    event Deposit(bytes32 indexed commitment, uint32 indexed leafIndex, uint256 timestamp);
    event Withdrawal(bytes32 indexed nullifierHash, address indexed receiver, uint256 timestamp);

    error Mixer__CommitmentAlreadySubmitted(bytes32 commitment);
    error Mixer__DepositAmountNotCorrect(uint256 amountToDeposit, uint256 denomination);
    error Mixer__UnknownRoot(bytes32 root);
    error Mixer__NullifierHashAlreadyUsed(bytes32 nullifierHash);
    error Mixer__InvalidProof();
    error Mixer__TransferFailed();
    

    constructor(IVerifier _verifier, uint32 _merkelTreeDepth, Poseidon2 _hasher) IncrementalMerkleTree(_merkelTreeDepth, _hasher) {
        i_verifier = _verifier;
        // Initialize the first root
        s_recentRoots[0] = s_root;
        s_historicalRoots[s_root] = true;
        s_currentRootIndex = 0;
    }

    function info() public pure returns (string memory) {
        return "Mixer";
    }

    /// @notice Deposit funds into the mixer
    /// @param _commitment the poseiden commitment of the nullifier and secret
    function deposit(bytes32 _commitment) external payable nonReentrant {
        // check whether the commitment has already been used so we can prevent a deposit being added twice
        if (s_commitments[_commitment]) {
            revert Mixer__CommitmentAlreadySubmitted(_commitment);
        }
        
        if (msg.value != DENOMINATION) {
            revert Mixer__DepositAmountNotCorrect(msg.value, DENOMINATION);
        }

        // add the commitment to the on-chain incremental merkle tree containing all of the commitments
        uint32 insertedIndex = _insert(_commitment);
        s_commitments[_commitment] = true;
        
        // Update root history
        _updateRootHistory(s_root);
        
        // allow the user to send ETH and make sure it is of the correct fixe amount (denomination)
        // add the commitment to a data structure containing all of the commitments
        emit Deposit(_commitment, insertedIndex, block.timestamp);
    }

    /// @notice Withdraw funds from the mixer in a private way
    /// @param _proof the zkSNARK proof that user has the right to withdraw
    /// @param root the merkle root used in the proof
    /// @param _nullifierHash the nullifier hash to prevent double spending
    /// @param receiver the address to receive the withdrawn funds
    function withdraw(bytes memory _proof, bytes32 root, bytes32 _nullifierHash, address payable receiver) external nonReentrant {
        // Check if root is in the recent 30 historical roots
        if (!s_historicalRoots[root]) {
            revert Mixer__UnknownRoot(root);
        }
        
        // Check if nullifier has already been used
        if (s_nullifierHashes[_nullifierHash]) {
            revert Mixer__NullifierHashAlreadyUsed(_nullifierHash);
        }
        
        // Construct public inputs: root, nullifier_hash, receiver
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = root;
        publicInputs[1] = _nullifierHash;
        publicInputs[2] = bytes32(uint256(uint160(address(receiver))));
        
        // Verify zkSNARK proof
        bool isValidProof = i_verifier.verify(_proof, publicInputs);
        if (!isValidProof) {
            revert Mixer__InvalidProof();
        }
        
        // Mark nullifier as used to prevent double spending
        s_nullifierHashes[_nullifierHash] = true;
        
        // Transfer funds to receiver
        (bool success, ) = receiver.call{value: DENOMINATION}("");
        if (!success) {
            revert Mixer__TransferFailed();
        }
        
        emit Withdrawal(_nullifierHash, receiver, block.timestamp);
    }
    
    /// @notice Update the historical roots mapping
    /// @param newRoot the new root to add to history
    function _updateRootHistory(bytes32 newRoot) internal {
        // Update index (cycle through 0-29)
        s_currentRootIndex = (s_currentRootIndex + 1) % 30;
        
        // If current position has an old root, remove it from mapping
        bytes32 oldRoot = s_recentRoots[s_currentRootIndex];
        if (oldRoot != bytes32(0)) {
            s_historicalRoots[oldRoot] = false;
        }
        
        // Add new root
        s_recentRoots[s_currentRootIndex] = newRoot;
        s_historicalRoots[newRoot] = true;
    }
}
