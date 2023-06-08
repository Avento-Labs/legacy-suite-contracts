// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/ILegacyVault.sol";
import "../interfaces/ILegacyVaultFactory.sol";
import "../interfaces/ILegacyAssetManager.sol";

contract LegacyVault is ILegacyVault, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    mapping(address => address[2]) public backupWallets;
    address private _legacyAssetManager;
    ILegacyVaultFactory public vaultFactory;

    modifier onlyListedUser(address user) {
        require((ILegacyAssetManager(_legacyAssetManager)._checkListedUser(user)), "LegacyAssetManager: User not listed");
        _;
    }

    event BackupWalletAdded(
        string userId,
        address indexed owner,
        uint8 index,
        address indexed backupwallet
    );

    event BackupWalletSwitched(
        string userId,
        address indexed owner,
        address indexed backupwallet
    );


    constructor(address _memberAddress, address _legacyAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, _memberAddress);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, _memberAddress);
        _setupRole(ADMIN_ROLE, _legacyAddress);
        _legacyAssetManager = _legacyAddress;
    }

    function getBackupWallet(
        address _owner) external view returns (address[2] memory) {
        return backupWallets[_owner];
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

    function addBackupWallet(
        string memory userId,
        uint8 index,
        address _backupWallet
    ) external onlyListedUser(_msgSender()) {
        require(
            !(ILegacyAssetManager(_legacyAssetManager).getUserAssets(_msgSender()).backupWalletStatus),
            "LegacyAssetManager: Backup wallet already switched"
        );
        require(index < 2, "LegacyAssetManager: Invalid backup wallet index");
        backupWallets[_msgSender()][index] = _backupWallet;
        emit BackupWalletAdded(userId, _msgSender(), index, _backupWallet);
    }

    function switchBackupWallet(string memory userId, address owner) external {
        require(
            _msgSender() == backupWallets[owner][0] ||
                _msgSender() == backupWallets[owner][1],
            "LegacyAssetManager: Unauthorized backup wallet transfer call"
        );
        ILegacyVault userVault = ILegacyVault(
            ILegacyVaultFactory(vaultFactory).getVault(owner)
        );
        for (uint i = 0; i < ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc1155Assets.length; i++) {
            IERC1155 _contract = IERC1155(
                ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc1155Assets[i]._contract
            );
            uint256 userBalance = _contract.balanceOf(
                owner,
                ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc1155Assets[i].tokenId
            );
            if (
                userBalance > 0 &&
                _contract.isApprovedForAll(owner, address(userVault))
            ) {
                userVault.transferErc1155TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc1155Assets[i].tokenId,
                    userBalance
                );
            }
        }
        for (uint i = 0; i < ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc721Assets.length; i++) {
            IERC721 _contract = IERC721(
                ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc721Assets[i]._contract
            );
            uint256 tokenId = ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc721Assets[i].tokenId;
            if (_contract.ownerOf(tokenId) == owner) {
                userVault.transferErc721TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    tokenId
                );
            }
        }
        for (uint i = 0; i < ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc20Assets.length; i++) {
            IERC20 _contract = IERC20(
                ILegacyAssetManager(_legacyAssetManager).getUserAssets(owner).erc20Assets[i]._contract
            );
            uint256 userBalance = _contract.balanceOf(owner);
            uint256 allowance = _contract.allowance(owner, address(userVault));
            if (userBalance > 0 && userBalance >= allowance) {
                userVault.transferErc20TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    allowance
                );
            } else if (userBalance > 0 && userBalance < allowance) {
                userVault.transferErc20TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    userBalance
                );
            }
        }
        ILegacyAssetManager(_legacyAssetManager).setBackupWalletStatus(owner,true);
        if (backupWallets[owner][0] == _msgSender()) {
            ILegacyAssetManager(_legacyAssetManager).setBackupWalletIndex(owner,0);
        } else {
            ILegacyAssetManager(_legacyAssetManager).setBackupWalletIndex(owner,1);
        }
        emit BackupWalletSwitched(userId, owner, _msgSender());
    }


}
