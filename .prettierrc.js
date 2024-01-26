let solOptions = {
    tabWidth: 4,
    printWidth: 100,
    singleQuote: false,
    bracketSpacing: false,
    compiler: '0.8.9',
}

module.exports = {
  semi: false,
  trailingComma: 'es5',
  singleQuote: true,
  printWidth: 80,
  tabWidth: 2,
  arrowParens: 'avoid',
  bracketSpacing: true,
  overrides: [
    { files: '*.sol', options: solOptions },
    { files: 'src/bridge/SequencerInbox.sol', options: { ...solOptions, compiler: '0.8.24' }},
    { files: 'src/rollup/BridgeCreator.sol', options: { ...solOptions, compiler: '0.8.24' }},
    { files: 'src/rollup/RollupCreator.sol', options: { ...solOptions, compiler: '0.8.24' }},
    { files: 'src/mocks/SequencerInboxStub.sol', options: { ...solOptions, compiler: '0.8.24' }},
    { files: 'src/libraries/GasRefundEnabled.sol', options: { ...solOptions, compiler: '0.8.24' }},
    { files: 'src/libraries/BlobDataHashReader.sol', options: { ...solOptions, compiler: '0.8.24' }},
    { files: 'src/rollup/ValidatorWallet.sol', options: { ...solOptions, compiler: '0.8.24' }},
    { files: 'src/rollup/ValidatorWalletCreator.sol', options: { ...solOptions, compiler: '0.8.24' }},
  ],
}
