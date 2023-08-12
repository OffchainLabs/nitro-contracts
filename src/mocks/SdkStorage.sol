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
        mapping(int32 => address)[] array;
        mapping(bytes1 => mapping(bool => uint256)) nested;
        mapping(string => Struct) structs;
    }

    function populate() external {
        flag = true;
        owner = address(0x70);
        other = address(0x30);

        sub.num = 32;
        sub.other = type(int32).max;
        sub.word = bytes32(uint256(64));

        for (uint64 i = 0; i < 32; i++) {
            vector.push(i);
        }
        vector[7] = 77;

        for (uint256 w = 0; w < 10; w++) {
            nested.push(new uint40[](w));
            for (uint256 i = 0; i < w; i++) {
                nested[w][i] = uint40(i);
            }
        }
        for (uint256 w = 0; w < 10; w++) {
            for (uint256 i = 0; i < w; i++) {
                nested[w][i] *= 2;
            }
        }

        for (uint8 i = 0; i < 31; i++) {
            bytesFull = abi.encodePacked(bytesFull, i);
        }
        for (uint8 i = 0; i < 80; i++) {
            bytesLong = abi.encodePacked(bytesLong, i);
        }
        chars = "arbitrum stylus";

        for (uint256 i = 0; i < 16; i++) {
            maps.basic[i] = address(uint160(i));
        }

        for (uint160 a = 0; a < 4; a++) {
            maps.vects[address(a)] = new bool[](0);
            for (uint256 i = 0; i <= a; i++) {
                maps.vects[address(a)].push(true);
            }
        }

        for (int32 i = 0; i < 4; i++) {
            maps.array.push();
            maps.array[uint256(uint32(i))][i] = address(uint160(uint32(i)));
        }

        for (uint8 i = 0; i < 4; i++) {
            maps.nested[bytes1(i)][i % 2 == 0] = i + 1;
        }

        maps.structs["stylus"] = sub;

        for (uint256 i = 0; i < 4; i++) {
            structs.push(sub);
        }
    }

    function remove() external {
        while (bytesFull.length != 0) {
            bytesFull.pop();
        }

        while (bytesLong.length > 16) {
            bytesLong.pop();
        }

        chars = "wasm is cute <3";

        while (vector.length != 0) {
            vector.pop();
        }

        while (nested.length > 1) {
            nested.pop();
        }

        for (uint256 i = 0; i < 8; i++) {
            delete maps.basic[i];
        }
        maps.basic[8] = address(32);

        for (uint160 i = 0; i < 4; i++) {
            delete maps.vects[address(i)];
        }

        structs.pop();
    }
}
