
object "BlobBasefeeReader" {
   code {
      datacopy(0, dataoffset("runtime"), datasize("runtime"))
      return(0, datasize("runtime"))
   }
   object "runtime" {
      code {
         // Match against the keccak of the ABI function signature needed.
         switch shr(0xe0,calldataload(0))
            // bytes4(keccak("getBlobBaseFee()"))
            case 0x1f6d6ef7 {
               // BLOBBASEFEE opcode has hex value 0x4a
               let blobBasefee := verbatim_0i_1o(hex"4a")
               mstore(0, blobBasefee) 
               return(0, 32)
            }
      }
   }
}