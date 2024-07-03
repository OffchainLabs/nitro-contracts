import { JsonRpcProvider } from '@ethersproject/providers'
import { L1Network, L2Network } from '@arbitrum/sdk'
import { execSync } from 'child_process'
import { Bridge__factory, RollupAdminLogic__factory } from '../build/types'

export function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

export const getLocalNetworks = async (
  l1Url: string,
  l2Url: string
): Promise<{
  l1Network: L1Network
  l2Network: Omit<L2Network, 'tokenBridge'>
}> => {
  const l1Provider = new JsonRpcProvider(l1Url)
  const l2Provider = new JsonRpcProvider(l2Url)
  let deploymentData: string

  let data = {
    bridge: '',
    inbox: '',
    'sequencer-inbox': '',
    rollup: '',
  }

  let sequencerContainer = execSync(
    'docker ps --filter "name=l3node" --format "{{.Names}}"'
  )
    .toString()
    .trim()

  deploymentData = execSync(
    `docker exec ${sequencerContainer} cat /config/l3deployment.json`
  ).toString()

  data = JSON.parse(deploymentData) as {
    bridge: string
    inbox: string
    ['sequencer-inbox']: string
    rollup: string
  }

  const rollup = RollupAdminLogic__factory.connect(data.rollup, l1Provider)
  const confirmPeriodBlocks = await rollup.confirmPeriodBlocks()

  const bridge = Bridge__factory.connect(data.bridge, l1Provider)
  const outboxAddr = await bridge.allowedOutboxList(0)

  const l1NetworkInfo = await l1Provider.getNetwork()
  const l2NetworkInfo = await l2Provider.getNetwork()

  const l1Network: L1Network = {
    blockTime: 10,
    chainID: l1NetworkInfo.chainId,
    explorerUrl: '',
    isCustom: true,
    name: 'EthLocal',
    partnerChainIDs: [l2NetworkInfo.chainId],
    isArbitrum: false,
  }

  const l2Network: Omit<L2Network, 'tokenBridge'> = {
    chainID: l2NetworkInfo.chainId,
    confirmPeriodBlocks: confirmPeriodBlocks.toNumber(),
    ethBridge: {
      bridge: data.bridge,
      inbox: data.inbox,
      outbox: outboxAddr,
      rollup: data.rollup,
      sequencerInbox: data['sequencer-inbox'],
    },
    explorerUrl: '',
    isArbitrum: true,
    isCustom: true,
    name: 'ArbLocal',
    partnerChainID: l1NetworkInfo.chainId,
    partnerChainIDs: [],
    blockTime: 1,
    retryableLifetimeSeconds: 7 * 24 * 60 * 60,
    nitroGenesisBlock: 0,
    nitroGenesisL1Block: 0,
    depositTimeout: 900000,
  }
  return {
    l1Network,
    l2Network,
  }
}
