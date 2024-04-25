const hre = require("hardhat");
const fs = require('fs');

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());
    const TokenContract = await hre.ethers.getContractFactory("Token");
    const tokenContract = await TokenContract.deploy();
    await tokenContract.deployed();
    console.log(`tokenContract deployed at = ${tokenContract.address}`);
}

main()
    .then(() => process.exit(0))
    .catch(err => {
        console.error(err);
        process.exit(1);
    });
