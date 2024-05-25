include "commitmentHash.circom";
include "merkleCheck.circom";

template Spend(depth) {
    ///public input
    signal input root;
    signal input recipient;
    signal input nullifierHash;

    ////private signal
    signal input nullifier;
    signal input secret;
    signal input sibling[depth];
    signal input direction[depth];

    component commitmentHash = CommitmentHash();

///tinh leaf va kiem tra nullifierHash co chinh xac khong
    commitmentHash.nullifier <== nullifier;
    commitmentHash.secret <== secret;
    commitmentHash.nullifierHash === nullifierHash;

///kiem tra merkle tree va path tu leaf den root
    component merkleTree = MerkleCheck(depth);
    merkleTree.root <== root;
    merkleTree.leaf <== commitmentHash.commitment;
    for (var i=0; i<depth; i++) {
        merkleTree.sibling[i] <== sibling[i];
        merkleTree.direction[i] <== direction[i];
    }

    signal recipientSquare;
    recipientSquare <== recipient * recipient;
}

component main {public [root, recipient, nullifierHash]} = Spend(32);
