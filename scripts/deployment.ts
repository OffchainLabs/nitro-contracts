import { ethers } from "hardhat";
import { ContractFactory, Contract, providers, Wallet } from "ethers";
import "@nomiclabs/hardhat-ethers";


async function deployContract(contractName: string, signer: any): Promise<Contract> {
  const factory: ContractFactory = await ethers.getContractFactory(contractName);
  const connectedFactory: ContractFactory = factory.connect(signer);
  const contract: Contract = await connectedFactory.deploy();
  await contract.deployTransaction.wait();
  console.log(`New ${contractName} created at address:`, contract.address);
  return contract;
}

async function deployAllContracts(signer: any): Promise<Record<string, Contract>> {
  const bridgeCreator = await deployContract("BridgeCreator", signer);
  const prover0 = await deployContract("OneStepProver0", signer);
  const proverMem = await deployContract("OneStepProverMemory", signer);
  const proverMath = await deployContract("OneStepProverMath", signer);
  const proverHostIo = await deployContract("OneStepProverHostIo", signer);
  const OneStepProofEntryFactory: ContractFactory = await ethers.getContractFactory("OneStepProofEntry");
  const OneStepProofEntryFactoryWithDeployer: ContractFactory = OneStepProofEntryFactory.connect(signer);
  const osp: Contract = await OneStepProofEntryFactoryWithDeployer.deploy(
    prover0.address,
    proverMem.address,
    proverMath.address,
    proverHostIo.address
  );
  await osp.deployTransaction.wait();
  console.log("New osp created at address:", osp.address);
  const challengeManager = await deployContract("ChallengeManager", signer);
  const rollupAdmin = await deployContract("RollupAdminLogic", signer);
  const rollupUser = await deployContract("RollupUserLogic", signer);
  const validatorUtils = await deployContract("ValidatorUtils", signer);
  const validatorWalletCreator = await deployContract("ValidatorWalletCreator", signer);
  const rollupCreator = await deployContract("RollupCreator", signer);
  return {
    bridgeCreator,
    prover0,
    proverMem,
    proverMath,
    proverHostIo,
    osp,
    challengeManager,
    rollupAdmin,
    rollupUser,
    validatorUtils,
    validatorWalletCreator,
    rollupCreator,
  };
}

async function main() {
  // Get the signer (account) to deploy the contract
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("Private key is not defined");
  }

  const providerAPI = process.env.RPC_URL;
  if (!providerAPI) {
    throw new Error("RPC URL is not defined");
  }

  const provider = new providers.JsonRpcProvider(providerAPI)
  const signer = new Wallet(privateKey, provider)

  try {
    const contracts = await deployAllContracts(signer);
    
    // Call setTemplates with the deployed contract addresses
    console.log("Waiting for the Template to be set on the Rollup Creator")
    await contracts.rollupCreator.setTemplates(
      contracts.bridgeCreator.address,
      contracts.osp.address,
      contracts.challengeManager.address,
      contracts.rollupAdmin.address,
      contracts.rollupUser.address,
      contracts.validatorUtils.address,
      contracts.validatorWalletCreator.address
      , {gasLimit: ethers.BigNumber.from("15000000")}
    );
    console.log("Template is set on the Rollup Creator")
    // Define the configuration for the createRollup function
    const rollupConfig = {
      confirmPeriodBlocks: 10,
      extraChallengeTimeBlocks: 10,
      stakeToken: ethers.constants.AddressZero,
      baseStake: ethers.utils.parseEther("1"),
      wasmModuleRoot: ethers.constants.HashZero,
      owner: signer.address,
      loserStakeEscrow: ethers.constants.AddressZero,
      chainId: 5,
      chainConfig:ethers.constants.HashZero,
      genesisBlockNum: 0,
      sequencerInboxMaxTimeVariation: {
        delayBlocks: 10,
        futureBlocks: 10,
        delaySeconds: 60,
        futureSeconds: 60,
      },
    };
    

    // Call the createRollup function
    console.log("Calling createRollup to generate a new rollup ...")
    const createRollupTx = await contracts.rollupCreator.createRollup(rollupConfig, {gasLimit: ethers.BigNumber.from("15000000")});
    const createRollupReceipt = await createRollupTx.wait();
    const rollupCreatedEvent = createRollupReceipt.events?.find(
      (event: { event: string }) => event.event === "RollupCreated"
      );

      if (rollupCreatedEvent) {
        const rollupAddress = rollupCreatedEvent.args?.rollupAddress;
        console.log("Congratulations! 🎉🎉🎉 New rollup created at address:", rollupAddress);
      } else {
        console.error("RollupCreated event not found");
      }
  
    } catch (error) {
      console.error("Deployment failed:", error instanceof Error ? error.message : error);
    }
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error: Error) => {
      console.error(error);
      process.exit(1);
    });
