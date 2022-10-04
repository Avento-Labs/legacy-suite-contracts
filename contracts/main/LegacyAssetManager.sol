// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/ILegacyVaultFactory.sol";
import "../interfaces/ILegacyVault.sol";

import "hardhat/console.sol";

contract LegacyAssetManager is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant LEGACY_ADMIN = keccak256("LEGACY_ADMIN");
    bytes32 public constant ASSET_AUTHORIZER = keccak256("ASSET_AUTHORIZER");

    ILegacyVaultFactory public vaultFactory;

    mapping(address => UserAssets) public userAssets;
    mapping(address => ERC721Asset[]) public erc721beneficiaries;
    mapping(address => ERC20Asset[]) public erc20Beneficiaries;
    mapping(address => mapping(uint256 => bool)) public listedAssets;
    mapping(address => bool) public listedMembers;
    mapping(address => address) public backupWallets;

    event ERC21AssetAdded(
        string userTag,
        address indexed owner,
        address _contract,
        uint256 indexed tokenId,
        address beneficiary
    );

    event ERC20AssetAdded(
        string userTag,
        address indexed owner,
        address indexed _contract,
        uint256 totalAmount,
        address[] beneficiaries,
        uint8[] beneficiaryPercentages,
        uint8 totalPercentage
    );

    event ERC721AssetRemoved(
        string userTag,
        address indexed owner,
        address _contract,
        uint256 indexed tokenId
    );

    event ERC20AssetRemoved(
        string userTag,
        address indexed owner,
        address indexed _contract,
        uint256 totalAmount,
        uint256 remainingBeneficiaries
    );

    event ERC721AssetClaimed(
        string userTag,
        address indexed owner,
        address claimer,
        address _contract,
        uint256 indexed tokenId
    );

    event ERC20AssetClaimed(
        string userTag,
        address indexed owner,
        address indexed claimer,
        address _contract,
        uint256 amount
    );

    event BackupWalletAdded(
        string userTag,
        address indexed owner,
        address indexed backupWallet
    );

    event BackupWalletSwitched(
        string userTag,
        address indexed owner,
        address indexed backupwallet
    );

    event BeneficiaryChanged(
        string userTag,
        address indexed owner,
        address _contract,
        uint256 tokenId,
        address newBeneficiary
    );

    event BeneficiaryPercentageChanged(
        string userTag,
        address indexed owner,
        address _contract,
        address beneficiary,
        uint8 newpercentage
    );

    /**
     * Structs
     */
    struct ERC20Benificiary {
        address account;
        uint8 allowedPercentage;
        bool transferStatus;
    }

    struct ERC20Asset {
        address owner;
        address _contract;
        uint256 totalAmount;
        ERC20Benificiary[] beneficiaries;
        uint256 remainingBeneficiaries;
        uint8 totalPercentage;
    }

    struct ERC721Asset {
        address owner;
        address _contract;
        uint256 tokenId;
        address beneficiary;
        bool transferStatus;
    }

    struct UserAssets {
        ERC721Asset[] erc721Assets;
        ERC20Asset[] erc20Assets;
        bool backupWalletStatus;
    }

    enum AssetType {
        erc721,
        erc20
    }

    constructor(address _vaultFactory) {
        vaultFactory = ILegacyVaultFactory(_vaultFactory);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(LEGACY_ADMIN, _msgSender());
        _setupRole(ASSET_AUTHORIZER, _msgSender());
    }

    function addERC721Assets(
        string memory userTag,
        address[] memory _contracts,
        uint256[] memory tokenIds,
        address[] memory beneficiaries,
        bytes32 hashedMessage,
        bytes memory signature
    ) public {
        require(
            _contracts.length == tokenIds.length &&
                tokenIds.length == beneficiaries.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        if (!listedMembers[_msgSender()]) {
            address signer = _verifySignature(hashedMessage, signature);
            require(
                hasRole(ASSET_AUTHORIZER, signer),
                "LegacyAssetManager: Unauthorized signature"
            );
            listedMembers[_msgSender()] = true;
        }
        for (uint i = 0; i < tokenIds.length; i++) {
            _addERC721Single(
                userTag,
                _contracts[i],
                tokenIds[i],
                beneficiaries[i]
            );
        }
    }

    function _addERC721Single(
        string memory userTag,
        address _contract,
        uint256 tokenId,
        address beneficiary
    ) internal {
        require(
            !listedAssets[_contract][tokenId],
            "LegacyAssetManager: Asset already added"
        );
        require(
            IERC721(_contract).supportsInterface(0x80ac58cd),
            "LegacyAssetManager: Contract is not a valid ERC721 _contract"
        );
        require(
            IERC721(_contract).ownerOf(tokenId) == _msgSender(),
            "LegacyAssetManager: Caller is not the token owner"
        );
        require(
            IERC721(_contract).getApproved(tokenId) ==
                vaultFactory.deployedContractFromMember(_msgSender()),
            "LegacyAssetManager: Asset not approved"
        );
        userAssets[_msgSender()].erc721Assets.push(
            ERC721Asset(_msgSender(), _contract, tokenId, beneficiary, false)
        );
        listedAssets[_contract][tokenId] = true;
        emit ERC21AssetAdded(
            userTag,
            _msgSender(),
            _contract,
            tokenId,
            beneficiary
        );
    }

    function addERC20Assets(
        string memory userTag,
        address[] memory contracts,
        uint256[] memory totalAmounts,
        address[][] memory beneficiaryAddresses,
        uint8[][] memory beneficiaryPercentages,
        bytes32 hashedMessage,
        bytes memory signature
    ) public {
        require(
            contracts.length == beneficiaryAddresses.length &&
                beneficiaryAddresses.length == totalAmounts.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        if (!listedMembers[_msgSender()]) {
            address signer = _verifySignature(hashedMessage, signature);
            require(
                hasRole(ASSET_AUTHORIZER, signer),
                "LegacyAssetManager: Unauthorized signature"
            );
            listedMembers[_msgSender()] = true;
        }
        for (uint i = 0; i < contracts.length; i++) {
            _addERC20Single(
                userTag,
                contracts[i],
                totalAmounts[i],
                beneficiaryAddresses[i],
                beneficiaryPercentages[i]
            );
        }
    }

    function _addERC20Single(
        string memory userTag,
        address _contract,
        uint256 totalAmount,
        address[] memory beneficiaryAddresses,
        uint8[] memory beneficiaryPercentages
    ) internal {
        require(
            beneficiaryAddresses.length == beneficiaryPercentages.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        require(
            IERC20(_contract).balanceOf(_msgSender()) >= totalAmount,
            "LegacyAssetManager: Asset amount exceeds balance"
        );
        require(
            IERC20(_contract).allowance(
                _msgSender(),
                vaultFactory.deployedContractFromMember(_msgSender())
            ) >= totalAmount,
            "LegacyAssetManager: Asset allowance is insufficient"
        );

        uint8 totalPercentage;
        ERC20Benificiary[] memory _erc20Beneficiaries = new ERC20Benificiary[](
            beneficiaryAddresses.length
        );
        for (uint i = 0; i < beneficiaryAddresses.length; i++) {
            require(
                beneficiaryPercentages[i] > 0,
                "LegacyAssetManager: Beneficiary percentage must be > 0"
            );
            _erc20Beneficiaries[i] = ERC20Benificiary(
                beneficiaryAddresses[i],
                beneficiaryPercentages[i],
                false
            );
            totalPercentage += beneficiaryPercentages[i];
            require(
                totalPercentage <= 100,
                "LegacyAssetManager: Beneficiary percentages exceed 100"
            );
        }
        userAssets[_msgSender()].erc20Assets.push(
            ERC20Asset(
                _msgSender(),
                _contract,
                totalAmount,
                _erc20Beneficiaries,
                beneficiaryAddresses.length,
                totalPercentage
            )
        );
        emit ERC20AssetAdded(
            userTag,
            _msgSender(),
            _contract,
            totalAmount,
            beneficiaryAddresses,
            beneficiaryPercentages,
            totalPercentage
        );
    }

    function removeERC721Single(
        string memory userTag,
        address _contract,
        uint256 tokenId
    ) public {
        require(
            listedAssets[_contract][tokenId],
            "LegacyAssetManager: Asset not found"
        );
        uint256 assetIndex = _findERC721AssetIndex(
            _msgSender(),
            _contract,
            tokenId
        );
        require(
            assetIndex < userAssets[_msgSender()].erc721Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        ERC721Asset memory erc721Asset = userAssets[_msgSender()].erc721Assets[
            assetIndex
        ];
        require(
            !erc721Asset.transferStatus,
            "LegacyAssetManager: Asset has been transferred to the beneficiary"
        );
        _removeAsset(_msgSender(), AssetType.erc721, assetIndex);
        emit ERC721AssetRemoved(userTag, _msgSender(), _contract, tokenId);
    }

    function removeERC20Single(string memory userTag, address _contract)
        public
    {
        uint256 assetIndex = _findERC20AssetIndex(_msgSender(), _contract);
        ERC20Asset memory erc20Asset = userAssets[_msgSender()].erc20Assets[
            assetIndex
        ];
        require(
            erc20Asset._contract != address(0),
            "LegacyAssetManager: Asset not found"
        );
        require(
            erc20Asset.remainingBeneficiaries > 0,
            "LegacyAssetManager: Asset has been transferred to the beneficiaries"
        );
        _removeAsset(_msgSender(), AssetType.erc20, assetIndex);
        emit ERC20AssetRemoved(
            userTag,
            _msgSender(),
            _contract,
            erc20Asset.totalAmount,
            erc20Asset.remainingBeneficiaries
        );
    }

    function _findERC721AssetIndex(
        address user,
        address _contract,
        uint256 tokenId
    ) internal view returns (uint256) {
        for (uint i = 0; i < userAssets[user].erc721Assets.length; i++) {
            if (
                userAssets[user].erc721Assets[i]._contract == _contract &&
                userAssets[user].erc721Assets[i].tokenId == tokenId
            ) {
                return i;
            }
        }
        return userAssets[user].erc721Assets.length;
    }

    function _findERC20AssetIndex(address user, address _contract)
        internal
        view
        returns (uint256)
    {
        for (uint i = 0; i < userAssets[user].erc20Assets.length; i++) {
            if (userAssets[user].erc20Assets[i]._contract == _contract) {
                return i;
            }
        }
        return userAssets[user].erc20Assets.length;
    }

    function _removeAsset(
        address user,
        AssetType assetType,
        uint256 assetIndex
    ) internal {
        if (assetType == AssetType.erc721) {
            for (
                uint i = assetIndex;
                i < userAssets[user].erc721Assets.length;
                i++
            ) {
                userAssets[user].erc721Assets[i] = userAssets[user]
                    .erc721Assets[i + 1];
            }
            userAssets[user].erc721Assets.pop();
        } else {
            for (
                uint i = assetIndex;
                i < userAssets[user].erc20Assets.length;
                i++
            ) {
                userAssets[user].erc20Assets[i] = userAssets[user].erc20Assets[
                    i + 1
                ];
            }
            userAssets[user].erc20Assets.pop();
        }
    }

    function getERC721Asset(
        address user,
        address _contract,
        uint256 tokenId
    ) public view returns (ERC721Asset memory) {
        uint256 assetIndex = _findERC721AssetIndex(user, _contract, tokenId);
        require(
            assetIndex < userAssets[user].erc721Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        return userAssets[user].erc721Assets[assetIndex];
    }

    function getERC20Asset(address user, address _contract)
        public
        view
        returns (ERC20Asset memory)
    {
        uint256 assetIndex = _findERC20AssetIndex(user, _contract);
        require(
            assetIndex < userAssets[user].erc20Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        return userAssets[user].erc20Assets[assetIndex];
    }

    function getBackupWallet(address owner) public view returns (address) {
        return backupWallets[owner];
    }

    function setBackupWallet(string memory userTag, address _backupWallet)
        public
    {
        require(
            !userAssets[_msgSender()].backupWalletStatus,
            "LegacyAssetManager: Backup wallet already switched"
        );
        require(
            _backupWallet != address(0),
            "LegacyAssetManager: Invalid address for backup wallet"
        );
        require(
            backupWallets[_msgSender()] != _backupWallet,
            "LegacyAssetManager: Backup wallet provided already set"
        );
        backupWallets[_msgSender()] = _backupWallet;
        emit BackupWalletAdded(userTag, _msgSender(), _backupWallet);
    }

    function switchBackupWallet(string memory userTag, address owner) public {
        require(
            _msgSender() == backupWallets[owner],
            "LegacyAssetManager: Unauthorized backup wallet transfer call"
        );
        ERC721Asset[] memory erc721Assets = userAssets[owner].erc721Assets;
        ERC20Asset[] memory erc20Assets = userAssets[owner].erc20Assets;

        ILegacyVault userVault = ILegacyVault(
            ILegacyVaultFactory(vaultFactory).deployedContractFromMember(owner)
        );
        for (uint i = 0; i < erc721Assets.length; i++) {
            IERC721 _contract = IERC721(erc721Assets[i]._contract);
            uint256 tokenId = erc721Assets[i].tokenId;
            if (_contract.ownerOf(tokenId) == owner) {
                userVault.transferErc721TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    tokenId
                );
            }
        }
        for (uint i = 0; i < erc20Assets.length; i++) {
            IERC20 _contract = IERC20(erc20Assets[i]._contract);
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
        userAssets[owner].backupWalletStatus = true;
        emit BackupWalletSwitched(userTag, owner, _msgSender());
    }

    function addAdmin(address _admin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LEGACY_ADMIN, _admin);
    }

    function removeAdmin(address _admin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(LEGACY_ADMIN, _admin);
    }

    function claimERC721Asset(
        string memory userTag,
        address owner,
        address _contract,
        uint256 tokenId,
        bytes32 hashedMessage,
        bytes memory signature
    ) public {
        address signer = _verifySignature(hashedMessage, signature);
        require(
            hasRole(LEGACY_ADMIN, signer),
            "LegacyAssetManager: Unauthorized signature"
        );
        uint256 assetIndex = _findERC721AssetIndex(owner, _contract, tokenId);
        ERC721Asset memory erc721Asset = userAssets[owner].erc721Assets[
            assetIndex
        ];
        require(
            !erc721Asset.transferStatus,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );
        require(
            erc721Asset.beneficiary == _msgSender(),
            "LegacyAssetManager: Unauthorized claim call"
        );

        address vaultAddress = vaultFactory.deployedContractFromMember(owner);
        address from;
        if (userAssets[owner].backupWalletStatus) {
            from = backupWallets[owner];
        } else {
            from = owner;
        }
        require(
            IERC721(_contract).ownerOf(tokenId) == from,
            "LegacyAssetManager: The asset does not belong to the owner now"
        );
        ILegacyVault(vaultAddress).transferErc721TokensAllowed(
            _contract,
            from,
            _msgSender(),
            tokenId
        );
        userAssets[owner].erc721Assets[assetIndex].transferStatus = true;
        emit ERC721AssetClaimed(
            userTag,
            owner,
            _msgSender(),
            _contract,
            tokenId
        );
    }

    function claimERC20Asset(
        string memory userTag,
        address owner,
        address _contract,
        bytes32 hashedMessage,
        bytes memory signature
    ) public {
        address signer = _verifySignature(hashedMessage, signature);
        require(
            hasRole(LEGACY_ADMIN, signer),
            "LegacyAssetManager: Unauthorized signature"
        );
        uint256 assetIndex = _findERC20AssetIndex(owner, _contract);
        ERC20Asset memory erc20Asset = userAssets[owner].erc20Assets[
            assetIndex
        ];
        uint256 beneficiaryIndex = _findBeneficiaryIndex(
            _msgSender(),
            erc20Asset
        );
        require(
            !erc20Asset.beneficiaries[beneficiaryIndex].transferStatus,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );
        uint8 allowedPercentage = erc20Asset
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;

        address from;
        if (userAssets[owner].backupWalletStatus) {
            from = backupWallets[owner];
        } else {
            from = owner;
        }
        uint256 ownerBalance = IERC20(_contract).balanceOf(from);
        require(
            ownerBalance > 0,
            "LegacyAssetManager: Owner has zero balance for this asset"
        );

        uint256 dueAmount;
        if (ownerBalance > erc20Asset.totalAmount) {
            dueAmount = (erc20Asset.totalAmount * allowedPercentage) / 100;
        } else {
            dueAmount = (ownerBalance * allowedPercentage) / 100;
        }
        address vaultAddress = vaultFactory.deployedContractFromMember(owner);
        ILegacyVault(vaultAddress).transferErc20TokensAllowed(
            _contract,
            from,
            _msgSender(),
            dueAmount
        );

        userAssets[owner]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .transferStatus = true;
        userAssets[owner].erc20Assets[assetIndex].remainingBeneficiaries--;
        emit ERC20AssetClaimed(
            userTag,
            owner,
            _msgSender(),
            _contract,
            dueAmount
        );
    }

    function _findBeneficiaryIndex(
        address beneficiary,
        ERC20Asset memory erc20Asset
    ) internal pure returns (uint256) {
        uint256 beneficiaryIndex;
        bool beneficiaryFound;
        for (uint i = 0; i < erc20Asset.beneficiaries.length; i++) {
            if (erc20Asset.beneficiaries[i].account == beneficiary) {
                beneficiaryIndex = i;
                beneficiaryFound = true;
                break;
            }
        }
        require(beneficiaryFound, "LegacyAssetManager: Beneficiary not found");
        return beneficiaryIndex;
    }

    function setBeneficiary(
        string memory userTag,
        address _contract,
        uint256 tokenId,
        address newBeneficiary
    ) public {
        uint256 assetIndex = _findERC721AssetIndex(
            _msgSender(),
            _contract,
            tokenId
        );
        require(
            assetIndex < userAssets[_msgSender()].erc721Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        require(
            !userAssets[_msgSender()].erc721Assets[assetIndex].transferStatus,
            "LegacyAssetManager: Asset has been transferred"
        );
        userAssets[_msgSender()]
            .erc721Assets[assetIndex]
            .beneficiary = newBeneficiary;
        emit BeneficiaryChanged(
            userTag,
            _msgSender(),
            _contract,
            tokenId,
            newBeneficiary
        );
    }

    function setBeneficiaryPercentage(
        string memory userTag,
        address _contract,
        address beneficiary,
        uint8 newPercentage
    ) public {
        uint256 assetIndex = _findERC20AssetIndex(_msgSender(), _contract);
        ERC20Asset memory erc20Asset = userAssets[_msgSender()].erc20Assets[
            assetIndex
        ];
        uint256 beneficiaryIndex = _findBeneficiaryIndex(
            beneficiary,
            erc20Asset
        );
        uint8 currentPercentage = userAssets[_msgSender()]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;
        require(
            (erc20Asset.totalPercentage - currentPercentage) + newPercentage <=
                100,
            "LegacyAssetManager: Beneficiary percentage exceeds 100"
        );
        userAssets[_msgSender()]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage = newPercentage;
        userAssets[_msgSender()].erc20Assets[assetIndex].totalPercentage =
            (erc20Asset.totalPercentage - currentPercentage) +
            newPercentage;
        emit BeneficiaryPercentageChanged(
            userTag,
            _msgSender(),
            _contract,
            beneficiary,
            newPercentage
        );
    }

    function setVaultFactory(address _vaultFactory)
        public
        onlyRole(LEGACY_ADMIN)
    {
        vaultFactory = ILegacyVaultFactory(_vaultFactory);
    }

    function _verifySignature(bytes32 _hashedMessage, bytes memory signature)
        internal
        pure
        returns (address)
    {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        bytes32 prefixedHashMessage = keccak256(
            abi.encodePacked(prefix, _hashedMessage)
        );
        address signer = ecrecover(prefixedHashMessage, v, r, s);
        return signer;
    }

    function _splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
