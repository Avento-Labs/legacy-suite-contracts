// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

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


interface ILegacyAssetManagerAdmin{
    function _checkListedUser(
        address _member
        )
        external
        view
        returns (bool);

    function setBackupWalletIndexStatus(
        address _member,
        uint8 index,
        bool status
        )
        external;

    function createUserVault(
        string calldata userId,
        uint256 nonce,
        bytes calldata signature
    ) external;

    function setVaultFactory(
        address _vaultFactory
    ) external;

    function setMinAdminSignature(
        uint16 _minAdminSignature
    ) external;


    function pauseContract()
        external;

    function unpauseContract()
        external;

    function withdrawEther(address to) external;
}