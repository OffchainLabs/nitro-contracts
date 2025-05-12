import { JsonRpcProvider } from '@ethersproject/providers'

export type CreatorTemplates = {
  eth: {
    bridge: string
    sequencerInbox: string
    delayBufferableSequencerInbox: string
    inbox: string
    rollupEventInbox: string
    outbox: string
  }
  erc20: {
    bridge: string
    sequencerInbox: string
    delayBufferableSequencerInbox: string
    inbox: string
    rollupEventInbox: string
    outbox: string
  }
  rollupUserLogic: string
  rollupAdminLogic: string
  challengeManagerTemplate: string
  osp: string
  rollupCreator: string
}

export const templates: {
  [key: number]: CreatorTemplates
} = {
  // Ethereum
  1: {
    eth: {
      bridge: '0x677ECf96DBFeE1deFbDe8D2E905A39f73Aa27B89',
      sequencerInbox: '0x93dCfC7E658050c80700a6eB7FAF12efaCF5BF76',
      delayBufferableSequencerInbox:
        '0xE4bE5495054fE4fa4Ea5972219484984927681E3',
      inbox: '0x9C4ce5EF20F831F4e7fEcf58aAA0Cda8d3091c35',
      rollupEventInbox: '0x7b6784fbd233EDB47E11eA4e7205fC4229447662',
      outbox: '0x186267690cb723d72A7EDBC002476E23D694cB33',
    },
    erc20: {
      bridge: '0x81be1Bf06cB9B23e8EEDa3145c3366A912DAD9D6',
      sequencerInbox: '0xe154a8d54e39Cd8edaEA85870Ea349B82B0E4eF4',
      delayBufferableSequencerInbox:
        '0x6F2E7F9B5Db5e4e9B5B1181D2Eb0e4972500C324',
      inbox: '0xD210b64eD9D47Ef8Acf1A3284722FcC7Fc6A1f4e',
      rollupEventInbox: '0x0d079b22B0B4083b9b0bDc62Bf1a4EAF4a95bDEe',
      outbox: '0x17E0C5fE0dFF2AE4cfC9E96d9Ccd112DaF5c0386',
    },
    rollupUserLogic: '0xA4892FFE3Deab25337D7D1A5b94b35dABa255451',
    rollupAdminLogic: '0x16aD566aaa05fe6977A033DE2472c05C84CAB724',
    challengeManagerTemplate: '0x93069fFd7730733eCfd57A0D2D528CF686248524',
    osp: '0x91cB57F200Bd5F897E41C164425Ab4DB0991A64f',
    rollupCreator: '0x43698080f40dB54DEE6871540037b8AB8fD0AB44',
  },

  // Sepolia
  11155111: {
    eth: {
      bridge: '0x331Edb39Eb823602484cD9F28bBC34cE4B9e76D9',
      sequencerInbox: '0x9a4332b77d150AB19388e7F01B686De91a3Eadf1',
      delayBufferableSequencerInbox:
        '0x6F753199ebe6aAb140838185c7D5ef17b46f7f88',
      inbox: '0x10cf5c20F6b774dBDC68FAa58dE00406cfB07dc7',
      rollupEventInbox: '0x048506cA2683d137C25a34fE055339CE522Ddd00',
      outbox: '0x829856Cf500eA1cA32eB922b73c6872250682E28',
    },
    erc20: {
      bridge: '0xE46b560190Aa928fBCE2AF3060bC655EBD42C078',
      sequencerInbox: '0xB3748F67a36C4e006935AB96bCcF48E0732b1626',
      delayBufferableSequencerInbox:
        '0xfA93a2dcdE904fcF60233bA820336cbd71DB253B',
      inbox: '0xF3dF0Ed5B5a205df214d04DAEE9d9b5621AD83bA',
      rollupEventInbox: '0xfE91F555Ce6892C4D357Be2fBC6d2f485072a39f',
      outbox: '0x2f61CF4C5C57026AA74d41F254147e931b0b4314',
    },
    rollupUserLogic: '0x8c7ff54b854E40b52192C7eE89235d41f2d7fC58',
    rollupAdminLogic: '0xEC81CC24cebe8511CD1B742Ff910b447FeB9dF66',
    challengeManagerTemplate: '0x6B21677CeAd8bF6526d4A27D144579c9eB46f0eB',
    osp: '0x1B9bd7B42516220f7A3e8a620Df7045b9b9A5ef1',
    rollupCreator: '0x687Bc1D23390875a868Db158DA1cDC8998E31640',
  },

  // Arbitrum One
  42161: {
    eth: {
      bridge: '0x81F6f682cA9bB29D759ce12d7067E1c6EF533096',
      sequencerInbox: '0xd86D418d881fd718fa197e399bf74Cdd61DD3acf',
      delayBufferableSequencerInbox:
        '0xfEB2537afD8519d16d0CcEa741A70f97f3D4288B',
      inbox: '0xDD262dfDf2FCe29696f54eC5bB82C6994Ec2F639',
      rollupEventInbox: '0xf4d69939895E5f1d1ddCa96E5f93A878c80368c3',
      outbox: '0x4ca08847418DE7860a6da0De2e5536F1Cd78458A',
    },
    erc20: {
      bridge: '0x31127A9c0308d8E3F6db5158a14aD674f22946d7',
      sequencerInbox: '0x2aB445728A7db4fB767457383cA23396a4B5611A',
      delayBufferableSequencerInbox:
        '0xC08A4543b011fd4f1EfC9e26521F4e157433b3b1',
      inbox: '0x08b1395a2Ee51073d6B9ebF9E97FBeb09dcAcAf1',
      rollupEventInbox: '0x9fD20D42Cf52B1A0dEf8e95AD8d2E92B58ECa51B',
      outbox: '0x99761fAc22FcE23498F8004ac4025F822fEdce95',
    },
    rollupUserLogic: '0x56411606380fD9eF28DB1AAc3897Bd4a24F26606',
    rollupAdminLogic: '0x8dA371823A4937e5F371B7b53876Ee34d5d5E520',
    challengeManagerTemplate: '0x1Ef281CD6BD48affD9C44Cb590858FCfF92DE821',
    osp: '0x61006c8566fac9a3315F646dA4624C00BbCF15E4',
    rollupCreator: '0xB90e53fd945Cd28Ec4728cBfB566981dD571eB8b',
  },

  // Arbitrum Nova
  42170: {
    eth: {
      bridge: '0x31c8DC074d8a31Cdd33925405719931457Ed61f4',
      sequencerInbox: '0x9Bb78F4d5fD55c576FFe2aA9B71F1e441163ADB9',
      delayBufferableSequencerInbox:
        '0x782BC330EA15c57Fc0e3D4959C2f8A38278703E8',
      inbox: '0xD3FCBcCC2937495E70091d8Fd971A04Ee209cf9c',
      rollupEventInbox: '0xe20067C07d31cc67463A1A6f924FacE8440e9723',
      outbox: '0x466AA18cE75f1a3039D4C06A3c31786d0d0386c8',
    },
    erc20: {
      bridge: '0x5F89646f93E360217AD7caD73a44298aBC4aCA9A',
      sequencerInbox: '0xd35dCCD471CB5136004DA35660E0573B6cd791d9',
      delayBufferableSequencerInbox:
        '0xd9E17C6012A50F8725aCDA0196Cecaa40657e8cB',
      inbox: '0x51882B52bcc3EF8008f9F7772B0229eA2551FDdc',
      rollupEventInbox: '0x234e937F1a2926737b0084Fb7498772579497735',
      outbox: '0x3De02cf69192f4805edE47d7fA5efa614c5A6593',
    },
    rollupUserLogic: '0xA6D1cE7210353E431CE79f41BcFA9Ea3Ae507b98',
    rollupAdminLogic: '0x3930AD9a21dA38E63d52B43b0c530CB0AACcB389',
    challengeManagerTemplate: '0xD3dE403eADdf791104918E9C9336B434AE7DDA01',
    osp: '0x09fDA6447fA7758EA9245ac78Ca3c9ba68CBfd3d',
    rollupCreator: '0xF916Bfe431B7A7AaE083273F5b862e00a15d60F4',
  },

  // Arbitrum Sepolia
  421614: {
    eth: {
      bridge: '0x860b23D7CD5797274D6BE385F6A629C734DFB448',
      sequencerInbox: '0x72198537ffabDc70dc7a8c1A0B7532BA2eadCBEd',
      delayBufferableSequencerInbox:
        '0x23Cb9fca677B5cf04D859D5d98aDc93016C97EC4',
      inbox: '0x476B0126252E56E103918FFf6eD7eb80Ad97Ddbb',
      rollupEventInbox: '0x62dD65218029D0263eC328Ee6A218b957670b407',
      outbox: '0x0aee0473359b6690858F009fB5628E967fdb4124',
    },
    erc20: {
      bridge: '0x646dE495dca9E006760a64D19Df01369B42f862a',
      sequencerInbox: '0xd70Ee45dFe94CFDf7c05231cc87F77C541a32340',
      delayBufferableSequencerInbox:
        '0x968306A79555234Fb796090479df3E0F805cD32A',
      inbox: '0x975c02Cd7d879602638068F3edB1bda092e43bfB',
      rollupEventInbox: '0x0b0731c4C66D5805b55d8BD0086546248510449B',
      outbox: '0xD5f920B14F5EDA221776F5FeE948e36DffE43c5D',
    },
    rollupUserLogic: '0xe9F561c87E1289C5eA60814f522922a1619897AE',
    rollupAdminLogic: '0x7FA087B469E26B653F3B495c537a8796B42AD883',
    challengeManagerTemplate: '0x22DD61cF5e1f19A4D98C08478E2f83DFb3FCe44C',
    osp: '0x61287c070a7281165666D367953f9A12c7616550',
    rollupCreator: '0x5F45675AC8DDF7d45713b2c7D191B287475C16cF',
  },

  // Base
  8453: {
    eth: {
      bridge: '0x88B1f445e0048809789af7CF6f227Dc0f4febCFd',
      sequencerInbox: '0x9Eaa71Ce832890BFdD71D1E3e78f967d2Cf527ea',
      delayBufferableSequencerInbox:
        '0xe0978394BEe15a49583fF833a80Bd426c17B68e4',
      inbox: '0xEb35A5E1B0FdBa925880A539Eac661907d43Ee07',
      rollupEventInbox: '0x96891cfc4D53e091c7114F8a6e0a72664874Dd42',
      outbox: '0xa5aBADAF73DFcf5261C7f55420418736707Dc0db',
    },
    erc20: {
      bridge: '0xD2d9A5662B03518f32bFd0a7f4D958e3F33D2125',
      sequencerInbox: '0x7f6DBaEd9905C3b01030D3Ad5AA93846EcbBFa44',
      delayBufferableSequencerInbox:
        '0x51dEDBD2f190E0696AFbEE5E60bFdE96d86464ec',
      inbox: '0xb040b105A4a0C7a9CC290164AcCBC32855368322',
      rollupEventInbox: '0x7ed9C3A779BE8b742AbFC17a2F15353ecBcE3e00',
      outbox: '0x964177232be7C9e530054B3274b8B9D332b24Df5',
    },
    rollupUserLogic: '0x93B1A8c9F084FBe7972BAea73535bed3d32748c6',
    rollupAdminLogic: '0x796822909dcefDc433da071c7f75001452310a67',
    challengeManagerTemplate: '0xaf58472D08D7dBCCC73D5f58D26b2bD9Ef43A5c2',
    osp: '0x76600101E42Dd9355D29741288407923268C06ed',
    rollupCreator: '0xDbe3e840569a0446CDfEbc65D7d429c5Da5537b7',
  },

  // Base Sepolia
  84532: {
    eth: {
      bridge: '0x0488026f3404888F199A14EDcf8B3D3ba56E069E',
      sequencerInbox: '0xB6B95DB97fCb2202D48D92E0ce0dd5ce034379C5',
      delayBufferableSequencerInbox:
        '0xA1Ed88af9d915e4E387bdb5019Dc8C3C545fD014',
      inbox: '0xC2Ab275C258Edd3846CB44FA4110b8669b54e7A6',
      rollupEventInbox: '0x99089435Cd97B2f643B9721BeFcf63750e181578',
      outbox: '0x723B45e3233652F64a399C260380AFC4a33F3f9D',
    },
    erc20: {
      bridge: '0xd8953b37A3050aA519Dc3a57505FC37c73A72d0f',
      sequencerInbox: '0x20B2b541f3382BFB11310Bd53D1C76b015E54775',
      delayBufferableSequencerInbox:
        '0xB14D2319BABDd03577f3697340323219cCdA2641',
      inbox: '0x5594a90b3d150f06a16dB5866f47B7F528D35D74',
      rollupEventInbox: '0x66e62BdeBCCEa538bA9938225a885a5c4D59C117',
      outbox: '0xcBfA2F189DCA8526Ec0266dB79d6F789b1b32e9e',
    },
    rollupUserLogic: '0xD45D3C6a11a90a6c91c45E8086076a86ACd5d14c',
    rollupAdminLogic: '0x32362a2884232d05df32feDeb18a9aBb89A8cf7b',
    challengeManagerTemplate: '0x409CcfCeDF546DE7B855191cC5B7f6EF318d406C',
    osp: '0x71f1904d9018087722fbF8EBB03be149A59405E2',
    rollupCreator: '0x70cA29dA3B116A2c4A267c549bf7947d47f41e22',
  },

  // Nitro testnode
  1337: {
    eth: {
      bridge: '0x43202b1afae6c0c2B2a04dA9030434D73579A0FF',
      sequencerInbox: '0x773D62Ce1794b11788907b32F793e647A4f9A1F7',
      delayBufferableSequencerInbox:
        '0x571fa696c2c66A85D0801C703E0ce4666B66D2af',
      inbox: '0x47821a1c6eF6f804753109057b89ea4Ec5d60516',
      rollupEventInbox: '0x7e8C3fcDF91a606b71b77c6502b8E4A58559D20A',
      outbox: '0x56001107D68A55A0Dc321821b22C8d657A6ce74b',
    },
    erc20: {
      bridge: '0xb3Dc60073a2A4F74b1575CeCa6c368D1d906c43E',
      sequencerInbox: '0x14820E92B664D771bc6c787481B7c088a9dA7760',
      delayBufferableSequencerInbox:
        '0x2766e96f90f9F027835E0c00c04C8119c635Ce02',
      inbox: '0x037B11bB930dBB7c875ce459eeFf69FC2E9FD40d',
      rollupEventInbox: '0xb034A5B82f12023017285b36a3d831698caA064f',
      outbox: '0x6Ca66235758bCCd08a4D1612662482F08Fab9347',
    },
    rollupUserLogic: '0xE927E260Eb017552b047786837bab40ff515FfD8',
    rollupAdminLogic: '0x479d0Fb5fd2902d6f9a4Fba18311854f8c4C6044',
    challengeManagerTemplate: '0xFf579b0AF1B69382BbF3e656bAE39A067AeE700a',
    osp: '0x8569CADe473FD633310d7899c0F5025e1F21f664',
    rollupCreator: '0xfB83e25003b4193060bA988bA0277122B6D8337C',
  },
}

export async function verifyCreatorTemplates(
  l1Rpc: JsonRpcProvider,
  templates: CreatorTemplates
) {
  const checkAddress = async (name: string, address: string) => {
    if ((await l1Rpc.getCode(address)).length <= 2) {
      throw new Error(`No code found for template ${name} at ${address}`)
    }
  }

  for (const [key, value] of Object.entries(templates)) {
    if (typeof value === 'string') {
      await checkAddress(key, value)
    } else {
      for (const [subkey, subvalue] of Object.entries(value)) {
        await checkAddress(`${key}.${subkey}`, subvalue)
      }
    }
  }
}
