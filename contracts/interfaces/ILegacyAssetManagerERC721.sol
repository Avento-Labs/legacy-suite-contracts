// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ILegacyAssetManagerERC721 {
function addERC721Assets(
        string calldata userId,
        address[] calldata _contracts,
        uint256[] calldata tokenIds,
        address[] calldata beneficiaries
    ) external;

function removeERC721Asset(
        string memory userId,
        address _contract,
        uint256 tokenId
    ) external;

function claimERC721Asset(
        string memory userId,
        address owner,
        address _contract,
        uint256 tokenId,
        uint256 nonce,
        bytes[] calldata signatures
    ) external;

function setERC721Beneficiary(
        string memory userId,
        address _contract,
        uint256 tokenId,
        address newBeneficiary
    ) external;


}