include "./lib/mimcsponge.circom";
template IfThenElse() {
    signal input condition;
    signal input true_value;
    signal input false_value;
    signal output out;

    signal tmp;
    tmp <== true_value - false_value;
    out <== false_value + tmp * condition;
}

template SelectiveSwitch() {
    signal input in0;
    signal input in1;
    signal input s;
    signal output out0;
    signal output out1;

    signal tmp;

    tmp <== in0-in1;

    out0 <== in0 - s*tmp;
    out1 <== in1 + s*tmp;
}

template HashLeftRight() {
    signal input in0;
    signal input in1;
    signal output out;

    component hasher = MiMCSponge(2, 220, 1);
    hasher.ins[0] <== in0;
    hasher.ins[1] <== in1;
    hasher.k <== 0;
    out <== hasher.outs[0];
}

template MerkleCheck(depth) {
    signal input root;
    signal input leaf;
    signal input sibling[depth];
    signal input direction[depth];
    signal output out;

    var tmp = leaf;

    component hashFunc0[depth];
    component switch[depth];

    for (var i=0; i<depth; i++) {
        switch[i] = SelectiveSwitch();
        switch[i].in0 <== tmp;
        switch[i].in1 <== sibling[i];
        switch[i].s <== direction[i];

        var in0 = switch[i].out0;
        var in1 = switch[i].out1;

        hashFunc0[i] = HashLeftRight();
        hashFunc0[i].in0 <== in0;
        hashFunc0[i].in1 <== in1;

        tmp = hashFunc0[i].out;
    }

    root === tmp;
}
