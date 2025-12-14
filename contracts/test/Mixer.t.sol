// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IVerifier} from "../src/Verifier.sol";
import {Mixer} from "../src/Mixer.sol";
import {IncrementalMerkleTree} from "../src/IncrementalMerkleTree.sol";
import {Poseidon2} from "@poseidon/src/Poseidon2.sol";
import {HonkVerifier} from "../src/Verifier.sol";
import "forge-std/Test.sol";

contract MixerTest is Test {
    Mixer public mixer;    
    HonkVerifier public verifier;
    Poseidon2 public hasher;

    address public recipient = vm.addr(1);

    function setUp() public {
        verifier = new HonkVerifier();
        hasher = new Poseidon2();
        mixer = new Mixer(IVerifier(address(verifier)), 20, hasher);
    }
    
    function _getCommitment() public returns (bytes32 _secret, bytes32 _nullifier, bytes32 _commitment) {
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateCommitment.js";

        bytes memory result = vm.ffi(inputs);
        // Decode the ABI-encoded secret, nullifier, and commitment from ethers
        (_secret, _nullifier, _commitment) = abi.decode(result, (bytes32, bytes32, bytes32));
        
        return (_secret, _nullifier, _commitment);
    }

    function _getProof(bytes32 _secret, bytes32 _nullifier, address _recipient, bytes32[] memory _leaves) public returns (bytes memory _proof, bytes32 _root, bytes32 _nullifierHash) {
        string[] memory inputs = new string[](6 + _leaves.length);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateProof.js";
        inputs[3] = vm.toString(uint256(_secret));
        inputs[4] = vm.toString(uint256(_nullifier));
        inputs[5] = vm.toString(bytes32(uint256(uint160(_recipient))));
        for (uint i = 0; i < _leaves.length; i++) {
            inputs[6 + i] = vm.toString(uint256(_leaves[i]));
        }

        bytes memory result = vm.ffi(inputs);
        (_proof, _root, _nullifierHash) = abi.decode(result, (bytes, bytes32, bytes32));
        return (_proof, _root, _nullifierHash);
    }

    function testMakeDeposit() public {
        (,, bytes32 _commitment) = _getCommitment();
        vm.expectEmit(true, true, false, true);
        emit Mixer.Deposit(_commitment, 0, block.timestamp);
        mixer.deposit{value: mixer.DENOMINATION()}(_commitment);
    }

    function testMakeWithdrawal() public {
        (bytes32 _secret, bytes32 _nullifier, bytes32 _commitment) = _getCommitment();
        vm.expectEmit(true, true, false, true);
        emit Mixer.Deposit(_commitment, 0, block.timestamp);
        mixer.deposit{value: mixer.DENOMINATION()}(_commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = _commitment;

        // Record balances before withdrawal
        uint256 mixerBalanceBefore = address(mixer).balance;
        uint256 recipientBalanceBefore = recipient.balance;

        // create a proof for withdrawal
        (bytes memory _proof, bytes32 _root, bytes32 _nullifierHash) = _getProof(_secret, _nullifier, recipient, leaves);
        console.log("Proof generated, root:", vm.toString(_root));
        console.log("Nullifier hash:", vm.toString(_nullifierHash));

        // Expect withdrawal event
        vm.expectEmit(true, true, false, true);
        emit Mixer.Withdrawal(_nullifierHash, recipient, block.timestamp);
        
        // make a withdrawal
        mixer.withdraw(_proof, _root, _nullifierHash, payable(recipient));

        // Check balances after withdrawal
        uint256 mixerBalanceAfter = address(mixer).balance;
        uint256 recipientBalanceAfter = recipient.balance;

        // Verify balance changes
        assertEq(mixerBalanceBefore - mixerBalanceAfter, mixer.DENOMINATION(), "Mixer balance should decrease by DENOMINATION");
        assertEq(recipientBalanceAfter - recipientBalanceBefore, mixer.DENOMINATION(), "Recipient balance should increase by DENOMINATION");
        
        // Verify nullifier is marked as used
        assertTrue(mixer.s_nullifierHashes(_nullifierHash), "Nullifier should be marked as used");
    }

    function testAttackerCannotWithdraw() public {
        // Legitimate user makes a deposit
        (bytes32 _secret, bytes32 _nullifier, bytes32 _commitment) = _getCommitment();
        vm.expectEmit(true, true, false, true);
        emit Mixer.Deposit(_commitment, 0, block.timestamp);
        mixer.deposit{value: mixer.DENOMINATION()}(_commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = _commitment;

        // Attacker tries to generate a proof with their own address as recipient
        address attacker = vm.addr(666);
        
        // Attacker cannot create a valid proof because they don't have the secret/nullifier
        // Even if they try to call withdraw with their address, the proof won't verify
        // because the proof was generated with the legitimate recipient address
        
        // First, get a valid proof for the legitimate recipient
        (bytes memory _proof, bytes32 _root, bytes32 _nullifierHash) = _getProof(_secret, _nullifier, recipient, leaves);
        
        // Attacker tries to use this proof but with their own address
        // The proof will fail because it was created for the legitimate recipient address
        vm.expectRevert();
        mixer.withdraw(_proof, _root, _nullifierHash, payable(attacker));
        
        // Verify attacker did not receive any funds
        assertEq(attacker.balance, 0, "Attacker should not receive any funds");
    }
}