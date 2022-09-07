// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface ILegacyVaultFactory {
    function createVault(address _memberAddress) external;

    function deployedContractFromMember(address _memberAddress)
        external
        view
        returns (address);

    function setLegacyAssetManagerAddress(address _VaultAddress) external;

    function pauseContract() external;

    function unpauseContract() external;
}
