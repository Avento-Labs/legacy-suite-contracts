// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ILegacyVaultFactory {
    function createVault(address _memberAddress) external;

    function getVault(address _listedAddress) external view returns (address);

    function getMainWallet(address _listedAddress)
        external
        view
        returns (address);

    function addWallet(address _memberAddress) external;

    function removeWallet(address _memberAddress) external;

    function setLegacyAssetManagerAddress(address _VaultAddress) external;

    function pauseContract() external;

    function unpauseContract() external;
}
