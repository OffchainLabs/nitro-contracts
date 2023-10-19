import { execSync } from 'child_process'
import { ContractFactory, Signer, Wallet, ethers } from 'ethers'
import * as http from 'http'
import { IDataHashReader, IDataHashReader__factory } from '../../build/types'

const dataHashReaderJson = {
  _format: 'hh-sol-artifact-1',
  contractName: 'DataHashesReader',
  sourceName: 'src/bridge/DataHashesReader.yul',
  abi: [],
  bytecode:
    '0x603b80600a5f395ff3fe5f3560e01c63e83a2d8214600f57005b5f5b804990811560295760019160408260051b0152016011565b60409060205f528060205260051b015ff3',
  linkReferences: {},
  deployedLinkReferences: {},
}

const wait = async (ms: number) =>
  new Promise((res, rej) => {
    setTimeout(res, ms)
  })

export class Toolkit4844 {
  public static postDataToGeth(body: any): Promise<any> {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: 'localhost',
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

  public static async sendBlobTx(
    privKey: string,
    to: string,
    blobs: string[],
    data: string
  ) {
    const blobStr = blobs.reduce((acc, blob) => acc + ' -b ' + blob, '')
    const blobCommand = `docker run --network=nitro-testnode_default ethpandaops/goomy-blob:master blob-sender -p ${privKey} -r http://127.0.0.1:8545 -t ${to} -d ${data} --gaslimit 1000000${blobStr} 2>&1`
    const res = execSync(blobCommand).toString()
    const txHashRegex = /0x[a-fA-F0-9]{64}/
    const match = res.match(txHashRegex)
    if (match) {
      await wait(10000)
      return match[0]
    } else {
      throw new Error('Error sending blob tx:\n' + res)
    }
  }

  public static async deployDataHashReader(
    wallet: Signer
  ): Promise<IDataHashReader> {
    const contractFactory = new ContractFactory(
      dataHashReaderJson.abi,
      dataHashReaderJson.bytecode,
      wallet
    )
    const dataHashReader = await contractFactory.deploy()
    await dataHashReader.deployed()

    return IDataHashReader__factory.connect(dataHashReader.address, wallet)
  }
}
