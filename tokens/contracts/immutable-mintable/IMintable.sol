// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IMintable {
    function mintFor(
        address to,
        uint256 quantity,
        bytes calldata mintingBlob
    ) external;
}