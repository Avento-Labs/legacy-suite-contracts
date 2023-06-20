// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ILegacyAssetManagerERC20{

function addERC20Assets(
        string calldata userId,
        address[] calldata contracts,
        address[][] calldata beneficiaryAddresses,
        uint8[][] calldata beneficiaryPercentages
    ) external;

function removeERC20Asset(
        string memory userId,
        address _contract
    ) external;

function claimERC20Asset(
        string memory userId,
        address owner,
        address _contract,
        uint256 nonce,
        bytes[] calldata signatures
    ) external;

function setERC1155BeneficiaryPercentage(
        string memory userId,
        address _contract,
        uint256 tokenId,
        address beneficiary,
        uint8 newPercentage
    ) external;

function setERC721Beneficiary(
        string memory userId,
        address _contract,
        uint256 tokenId,
        address newBeneficiary
    ) external;


function setERC20BeneficiaryPercentage(
        string memory userId,
        address _contract,
        address beneficiary,
        uint8 newPercentage
    ) external;


function setVaultFactory(
        address _vaultFactory
    ) external;


function setMinAdminSignature(
        uint16 _minAdminSignature
    ) external;



}