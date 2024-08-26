// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

struct SignatureData {
    string chainId;
    address contractAddress;
    address serverAddress;
    address userAddress;
    string signatureType;
    string s1;
}
