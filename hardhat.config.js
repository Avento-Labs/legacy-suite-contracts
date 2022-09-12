require("dotenv").config();
require("@nomiclabs/hardhat-waffle");

module.exports = {
    networks: {
        hardhat: {
            seeds: [process.env.rinkeby_mnemonic],
            gas: 2100000,
        },
        rinkeby: {
            url: process.env.rinkeby_rpc_url,
            accounts: {
                mnemonic: process.env.rinkeby_mnemonic,
            },
            gas: 2100000,
            networkTimeOut: 1000000000000000,
        },
        maticmainnet: {
            url: process.env.matic_rpc_url,
            chainId: 137,
            seeds: [process.env.matic_mnemonic],
            gas: 2100000,
        },
    },
    solidity: {
        version: "0.8.15",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,
        },
    },
    paths: {
        sources: "./contracts",
        tests: "./test",
        cache: "./cache",
        artifacts: "./build",
    },
    mocha: {
        timeout: 20000,
    },
};
