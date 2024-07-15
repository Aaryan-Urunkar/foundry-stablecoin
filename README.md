# <p align=center >DeFi STABLECOIN</p>
## Introduction
<br>
<p >Stablecoins are cryptocurrency assets whose values are relatively stable and non-volatile. They are backed by certain colleteral which can exist off-chain(ex: USDC is pegged to USD ) or collateral which exists on chain(ex: UST which is backed by LUNA ). Stability is achieved chiefly in two major ways; by either making the asset governed or algorithmic. Governed method of stability makes it more centralized and the algorithmic method requires a permissionless algorithm to achieve stability. </p>
<br>
<p > To learn more, please read <a href="https://blog.chain.link/stablecoins-but-actually/"> this article by Chainlink.</a></p>
<br>
<br>
<p >In this project I aim to build a stablecoin which is pegged to the USD, algorithmic and exogenous.</p>

1. <p >Relative stability : Anchored or pegged => 1$</p>
2. <p >Stability mechanism(Minting) : Algorithmic (Decentralized)</p>
3. <p > Collateral : Exogenous(Crypto)</p>

<br>
<br>

## Getting Started

Welcome to the Solidity Stablecoin Project! This guide will help you set up and run the project on your local machine. Follow these steps to get started.

### Prerequisites

Before you begin, ensure you have the following installed:

- **Foundry**: A fast, modular toolkit for Ethereum application development written in Rust.

  If you don't have Foundry installed, you can install it by running:

  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```
- **Git** : Version control system to clone the repository.
            <br>
            You can download Git from <a href="https://git-scm.com/">here</a>.

### Installation

1. **Clone the Repository**

   First, clone the repository to your local machine:

   ```bash
   git clone https://github.com/Aaryan-Urunkar/foundry-stablecoin.git
   cd foundry-stablecoin    
   ```
2. **Install dependencies**

    Use Foundry to install all the required dependencies:

    ```bash
    forge install
    ```

### Configuration

1. **Create a `.env` File**

   In the root directory of the project, create a `.env` file to store your private variables. Add the following variables:

   ```ini
   PRIVATE_KEY=<your-sepolia-private-key>
   SEPOLIA_RPC_URL=<your-sepolia-rpc-url-from-alchemy>
   ETHERSCAN_API_KEY=<your-etherscan-api-key>
   ANVIL_RPC_URL=<your-anvil-rpc-url>
   ```
   Replace < your-sepolia-private-key> , < your-etherscan-api-key> , and < your-sepolia-rpc-url-from-alchemy> with your actual private values.

   Note: Ensure you do not share this file publicly as it contains sensitive information.

### Running the Project

With everything set up, you can now run the project. Use the following command to compile and test the smart contracts:

```bash
forge test
```
This will compile your contracts and run the tests to ensure everything is working correctly.


### Additional Commands

- **Compile Contracts:**

  ```bash
  forge build
  ```

-  **Deploy Contracts(Anvil localhost):**

  ```bash
  anvil
  ```

  ```bash
  forge script scripts/DeployDSC.s.sol --broadcast
  ```

-  **Deploy Contracts(Testnet):**

  ```bash
  source .env
  ```

  ```bash
  forge script scripts/DeployDSC.s.sol --broadcast --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --verify --etherscan-api-key $ETHERSCAN_API_KEY
  ```






