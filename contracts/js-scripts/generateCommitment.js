import { Barretenberg, Fr } from '@aztec/bb.js';
import { AbiCoder } from 'ethers';

export async function generateCommitment() {
    const bb = await Barretenberg.new();

    const secret = Fr.random();
    const nullifier = Fr.random();

    const commitment = await bb.poseidon2Hash([nullifier, secret]);
    
    // Use ethers AbiCoder to encode secret, nullifier, and commitment
    const abiCoder = new AbiCoder();
    const encoded = abiCoder.encode(
        ['bytes32', 'bytes32', 'bytes32'],
        [secret.toBuffer(), nullifier.toBuffer(), commitment.toBuffer()]
    );
    return encoded;
}

(async () => {
    try {
        const result = await generateCommitment();
        process.stdout.write(result);
        process.exit(0);
    } catch (err) {
        console.error('Error generating commitment:', err);
        process.exit(1);
    }
})();