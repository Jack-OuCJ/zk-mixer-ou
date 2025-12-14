import { Barretenberg, Fr, UltraHonkBackend } from "@aztec/bb.js";
import { Noir } from "@noir-lang/noir_js";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AbiCoder } from "ethers";
import fs from "fs";

// if add default, no need to big import
import { merkleTree, ZERO_VALUES } from "./merkleTree.js";

// ES modules don't have __dirname, so we need to create it
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const circuit = JSON.parse(
  fs.readFileSync(
    path.resolve(__dirname, "../../circuits/target/circuits.json"),
    "utf-8"
  )
);

export async function generateProof() {
    // get the inputs
    const inputs = process.argv.slice(2);
    console.error(`[DEBUG] Received ${inputs.length} arguments`);
    const bb = await Barretenberg.new();
    
    // Parse inputs - they come as decimal strings from Solidity vm.toString(uint256(...))
    // Convert to hex and use Fr.fromBuffer for proper field element handling
    const secretBigInt = BigInt(inputs[0]);
    const nullifierBigInt = BigInt(inputs[1]);
    console.error(`[DEBUG] secret=${secretBigInt}, nullifier=${nullifierBigInt}`);
    
    // Convert BigInt to 32-byte buffer (big-endian)
    const toBuffer32 = (bigint) => {
        const hex = bigint.toString(16).padStart(64, '0');
        return Buffer.from(hex, 'hex');
    };
    
    const secret = Fr.fromBuffer(toBuffer32(secretBigInt));
    const nullifier = Fr.fromBuffer(toBuffer32(nullifierBigInt));
    const nullifierHash = await bb.poseidon2Hash([nullifier]);
    console.error(`[DEBUG] nullifierHash=${nullifierHash.toString()}`);
    
    // recipient comes as hex string with 0x prefix
    const recipientHex = inputs[2].startsWith('0x') ? inputs[2].slice(2) : inputs[2];
    const recipient = Fr.fromBuffer(Buffer.from(recipientHex.padStart(64, '0'), 'hex'));
    console.error(`[DEBUG] recipient=${recipient.toString()}`);
    
    // leaves come as decimal strings
    const leaves = inputs.slice(3).map(leaf => {
        const leafBigInt = BigInt(leaf);
        return Fr.fromBuffer(toBuffer32(leafBigInt)).toString();
    });
    console.error(`[DEBUG] Processing ${leaves.length} leaves`);
    
    const tree = await merkleTree(leaves);

    const commitment = await bb.poseidon2Hash([nullifier, secret]);
    const commitmentStr = commitment.toString();
    const leafIndex = tree.getIndex(commitmentStr);
    console.error(`[DEBUG] commitment=${commitmentStr}, leafIndex=${leafIndex}`);
    if (leafIndex < 0) {
        throw new Error('Commitment not found in provided leaves (leafIndex < 0).');
    }
    const merkleProof = tree.proof(leafIndex);
    console.error(`[DEBUG] merkleProof.root=${merkleProof.root}, pathElements.length=${merkleProof.pathElements.length}`);
    
    try {
        const noir = new Noir(circuit);
        const honk = new UltraHonkBackend(circuit.bytecode, {threads: 1});
        
        // Noir expects string representations of field elements
        const input = {
            // Public inputs
            root: merkleProof.root,
            nullifier_hash: nullifierHash.toString(),
            recipient: recipient.toString(),

            // Private inputs
            secret: secret.toString(),
            nullifier: nullifier.toString(),
            merkle_proof: merkleProof.pathElements.map(i => i.toString()),
            // Circuit semantics: is_even[i] == true means the sibling is on the left
            // pathIndices: 0 means current node is on left (even), sibling on right
            // So we need to invert: is_even should be true when pathIndices is 1 (odd)
            is_even: merkleProof.siblingIndices.map(i => (i % 2 == 0)),
        };
        console.error(`[DEBUG] Circuit input prepared, merkle_proof.length=${input.merkle_proof.length}`);

        console.error(`[DEBUG] Executing noir.execute...`);
        const { witness } = await noir.execute(input);
        console.error(`[DEBUG] noir.execute completed, witness length=${witness?.length ?? 'unknown'}`);

        // Always use keccak to match on-chain verification
        console.error(`[DEBUG] Generating proof with keccak...`);
        const { proof } = await honk.generateProof(witness, { keccak: true });
        console.error(`[DEBUG] Proof generated, length=${proof?.length ?? 'unknown'}`);
        
        const abiCoder = new AbiCoder();
        const result = abiCoder.encode(
            ['bytes', 'bytes32', 'bytes32'],
            [proof, merkleProof.root, nullifierHash.toBuffer()]
        );
        console.error(`[DEBUG] Result encoded, length=${result?.length ?? 'unknown'}, result=${result}`);
        return result;
    } catch (err) {
        console.error("Error generating proof:", err);
        throw err;
    }
}

(async () => {
    try {
        const result = await generateProof();
        process.stdout.write(result);
        process.exit(0);
    } catch (err) {
        console.error('Error generating proof:', err);
        process.exit(1);
    }
})();