// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/ILegacyVault.sol";

contract LegacyVault is ILegacyVault, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address[2] public backupWallets;
    bool public backupWalletStatus;

    event BackupWalletsAdded(
        string userId,
        address indexed owner,
        address[2] backupwallets,
        string[2] walletNames
    );

    constructor(address _memberAddress, address _legacyAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, _memberAddress);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, _memberAddress);
        _setupRole(ADMIN_ROLE, _legacyAddress);
    }

    function getBackupWallets() external view returns (address[2] memory) {
        return backupWallets;
    }

    function setBackupWallets(
        string memory userId,
        address[2] calldata _backupWallets,
        string[2] calldata walletNames
    ) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(
            !backupWalletStatus,
            "LegacyVault: Backup wallet already switched"
        );
        for (uint i = 0; i < 2; i++) {
            require(
                _backupWallets[i] != address(0),
                "LegacyAssetManager: Backup wallet cannot be zero address"
            );
            backupWallets[i] = _backupWallets[i];
        }
        emit BackupWalletsAdded(
            userId,
            _msgSender(),
            _backupWallets,
            walletNames
        );
    }

    function transferErc20TokensAllowed(
        address _contractAddress,
        address _ownerAddress,
        address _recipientAddress,
        uint256 _amount
    ) external override whenNotPaused onlyRole(ADMIN_ROLE) {
        IERC20(_contractAddress).transferFrom(
            _ownerAddress,
            _recipientAddress,
            _amount
        );
    }

    function transferErc721TokensAllowed(
        address _contractAddress,
        address _ownerAddress,
        address _recipientAddress,
        uint256 _tokenId
    ) external override whenNotPaused onlyRole(ADMIN_ROLE) {
        IERC721(_contractAddress).safeTransferFrom(
            _ownerAddress,
            _recipientAddress,
            _tokenId
        );
    }

    function transferErc1155TokensAllowed(
        address _contractAddress,
        address _ownerAddress,
        address _recipientAddress,
        uint256 _tokenId,
        uint256 _amount
    ) external override whenNotPaused onlyRole(ADMIN_ROLE) {
        IERC1155(_contractAddress).safeTransferFrom(
            _ownerAddress,
            _recipientAddress,
            _tokenId,
            _amount,
            "0x01"
        );
    }

    function pauseContract()
        external
        override
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _pause();
    }

    function unpauseContract()
        external
        override
        whenPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _unpause();
    }
}
