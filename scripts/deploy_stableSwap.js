const hre = require("hardhat");

async function main() {
    const StableSwap = await hre.ethers.getContractFactory("StableSwap");
    const stableSwap = await StableSwap.deploy();
    await stableSwap.deployed();
    try {
        console.log(`Successfully wrote exchange address ${stableSwap.address}`)

    } catch(error) {
        console.log(`Failed to write to file`);
        console.log(`Manually input exchange address: ${stableSwap.address}`);
    }
}

main()
    .then(() => process.exit(0))
    .catch(err => {
        console.error(err);
        process.exit(1);
    });
