// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/ILegacyVault.sol";
import "../interfaces/ILegacyAssetManager.sol";
import "../interfaces/ILegacyVaultFactory.sol";

contract LegacyVault is ILegacyVault, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    address legacyAssetManager;
    mapping(address => address[2]) public backupWallets;
    
    


    constructor(address _memberAddress, address _legacyAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, _memberAddress);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, _memberAddress);
        _setupRole(ADMIN_ROLE, _legacyAddress);
        legacyAssetManager = _legacyAddress;
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

    function getBackupWallet(address _owner)
        external
        view
        override
        returns (address[2] memory)
    {
        return backupWallets[_owner];
    }

    function addBackupWallet(
        string memory userId,
        uint8 index,
        address _backupWallet
    ) external {
        ILegacyAssetManager assetManager = ILegacyAssetManager(legacyAssetManager);
        require(
            assetManager._checkListedUser(_msgSender()),
            "LegacyAssetManager: User not listed"
        );
        require(
            !(assetManager.getUserAssets(_msgSender())).backupWalletStatus,
            "LegacyAssetManager: Backup wallet already switched"
        );
        require(index < 2, "LegacyAssetManager: Invalid backup wallet index");
        backupWallets[_msgSender()][index]=_backupWallet;
        emit BackupWalletAdded(userId, _msgSender(), index, _backupWallet);
    }

     function switchBackupWallet(string memory userId, address owner) external {
        require(
            _msgSender() == backupWallets[owner][0] ||
                _msgSender() == backupWallets[owner][1],
            "LegacyAssetManager: Unauthorized backup wallet transfer call"
        );
        ILegacyAssetManager assetManager = ILegacyAssetManager(legacyAssetManager);
        UserAssets memory userAsset = assetManager.getUserAssets(owner);
        for (uint i = 0; i < userAsset.erc1155Assets.length; i++) {
            IERC1155 _contract = IERC1155(
                userAsset.erc1155Assets[i]._contract
            );
            uint256 userBalance = _contract.balanceOf(
                owner,
                userAsset.erc1155Assets[i].tokenId
            );
            if (
                userBalance > 0 &&
                _contract.isApprovedForAll(owner, address(this))
            ) {
                this.transferErc1155TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    userAsset.erc1155Assets[i].tokenId,
                    userBalance
                );
            }
        }
        for (uint i = 0; i < userAsset.erc721Assets.length; i++) {
            IERC721 _contract = IERC721(
                userAsset.erc721Assets[i]._contract
            );
            uint256 tokenId = userAsset.erc721Assets[i].tokenId;
            if (_contract.ownerOf(tokenId) == owner) {
                this.transferErc721TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    tokenId
                );
            }
        }
        for (uint i = 0; i < userAsset.erc20Assets.length; i++) {
            IERC20 _contract = IERC20(
                userAsset.erc20Assets[i]._contract
            );
            uint256 userBalance = _contract.balanceOf(owner);
            uint256 allowance = _contract.allowance(owner, address(this));
            if (userBalance > 0 && userBalance >= allowance) {
                this.transferErc20TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    allowance
                );
            } else if (userBalance > 0 && userBalance < allowance) {
                this.transferErc20TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    userBalance
                );
            }
        }
        
        if (backupWallets[owner][0] == _msgSender()) {
            assetManager.setBackupWalletIndexStatus(owner,0,true);
        } else {
            assetManager.setBackupWalletIndexStatus(owner,1,true);
        }
        emit BackupWalletSwitched(userId, owner, _msgSender());
    }

}
