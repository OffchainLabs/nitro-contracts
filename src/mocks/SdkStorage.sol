// Copyright 2022-2023, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

contract SdkStorage {
    bool flag;
    address owner;
    address other;
    Struct sub;
    Struct[] structs;
    uint64[] vector;
    uint40[][] nested;
    bytes bytesFull;
    bytes bytesLong;
    string chars;
    Maps maps;

    struct Struct {
        uint16 num;
        int32 other;
        bytes32 word;
    }

    struct Maps {
        mapping(uint256 => address) basic;
        mapping(address => bool[]) vects;
        mapping(uint32 => address)[] array;
        mapping(bytes1 => mapping(bool => uint256)) nested;
        mapping(string => Struct) structs;
    }

    function test() external {
        flag = true;
        owner = address(0x70);
        other = address(0x30);

        sub.num = 32;
        sub.other = type(int32).max;
        sub.word = bytes32(uint(64));

        for (uint64 i = 0; i < 32; i++) {
            vector.push(i);
        }
        vector[7] = 77;

        for (uint w = 0; w < 10; w++) {
            nested.push(new uint40[](w));
            for (uint i = 0; i < w; i++) {
                nested[w][i] = uint40(i);
            }
        }
        for (uint w = 0; w < 10; w++) {
            for (uint i = 0; i < w; i++) {
                nested[w][i] *= 2;
            }
        }

        for (uint8 i = 0; i < 31; i++) {
            bytesFull = abi.encodePacked(bytesFull, i);
        }
        for (uint8 i = 0; i < 34; i++) {
            bytesLong = abi.encodePacked(bytesLong, i);
        }
        chars = "arbitrum stylus";

        for (uint i = 0; i < 16; i++) {
            maps.basic[i] = address(uint160(i));
        }

        for (uint160 a = 0; a < 4; a++) {
            maps.vects[address(a)] = new bool[](0);
            for (uint i = 0; i <= a; i++) {
                maps.vects[address(a)].push(true);
            }
        }

        for (uint32 i = 0; i < 4; i++) {
            maps.array.push();
            maps.array[i][i] = address(uint160(i));
        }

        for (uint8 i = 0; i < 4; i++) {
            maps.nested[bytes1(i)][i % 2 == 0] = i + 1;
        }

        maps.structs["stylus"] = sub;

        for (uint i = 0; i < 4; i++) {
            structs.push(sub);
        }
    }
}
