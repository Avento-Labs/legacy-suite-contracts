// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
    /**
     * Structs
     */
    struct Beneficiary {
        address account;
        uint8 allowedPercentage;
        uint256 totalAmount;
        uint256 claimedAmount;
    }

    struct ERC1155Asset {
        address owner;
        address _contract;
        uint256 tokenId;
        uint256 totalAmount;
        uint256 totalRemainingAmount;
        uint8 totalPercentage;
        Beneficiary[] beneficiaries;
        uint256 remainingBeneficiaries;
    }

    struct ERC721Asset {
        address owner;
        address _contract;
        uint256 tokenId;
        address beneficiary;
        bool transferStatus;
    }

    struct ERC20Asset {
        address owner;
        address _contract;
        uint256 totalAmount;
        uint256 totalRemainingAmount;
        uint8 totalPercentage;
        Beneficiary[] beneficiaries;
        uint256 remainingBeneficiaries;
    }

    struct UserAssets {
        ERC1155Asset[] erc1155Assets;
        ERC721Asset[] erc721Assets;
        ERC20Asset[] erc20Assets;
        bool backupWalletStatus;
        uint8 backupWalletIndex;
    }

interface ILegacyAssetManager{
    function _checkListedUser(
        address _member
        )
        external
        view
        returns (bool);

    function createUserVault(
        string calldata userId,
        uint256 nonce,
        bytes calldata signature
    ) external; 


    function getUserAssets(
        address _member
        )
        external
        view
        returns (UserAssets memory);


        function setBackupWalletIndexStatus(
        address _member,
        uint8 index,
        bool status
        )
        external;

}