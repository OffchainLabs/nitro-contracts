# How to deploy the RollupCreator factory contract and create new rollup chains?

> [!IMPORTANT]
> The recommended way of creating new Arbitrum chains is through the Arbitrum Orbit SDK. Instructions are available in our [documentation portal](https://docs.arbitrum.io/launch-arbitrum-chain/arbitrum-chain-sdk-introduction). These instructions are targetted to readers who are familiar with the Nitro stack and the creation of Arbitrum chains.

This short guide includes instructions to deploy the `RollupCreator` factory contract, as well as create new rollup chains using it.

## 1. Setup project

Clone this repository

```shell
git clone https://github.com/offchainlabs/nitro-contracts
cd nitro-contracts
```

Checkout the appropriate release (e.g. `develop` or `v3.1.1`)

```shell
git checkout develop
```

Install dependencies and build

```shell
yarn install
yarn build:all
```

Make a copy of the .env-sample file

```shell
cp .env-sample .env
```

Choose the network that you're going to deploy the contracts to. If it's not present in [../hardhat.config.ts](../hardhat.config.ts), use the `custom` network.

Then set the environment variables needed.

To set the RPC and deployer private key to use, follow these instructions

```shell
# For any L1 network (mainnet, sepolia, holesky) we use an Infura endpoint, so set the key here
# For Arbitrum and Base networks, we use the public RPC
INFURA_KEY=

# For any mainnet network (mainnet, arb1, arbnova, base), use `MAINNET_PRIVKEY`
# For any testnet network (sepolia, holesky, arbsepolia, basesepolia), use `DEVNET_PRIVKEY`
MAINNET_PRIVKEY=
DEVNET_PRIVKEY=

# For any other network
CUSTOM_RPC_URL=
CUSTOM_PRIVKEY=
```

_Note: the additional env variables needed for each step are specified in the appropriate section._

## 2. Deploy the RollupCreator factory

Set the following environment variable:

```shell
# Owner of the RollupCreator factory contract, with ability to modify the templates after the first deployment
# (usually don't need to modify this value)
FACTORY_OWNER="0x000000000000000000000000000000000000dead"
```

Optionally, set these extra variables:

```shell
# When deploying on L1, use 117964; When deploying on L2, use 104857
# (defaults to 117964)
MAX_DATA_SIZE=117964

# Whether or not to verify the contracts deployed
# (defaults to false, i.e., verify the contracts)
DISABLE_VERIFICATION=true
```

_Note: if you choose to verify the contracts, follow the instructions in the section "Verification of contracts" below, to set the appropriate api key_

Finally deploy the RollupCreator factory contract and the templates, using the `--network` flag to specify hardhat network to use.

> [!NOTE]  
> The deployment script uses Create2 to deploy all contracts. If Arachnid's proxy is not deployed in the chain, you must deploy it first (follow instructions in its [github repository](https://github.com/Arachnid/deterministic-deployment-proxy/) to do so). If the proxy is deployed in a different address, you can specify it with the environment variable `CREATE2_FACTORY`.

```shell
yarn run deploy-factory --network (arbSepolia | arb1 | custom | ...)
```

The script will output all deployed addresses. Write down the address of the RollupCreator contract created, as you'll need it in the next step.

## 3. Create new rollup chains

Set the following environment variables:

```shell
# Address of the RollupCreator factory contract
ROLLUP_CREATOR_ADDRESS="0x"
# Address of the stake token to use for validation through the Rollup contract
# (this is usually set to the WETH token)
STAKE_TOKEN_ADDRESS="0x"
```

Additionally, if you're going to deploy a custom gas token chain, set the following variables:

```shell
# Address of the token contract in the parent chain, to use as the native gas token of your chain
FEE_TOKEN_ADDRESS="0x"
# Address of the fee token pricer to use for the fee token
# (see instructions in https://docs.arbitrum.io/launch-arbitrum-chain/configure-your-chain/common-configurations/use-a-custom-gas-token-rollup to understand how pricers work)
FEE_TOKEN_PRICER_ADDRESS="0x"
```

Optionally, set this extra variable:

```shell
# Whether or not to verify the contracts deployed
# (defaults to false, i.e., verify the contracts)
DISABLE_VERIFICATION=true
```

_Note: if you choose to verify the contracts, follow the instructions in the section "Verification of contracts" below, to set the appropriate api key_

Then, make a copy of the `config.example.ts` file to configure the initial parameters of your chain.

```shell
cp scripts/config.example.ts scripts/config.ts
```

Modify the initial parameters of your chain. Make sure all addresses are set to wallets that you own.

Finally, use the appropriate command to create your rollup chain, depending on the gas token of your chain.

If you'll use ETH as the gas token of your chain, call the following command, using the `--network` flag to specify hardhat network to use.

```shell
yarn run deploy-eth-rollup --network (arbSepolia | arb1 | custom | ...)
```

If you'll use a custom gas token for your chain, call the following command, using the `--network` flag to specify hardhat network to use.

```shell
yarn run deploy-erc20-rollup --network (arbSepolia | arb1 | custom | ...)
```

The script will output all deployed addresses and the block at which the transaction executed.

## Verification of contracts

If you choose to verify the deployed contracts, you'll also need to set the key to use Etherscan's API (or the appropriate network's block explorer).

```shell
# This key will be used against Etherscan's API (v2) on all supported networks,
# or against the API URL defined in `CUSTOM_ETHERSCAN_API_URL` when using a custom network
ETHERSCAN_API_KEY=

# For deployments on other networks
CUSTOM_CHAINID=
CUSTOM_ETHERSCAN_API_URL=
CUSTOM_ETHERSCAN_BROWSER_URL=
```

## TokenBridge deployment

To deploy a token bridge for your chain, follow the instructions in the [token-bridge-contracts](https://github.com/OffchainLabs/token-bridge-contracts/blob/main/docs/deployment.md) repository.
