import { assert } from 'chai'
import { ethers } from 'hardhat'
import { hash as tsGlobalStateHash } from '../../contract/common/globalStateLib'

// The TypeScript GlobalState hash helper must agree with the on-chain GlobalStateLib.hash on the
// current layout (4 x bytes32 + 2 x u64). SimpleOneStepProofEntry's getMachineHash returns
// globalState.hash() directly for a FINISHED state, giving us an on-chain oracle without extra
// scaffolding. This locks the TS mirror to the contract and would catch the helper drifting from
// the committed layout (e.g. the MELStateHash/NextMsgHash bytes32 slots).
describe('GlobalState hash (TS vs Solidity)', function () {
  const keccak = (s: string) =>
    ethers.utils.keccak256(ethers.utils.toUtf8Bytes(s))

  const MAX_U64 = '18446744073709551615' // 2**64 - 1

  it('TS globalStateLib.hash matches on-chain GlobalStateLib.hash for populated states', async function () {
    const factory = await ethers.getContractFactory('SimpleOneStepProofEntry')
    const osp = await factory.deploy()
    await osp.deployed()

    const states = [
      // all-zero
      {
        bytes32Vals: [
          ethers.constants.HashZero,
          ethers.constants.HashZero,
          ethers.constants.HashZero,
          ethers.constants.HashZero,
        ],
        u64Vals: [0, 0],
      },
      // populated MEL slots: [BlockHash, SendRoot, MELStateHash, NextMsgHash], [MsgCount, ExecutedMsgCount]
      {
        bytes32Vals: [
          keccak('blockHash'),
          keccak('sendRoot'),
          keccak('melStateHash'),
          keccak('nextMsgHash'),
        ],
        u64Vals: [7, 5],
      },
      // boundary u64 values
      {
        bytes32Vals: [keccak('a'), keccak('b'), keccak('c'), keccak('d')],
        u64Vals: [MAX_U64, '12345'],
      },
    ]

    for (const state of states) {
      const onchain = await osp.getMachineHash({
        globalState: state,
        machineStatus: 1, // FINISHED
      })
      const ts = tsGlobalStateHash(state as any)
      assert.equal(
        onchain,
        ts,
        'TS globalStateLib.hash disagrees with on-chain GlobalStateLib.hash'
      )
    }
  })
})
