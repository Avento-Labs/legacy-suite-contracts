require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");

module.exports = {
  networks: {
    hardhat: {
      seeds: [process.env.rinkeby_mnemonic],
      gas: 2100000,
    },
    goerli: {
      url: process.env.goerli_rpc_url,
      chainId: 5,
      accounts: {
        mnemonic: process.env.goerli_mnemonic,
      },
      gas: 2100000,
      networkTimeOut: 100000000000,
    },
    mumbai: {
      url: process.env.mumbai_rpc_url,
      chainId: 80001,
      accounts: {
        mnemonic: process.env.mumbai_mnemonic,
      },
      gas: 2100000,
      networkTimeOut: 100000000000,
    },
    polygon: {
      url: process.env.matic_rpc_url,
      chainId: 137,
      accounts: {
        mnemonic: process.env.goerli_mnemonic,
      },
      gas: 2100000,
      networkTimeOut: 100000000000,
    },
  },
  solidity: {
    version: "0.8.15",
    settings: {
      metadata: {
        useLiteralContent: true,
      },
      optimizer: {
        enabled: true,
        runs: 10,
      },
      viaIR: true,
      outputSelection: {
        "*": {
          "*": [
            "abi",
            "evm.bytecode",
            "evm.deployedBytecode",
            "evm.methodIdentifiers",
            "metadata",
          ],
          "": ["id", "ast"],
        },
      },
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
  etherscan: {
    apiKey: "3CQMI6V1GX34DVAWFC8H4KAMB3W559PE1V",
    customChains: [
      {
        network: "mumbai",
        chainId: 80001,
        urls: {
          apiURL: "https://api-rinkeby.etherscan.io/api",
          browserURL: "https://rinkeby.etherscan.io",
        },
      },
    ],
  },
};
