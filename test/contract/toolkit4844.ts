import { execSync } from 'child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'fs'
import { tmpdir } from 'os'
import { join } from 'path'
import { ContractFactory, Signer, ethers } from 'ethers'
import * as http from 'http'
import { IReader4844, IReader4844__factory } from '../../build/types'
import { JsonRpcProvider } from '@ethersproject/providers'
import { bytecode as Reader4844Bytecode } from '../../out/yul/Reader4844.yul/Reader4844.json'

const wait = async (ms: number) =>
  new Promise(res => {
    setTimeout(res, ms)
  })

export class Toolkit4844 {
  public static DATA_BLOB_HEADER_FLAG = '0x50' // 0x40 | 0x10

  public static postDataToGeth(body: any): Promise<any> {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: '127.0.0.1',
        port: 8545,
        path: '/',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json;charset=UTF-8',
          'Content-Length': Buffer.byteLength(JSON.stringify(body)),
        },
      }

      const req = http.request(options, res => {
        let data = ''

        // Event emitted when a chunk of data is received
        res.on('data', chunk => {
          data += chunk
        })

        // Event emitted when the response is fully received
        res.on('end', () => {
          resolve(JSON.parse(data))
        })
      })

      // Handle any errors
      req.on('error', error => {
        reject(error)
      })

      // Send the POST data
      req.write(JSON.stringify(body))

      // Close the request
      req.end()
    })
  }

  public static async getTx(
    txHash: string
  ): Promise<ethers.providers.TransactionResponse> {
    const body = {
      method: 'eth_getTransactionByHash',
      params: [txHash],
      id: Date.now(),
      jsonrpc: '2.0',
    }
    return (await this.postDataToGeth(body))['result']
  }

  public static async getTxReceipt(
    txHash: string
  ): Promise<ethers.providers.TransactionReceipt> {
    const body = {
      method: 'eth_getTransactionReceipt',
      params: [txHash],
      id: Date.now(),
      jsonrpc: '2.0',
    }
    return (await this.postDataToGeth(body))['result']
  }

  public static async chainId(): Promise<any> {
    const body = {
      method: 'eth_chainId',
      params: [],
      id: Date.now(),
      jsonrpc: '2.0',
    }
    return (await this.postDataToGeth(body))['result']
  }

  public static isReplacementError(err: string) {
    const errRegex =
      /Error while sending transaction: replacement transaction underpriced:/
    const match = err.match(errRegex)
    return Boolean(match)
  }

  public static async waitUntilBlockMined(
    blockNumber: number,
    provider: JsonRpcProvider
  ) {
    while ((await provider.getBlockNumber()) <= blockNumber) {
      await wait(300)
    }
  }

  // Bytes one blob holds in cast's blob encoding (4096 field elements of 31 bytes).
  private static BLOB_CAPACITY = 4096 * 31

  public static async sendBlobTx(
    privKey: string,
    to: string,
    blobs: string[],
    data: string
  ) {
    // cast packs one payload into as many blobs as it needs, so fill every blob but the last to
    // capacity: the tx then carries exactly blobs.length blobs.
    const payloads = blobs.map((blob, i) => {
      const bytes = Buffer.from(blob.replace(/^0x/, ''), 'hex')
      return i < blobs.length - 1
        ? Buffer.concat([
            bytes,
            Buffer.alloc(this.BLOB_CAPACITY - bytes.length),
          ])
        : bytes
    })
    const dir = mkdtempSync(join(tmpdir(), 'blob-'))
    const blobPath = join(dir, 'blobs.bin')
    writeFileSync(blobPath, Buffer.concat(payloads))
    try {
      const res = execSync(
        `cast send --json --private-key 0x${privKey} --rpc-url http://127.0.0.1:8545 ` +
          `--gas-limit 1000000 --blob --eip4844 --path ${blobPath} ${to} ${data} 2>&1`
      ).toString()
      const txHash = JSON.parse(res).transactionHash as string
      const tx = await this.getTx(txHash)
      const blobCount = ((tx as any)['blobVersionedHashes'] as string[]).length
      if (blobCount !== blobs.length) {
        throw new Error(
          `blob tx carried ${blobCount} blobs, wanted ${blobs.length}`
        )
      }
      return txHash
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  }

  public static async deployReader4844(wallet: Signer): Promise<IReader4844> {
    const contractFactory = new ContractFactory(
      IReader4844__factory.abi,
      Reader4844Bytecode,
      wallet
    )
    const reader4844 = await contractFactory.deploy()
    await reader4844.deployed()

    return IReader4844__factory.connect(reader4844.address, wallet)
  }
}
