import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-coverage";
import "@nomicfoundation/hardhat-verify";
require("dotenv").config();

const account: string = process.env.TEST_PRIVATE_KEY ?? "";
const ETHEREUM_API_KEY: string = process.env.ETHEREUM_API ?? "";
const POLYGON_API_KEY: string = process.env.POLYGON_API ?? "";
// const POLYGON_MAINNET: string = process.env.POLYGON_MAINNET ?? "";
// const ETHEREUM_MAINNET: string = process.env.ETHEREUM_MAINNET ?? "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 2000,
      },
    },
  },

  networks: {
    hardhat: {
      // forking: {
      //   url: ETHEREUM_MAINNET,
      // },
    },

    // mainnet: {
    //   url: process.env.ETHEREUM_MAINNET,
    //   accounts: [account],
    // },

    // polygon: {
    //   url: process.env.POLYGON_MAINNET,
    //   accounts: [account],
    // },

    amoy: {
      url: process.env.RPC_PROVIDER_AMOY,
      accounts: [account],
    },

    sepolia: {
      url: process.env.RPC_PROVIDER_SEPOLIA,
      accounts: [account],
    },
  },

  etherscan: {
    apiKey: {
      mainnet: ETHEREUM_API_KEY,
      polygon: POLYGON_API_KEY,
      sepolia: ETHEREUM_API_KEY,
      polygonAmoy: POLYGON_API_KEY,
    },
  },
};

export default config;
