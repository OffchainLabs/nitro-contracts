# Arbitrum Nitro Rollup Contracts

This is the package with the smart contract code that powers Arbitrum Nitro.
It includes the rollup and fraud proof smart contracts, as well as interfaces for interacting with precompiles.

For more information see https://developer.arbitrum.io/intro

For the deployed addresses of these contracts for Arbitrum chains see [https://docs.arbitrum.io/for-devs/dev-tools-and-resources/chain-info#core-contracts](https://docs.arbitrum.io/for-devs/dev-tools-and-resources/chain-info#core-contracts)

For the token bridge contracts see [https://github.com/OffchainLabs/token-bridge-contracts](https://github.com/OffchainLabs/token-bridge-contracts)

Compile these contracts locally by running

```bash
git clone https://github.com/offchainlabs/nitro-contracts
cd nitro-contracts
yarn install
yarn build
```

## License

Nitro is currently licensed under a [Business Source License](./LICENSE.md), similar to our friends at Uniswap and Aave, with an "Additional Use Grant" to ensure that everyone can have full comfort using and running nodes on all public Arbitrum chains.

The Additional Use Grant also permits the deployment of the Nitro software, in a permissionless fashion and without cost, as a new blockchain provided that the chain settles to either Arbitrum One or Arbitrum Nova.

For those that prefer to deploy the Nitro software either directly on Ethereum (i.e. an L2) or have it settle to another Layer-2 on top of Ethereum, the [Arbitrum Expansion Program (the "AEP")](https://docs.arbitrum.foundation/aep/ArbitrumExpansionProgramTerms.pdf) was recently established. The AEP allows for the permissionless deployment in the aforementioned fashion provided that 10% of net revenue is contributed back to the Arbitrum community in accordance with the requirements of the AEP.

## Contact

Discord - [Arbitrum](https://discord.com/invite/5KE54JwyTs)

Twitter: [Arbitrum](https://twitter.com/arbitrum)
