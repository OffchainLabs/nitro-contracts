// taken from https://github.com/rauljordan/eip4844-interop/blob/b23c1afa79ad18b0318dca41c000c7c0edfe29d9/upload/contracts/DataHashesReader.yul
object "DataHashesReader" {
   code {
      datacopy(0, dataoffset("runtime"), datasize("runtime"))
      return(0, datasize("runtime"))
   }
   object "runtime" {
      code {
         // Match against the keccak of the ABI function signature needed.
         switch shr(0xe0,calldataload(0))
            // bytes4(keccak("getDataHashes()"))
            case 0xe83a2d82 {
                // DATAHASH opcode has hex value 0x49
                let i := 0
                for {} true {} {
                    let hash := verbatim_1i_1o(hex"49", i)
                    if iszero(hash) {
                        break
                    }
                    mstore(add(mul(i, 32), 64), hash)
                    i := add(i, 1)
                }
                mstore(0, 32)
                mstore(32, i)
                return(0, add(mul(i, 32), 64))
            }
      }
   }
}