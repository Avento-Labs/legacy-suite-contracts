// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/ILegacyVaultFactory.sol";
import "../interfaces/ILegacyVault.sol";

contract LegacyAssetManager is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant LEGACY_ADMIN = keccak256("LEGACY_ADMIN");
    bytes32 public constant ASSET_AUTHORIZER = keccak256("ASSET_AUTHORIZER");

    ILegacyVaultFactory public vaultFactory;
    uint16 public minAdminSignature;
    mapping(address => UserAssets) public userAssets;
    mapping(address => mapping(uint256 => bool)) public listedAssets;
    mapping(address => bool) public listedMembers;
    mapping(address => address) public backupWallets;
    mapping(uint256 => bool) public burnedNonces;

    event ERC1155AssetAdded(
        string userTag,
        address indexed owner,
        address indexed _contract,
        uint256 indexed tokenId,
        uint256 totalAmount,
        address[] beneficiaries,
        uint8[] beneficiaryPercentages,
        uint8 totalPercentage
    );
    event ERC721AssetAdded(
        string userTag,
        address indexed owner,
        address indexed _contract,
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

    event ERC1155AssetRemoved(
        string userTag,
        address indexed owner,
        address _contract,
        uint256 indexed tokenId,
        uint256 totalAmount,
        uint256 remainingBeneficiaries
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

    event ERC1155AssetClaimed(
        string userTag,
        address indexed owner,
        address claimer,
        address _contract,
        uint256 indexed tokenId,
        uint256 amount,
        address[] signers
    );

    event ERC721AssetClaimed(
        string userTag,
        address indexed owner,
        address claimer,
        address _contract,
        uint256 indexed tokenId,
        address[] signers
    );

    event ERC20AssetClaimed(
        string userTag,
        address indexed owner,
        address indexed claimer,
        address _contract,
        uint256 amount,
        address[] signers
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
    struct Beneficiary {
        address account;
        uint8 allowedPercentage;
        uint256 remainingAmount;
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
    }

    constructor(address _vaultFactory, uint16 _minAdminSignature) {
        vaultFactory = ILegacyVaultFactory(_vaultFactory);
        minAdminSignature = _minAdminSignature;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(LEGACY_ADMIN, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ASSET_AUTHORIZER, DEFAULT_ADMIN_ROLE);
        _setupRole(LEGACY_ADMIN, _msgSender());
        _setupRole(ASSET_AUTHORIZER, _msgSender());
    }

    function addERC1155Assets(
        string memory userTag,
        address[] memory contracts,
        uint256[] memory tokenIds,
        uint256[] calldata totalAmount,
        address[][] calldata beneficiaryAddresses,
        uint8[][] calldata beneficiaryPercentages,
        bytes32 hashedMessage,
        bytes calldata signature
    ) external nonReentrant {
        require(
            contracts.length == tokenIds.length &&
                tokenIds.length == beneficiaryAddresses.length &&
                beneficiaryAddresses.length == totalAmount.length &&
                totalAmount.length == beneficiaryPercentages.length,
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
            _addERC1155Single(
                userTag,
                contracts[i],
                tokenIds[i],
                totalAmount[i],
                beneficiaryAddresses[i],
                beneficiaryPercentages[i]
            );
        }
    }

    function _addERC1155Single(
        string memory userTag,
        address _contract,
        uint256 tokenId,
        uint256 totalAmount,
        address[] calldata beneficiaryAddresses,
        uint8[] calldata beneficiaryPercentages
    ) internal {
        require(
            !listedAssets[_contract][tokenId],
            "LegacyAssetManager: Asset already added"
        );
        require(
            IERC1155(_contract).supportsInterface(0xd9b67a26),
            "LegacyAssetManager: Contract is not a valid ERC1155 contract"
        );
        require(
            IERC1155(_contract).balanceOf(_msgSender(), tokenId) > 0 &&
                IERC1155(_contract).balanceOf(_msgSender(), tokenId) >=
                totalAmount,
            "LegacyAssetManager: Insufficient token balance"
        );
        require(
            IERC1155(_contract).isApprovedForAll(
                _msgSender(),
                vaultFactory.deployedContractFromMember(_msgSender())
            ),
            "LegacyAssetManager: Asset not approved"
        );
        uint8 totalPercentage;
        Beneficiary[] memory _beneficiaries = new Beneficiary[](
            beneficiaryAddresses.length
        );
        for (uint i = 0; i < beneficiaryAddresses.length; i++) {
            require(
                beneficiaryPercentages[i] > 0,
                "LegacyAssetManager: Beneficiary percentage must be > 0"
            );
            uint256 remainingAmount = (totalAmount *
                beneficiaryPercentages[i]) / 100;
            _beneficiaries[i] = Beneficiary(
                beneficiaryAddresses[i],
                beneficiaryPercentages[i],
                remainingAmount
            );
            totalPercentage += beneficiaryPercentages[i];
            require(
                totalPercentage <= 100,
                "LegacyAssetManager: Beneficiary percentages exceed 100"
            );
        }
        userAssets[_msgSender()].erc1155Assets.push(
            ERC1155Asset(
                _msgSender(),
                _contract,
                tokenId,
                totalAmount,
                totalAmount,
                totalPercentage,
                _beneficiaries,
                beneficiaryAddresses.length
            )
        );
        listedAssets[_contract][tokenId] = true;
        emit ERC1155AssetAdded(
            userTag,
            _msgSender(),
            _contract,
            tokenId,
            totalAmount,
            beneficiaryAddresses,
            beneficiaryPercentages,
            totalPercentage
        );
    }

    function addERC721Assets(
        string memory userTag,
        address[] calldata _contracts,
        uint256[] calldata tokenIds,
        address[] calldata beneficiaries,
        bytes32 hashedMessage,
        bytes calldata signature
    ) external nonReentrant {
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
        emit ERC721AssetAdded(
            userTag,
            _msgSender(),
            _contract,
            tokenId,
            beneficiary
        );
    }

    function addERC20Assets(
        string memory userTag,
        address[] calldata contracts,
        uint256[] calldata totalAmount,
        address[][] calldata beneficiaryAddresses,
        uint8[][] calldata beneficiaryPercentages,
        bytes32 hashedMessage,
        bytes calldata signature
    ) external nonReentrant {
        require(
            contracts.length == beneficiaryAddresses.length &&
                beneficiaryAddresses.length == totalAmount.length &&
                totalAmount.length == beneficiaryPercentages.length,
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
                beneficiaryAddresses[i],
                beneficiaryPercentages[i]
            );
        }
    }

    function _addERC20Single(
        string memory userTag,
        address _contract,
        address[] calldata beneficiaryAddresses,
        uint8[] calldata beneficiaryPercentages
    ) internal {
        require(
            beneficiaryAddresses.length == beneficiaryPercentages.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        require(
            _findERC20AssetIndex(_msgSender(), _contract) ==
                userAssets[_msgSender()].erc20Assets.length,
            "LegacyAssetManager: Asset already added"
        );
        uint256 totalAmount = IERC20(_contract).allowance(
            _msgSender(),
            vaultFactory.deployedContractFromMember(_msgSender())
        );
        require(
            totalAmount > 0,
            "LegacyAssetManager: Insufficient allowance for the asset"
        );

        uint8 totalPercentage;
        Beneficiary[] memory _erc20Beneficiaries = new Beneficiary[](
            beneficiaryAddresses.length
        );
        for (uint i = 0; i < beneficiaryAddresses.length; i++) {
            require(
                beneficiaryPercentages[i] > 0,
                "LegacyAssetManager: Beneficiary percentage must be > 0"
            );
            uint256 remainingAmount = (totalAmount *
                beneficiaryPercentages[i]) / 100;
            _erc20Beneficiaries[i] = Beneficiary(
                beneficiaryAddresses[i],
                beneficiaryPercentages[i],
                remainingAmount
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
                totalAmount,
                totalPercentage,
                _erc20Beneficiaries,
                beneficiaryAddresses.length
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

    function removeERC1155Single(
        string memory userTag,
        address _contract,
        uint256 tokenId
    ) external nonReentrant {
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
        require(
            userAssets[_msgSender()]
                .erc1155Assets[assetIndex]
                .remainingBeneficiaries > 0,
            "LegacyAssetManager: Asset has been transferred to the beneficiaries"
        );
        userAssets[_msgSender()].erc1155Assets[assetIndex] = userAssets[
            _msgSender()
        ].erc1155Assets[userAssets[_msgSender()].erc1155Assets.length - 1];
        userAssets[_msgSender()].erc1155Assets.pop();
        listedAssets[_contract][tokenId] = false;
        emit ERC1155AssetRemoved(
            userTag,
            _msgSender(),
            _contract,
            tokenId,
            userAssets[_msgSender()].erc1155Assets[assetIndex].totalAmount,
            userAssets[_msgSender()]
                .erc1155Assets[assetIndex]
                .remainingBeneficiaries
        );
    }

    function removeERC721Single(
        string memory userTag,
        address _contract,
        uint256 tokenId
    ) external nonReentrant {
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
        require(
            !userAssets[_msgSender()].erc721Assets[assetIndex].transferStatus,
            "LegacyAssetManager: Asset has been transferred to the beneficiary"
        );
        userAssets[_msgSender()].erc721Assets[assetIndex] = userAssets[
            _msgSender()
        ].erc721Assets[userAssets[_msgSender()].erc721Assets.length - 1];
        userAssets[_msgSender()].erc721Assets.pop();
        listedAssets[_contract][tokenId] = false;
        emit ERC721AssetRemoved(userTag, _msgSender(), _contract, tokenId);
    }

    function removeERC20Single(string memory userTag, address _contract)
        external
        nonReentrant
    {
        uint256 assetIndex = _findERC20AssetIndex(_msgSender(), _contract);
        require(
            assetIndex < userAssets[_msgSender()].erc20Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        require(
            userAssets[_msgSender()]
                .erc20Assets[assetIndex]
                .remainingBeneficiaries > 0,
            "LegacyAssetManager: Asset has been transferred to the beneficiaries"
        );
        userAssets[_msgSender()].erc20Assets[assetIndex] = userAssets[
            _msgSender()
        ].erc20Assets[userAssets[_msgSender()].erc20Assets.length - 1];
        userAssets[_msgSender()].erc20Assets.pop();
        emit ERC20AssetRemoved(
            userTag,
            _msgSender(),
            _contract,
            userAssets[_msgSender()].erc20Assets[assetIndex].totalAmount,
            userAssets[_msgSender()]
                .erc20Assets[assetIndex]
                .remainingBeneficiaries
        );
    }

    function _findERC1155AssetIndex(
        address user,
        address _contract,
        uint256 tokenId
    ) internal view returns (uint256) {
        for (uint i = 0; i < userAssets[user].erc1155Assets.length; i++) {
            if (
                userAssets[user].erc1155Assets[i]._contract == _contract &&
                userAssets[user].erc1155Assets[i].tokenId == tokenId
            ) {
                return i;
            }
        }
        return userAssets[user].erc1155Assets.length;
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

    function getERC721Asset(
        address user,
        address _contract,
        uint256 tokenId
    ) external view returns (ERC721Asset memory) {
        uint256 assetIndex = _findERC721AssetIndex(user, _contract, tokenId);
        require(
            assetIndex < userAssets[user].erc721Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        return userAssets[user].erc721Assets[assetIndex];
    }

    function getERC20Asset(address user, address _contract)
        external
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

    function getBackupWallet(address owner) external view returns (address) {
        return backupWallets[owner];
    }

    function setBackupWallet(string memory userTag, address _backupWallet)
        external
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

    function switchBackupWallet(string memory userTag, address owner) external {
        require(
            _msgSender() == backupWallets[owner],
            "LegacyAssetManager: Unauthorized backup wallet transfer call"
        );
        ILegacyVault userVault = ILegacyVault(
            ILegacyVaultFactory(vaultFactory).deployedContractFromMember(owner)
        );
        for (uint i = 0; i < userAssets[owner].erc1155Assets.length; i++) {
            IERC1155 _contract = IERC1155(
                userAssets[owner].erc1155Assets[i]._contract
            );
            uint256 userBalance = _contract.balanceOf(
                owner,
                userAssets[owner].erc1155Assets[i].tokenId
            );
            if (
                userBalance > 0 &&
                _contract.isApprovedForAll(owner, address(userVault))
            ) {
                userVault.transferErc1155TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    userAssets[owner].erc1155Assets[i].tokenId,
                    userBalance
                );
            }
        }
        for (uint i = 0; i < userAssets[owner].erc721Assets.length; i++) {
            IERC721 _contract = IERC721(
                userAssets[owner].erc721Assets[i]._contract
            );
            uint256 tokenId = userAssets[owner].erc721Assets[i].tokenId;
            if (_contract.ownerOf(tokenId) == owner) {
                userVault.transferErc721TokensAllowed(
                    address(_contract),
                    owner,
                    _msgSender(),
                    tokenId
                );
            }
        }
        for (uint i = 0; i < userAssets[owner].erc20Assets.length; i++) {
            IERC20 _contract = IERC20(
                userAssets[owner].erc20Assets[i]._contract
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
        userAssets[owner].backupWalletStatus = true;
        emit BackupWalletSwitched(userTag, owner, _msgSender());
    }

    function claimERC1155Asset(
        string memory userTag,
        address owner,
        address _contract,
        uint256 tokenId,
        uint256 nonce,
        bytes[] calldata signatures
    ) external nonReentrant {
        bytes32 hashedMessage = keccak256(
            abi.encodePacked(owner, _msgSender(), _contract, tokenId, nonce)
        );
        address[] memory signers = _verifySigners(
            hashedMessage,
            nonce,
            signatures
        );
        uint256 assetIndex = _findERC1155AssetIndex(owner, _contract, tokenId);
        require(
            assetIndex < userAssets[owner].erc1155Assets.length,
            "LegacyAssetManager: Asset not found"
        );

        address vaultAddress = vaultFactory.deployedContractFromMember(owner);

        address currentOwner;
        if (userAssets[owner].backupWalletStatus) {
            currentOwner = backupWallets[owner];
        } else {
            currentOwner = owner;
        }
        uint256 ownerBalance = IERC1155(_contract).balanceOf(
            currentOwner,
            tokenId
        );
        bool isApprovedForAll = IERC1155(_contract).isApprovedForAll(
            currentOwner,
            vaultAddress
        );
        require(
            ownerBalance > 0 && isApprovedForAll,
            "LegacyAssetManager: Owner has zero balance or approval is not set for this asset"
        );

        uint256 beneficiaryIndex = _findERC1155BeneficiaryIndex(
            _msgSender(),
            userAssets[owner].erc1155Assets[assetIndex]
        );
        require(
            userAssets[owner]
                .erc1155Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount > 0,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );

        uint8 allowedPercentage = userAssets[owner]
            .erc1155Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;
        uint256 currentAmount = (userAssets[owner]
            .erc1155Assets[assetIndex]
            .totalAmount * allowedPercentage) / 100;
        require(
            currentAmount > 0,
            "LegacyAssetManager: Beneficiary has zero claimable amount for this asset"
        );

        if (
            currentAmount !=
            userAssets[owner]
                .erc1155Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount
        ) {
            userAssets[owner]
                .erc1155Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount = currentAmount;
        }

        uint256 dueAmount;
        if (
            ownerBalance >=
            userAssets[owner].erc1155Assets[assetIndex].totalRemainingAmount
        ) {
            dueAmount = userAssets[owner]
                .erc1155Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount;
        } else {
            dueAmount = (ownerBalance * allowedPercentage) / 100;
        }

        userAssets[owner]
            .erc1155Assets[assetIndex]
            .totalRemainingAmount -= dueAmount;
        userAssets[owner]
            .erc1155Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .remainingAmount -= dueAmount;
        userAssets[owner].erc1155Assets[assetIndex].remainingBeneficiaries--;

        ILegacyVault(vaultAddress).transferErc1155TokensAllowed(
            _contract,
            currentOwner,
            _msgSender(),
            tokenId,
            dueAmount
        );

        emit ERC1155AssetClaimed(
            userTag,
            owner,
            _msgSender(),
            _contract,
            tokenId,
            dueAmount,
            signers
        );
    }

    function claimERC721Asset(
        string memory userTag,
        address owner,
        address _contract,
        uint256 tokenId,
        uint256 nonce,
        bytes[] calldata signatures
    ) external nonReentrant {
        bytes32 hashedMessage = keccak256(
            abi.encodePacked(owner, _msgSender(), _contract, tokenId, nonce)
        );
        address[] memory signers = _verifySigners(
            hashedMessage,
            nonce,
            signatures
        );
        uint256 assetIndex = _findERC721AssetIndex(owner, _contract, tokenId);
        require(
            assetIndex < userAssets[owner].erc721Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        require(
            !userAssets[owner].erc721Assets[assetIndex].transferStatus,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );
        require(
            userAssets[owner].erc721Assets[assetIndex].beneficiary ==
                _msgSender(),
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
            tokenId,
            signers
        );
    }

    function claimERC20Asset(
        string memory userTag,
        address owner,
        address _contract,
        uint256 nonce,
        bytes[] calldata signatures
    ) external nonReentrant {
        bytes32 hashedMessage = keccak256(
            abi.encodePacked(owner, _msgSender(), _contract, nonce)
        );
        address[] memory signers = _verifySigners(
            hashedMessage,
            nonce,
            signatures
        );
        uint256 assetIndex = _findERC20AssetIndex(owner, _contract);
        require(
            assetIndex < userAssets[owner].erc20Assets.length,
            "LegacyAssetManager: Asset not found"
        );

        address vaultAddress = vaultFactory.deployedContractFromMember(owner);

        address currentOwner;
        if (userAssets[owner].backupWalletStatus) {
            currentOwner = backupWallets[owner];
        } else {
            currentOwner = owner;
        }
        uint256 ownerBalance = IERC20(_contract).balanceOf(currentOwner);
        uint256 allowance = IERC20(_contract).allowance(
            currentOwner,
            vaultAddress
        );
        require(
            ownerBalance > 0 && allowance > 0,
            "LegacyAssetManager: Owner has zero balance or zero allowance for this asset"
        );

        if (
            userAssets[owner].erc20Assets[assetIndex].beneficiaries.length ==
            userAssets[owner].erc20Assets[assetIndex].remainingBeneficiaries &&
            allowance != userAssets[owner].erc20Assets[assetIndex].totalAmount
        ) {
            userAssets[owner].erc20Assets[assetIndex].totalAmount = allowance;
        }

        uint256 beneficiaryIndex = _findERC20BeneficiaryIndex(
            _msgSender(),
            userAssets[owner].erc20Assets[assetIndex]
        );
        require(
            userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount > 0,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );

        uint8 allowedPercentage = userAssets[owner]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;
        uint256 currentAmount = (userAssets[owner]
            .erc20Assets[assetIndex]
            .totalAmount * allowedPercentage) / 100;

        if (
            currentAmount !=
            userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount
        ) {
            userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount = currentAmount;
        }

        uint256 dueAmount;
        if (
            ownerBalance >=
            userAssets[owner].erc20Assets[assetIndex].totalRemainingAmount
        ) {
            dueAmount = userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .remainingAmount;
        } else {
            dueAmount = (ownerBalance * allowedPercentage) / 100;
        }

        userAssets[owner]
            .erc20Assets[assetIndex]
            .totalRemainingAmount -= dueAmount;
        userAssets[owner]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .remainingAmount -= dueAmount;
        userAssets[owner].erc20Assets[assetIndex].remainingBeneficiaries--;

        ILegacyVault(vaultAddress).transferErc20TokensAllowed(
            _contract,
            currentOwner,
            _msgSender(),
            dueAmount
        );

        emit ERC20AssetClaimed(
            userTag,
            owner,
            _msgSender(),
            _contract,
            dueAmount,
            signers
        );
    }

    function _findERC1155BeneficiaryIndex(
        address beneficiary,
        ERC1155Asset memory erc1155Asset
    ) internal pure returns (uint256) {
        uint256 beneficiaryIndex;
        bool beneficiaryFound;
        for (uint i = 0; i < erc1155Asset.beneficiaries.length; i++) {
            if (erc1155Asset.beneficiaries[i].account == beneficiary) {
                beneficiaryIndex = i;
                beneficiaryFound = true;
                break;
            }
        }
        require(beneficiaryFound, "LegacyAssetManager: Beneficiary not found");
        return beneficiaryIndex;
    }

    function _findERC20BeneficiaryIndex(
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
    ) external {
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
    ) external {
        uint256 assetIndex = _findERC20AssetIndex(_msgSender(), _contract);
        require(
            assetIndex < userAssets[_msgSender()].erc20Assets.length,
            "LegacyAssetManager: Asset not found"
        );
        uint256 beneficiaryIndex = _findERC20BeneficiaryIndex(
            beneficiary,
            userAssets[_msgSender()].erc20Assets[assetIndex]
        );
        uint8 currentPercentage = userAssets[_msgSender()]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;
        require(
            (userAssets[_msgSender()].erc20Assets[assetIndex].totalPercentage -
                currentPercentage) +
                newPercentage <=
                100,
            "LegacyAssetManager: Beneficiary percentage exceeds 100"
        );
        userAssets[_msgSender()]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage = newPercentage;
        userAssets[_msgSender()].erc20Assets[assetIndex].totalPercentage =
            (userAssets[_msgSender()].erc20Assets[assetIndex].totalPercentage -
                currentPercentage) +
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
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        vaultFactory = ILegacyVaultFactory(_vaultFactory);
    }

    function setMinSignature(uint16 _minAdminSignature)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        minAdminSignature = _minAdminSignature;
    }

    function _verifySigners(
        bytes32 hashedMessage,
        uint256 nonce,
        bytes[] calldata signatures
    ) internal returns (address[] memory) {
        require(
            signatures.length >= minAdminSignature,
            "LegacyAssetManger: Signatures are less than minimum required"
        );
        require(!burnedNonces[nonce], "LegacyAssetManger: Nonce already used");
        address[] memory signers = new address[](signatures.length);
        for (uint i = 0; i < signatures.length; i++) {
            address signer = _verifySignature(hashedMessage, signatures[i]);
            require(
                hasRole(LEGACY_ADMIN, signer),
                "LegacyAssetManager: Unauthorized signature"
            );
            signers[i] = signer;
            for (uint j = signers.length - 1; j != 0; j--) {
                require(
                    signers[j] != signers[j - 1],
                    "LegacyAssetManager: Duplicate signature not allowed"
                );
            }
        }
        burnedNonces[nonce] = true;
        return signers;
    }

    function _verifySignature(bytes32 _hashedMessage, bytes calldata signature)
        internal
        pure
        returns (address)
    {
        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(
            _hashedMessage
        );
        address signer = ECDSA.recover(ethSignedMessageHash, signature);
        return signer;
    }
}
