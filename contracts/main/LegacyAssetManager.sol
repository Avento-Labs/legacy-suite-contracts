// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
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
    mapping(address => bool) public listedMembers;
    mapping(address => mapping(address => mapping(uint256 => bool)))
        public listedAssets;
    mapping(address => address[2]) public backupWallets;
    mapping(uint256 => bool) public burnedNonces;

    event AssetAdded(
        string userId,
        address indexed owner,
        address indexed _contract,
        uint256 indexed tokenId,
        uint256 totalAmount,
        address[] beneficiaries,
        uint8[] beneficiaryPercentages
    );

    event AssetRemoved(
        string userId,
        address indexed owner,
        address _contract,
        uint256 indexed tokenId
    );

    event AssetClaimed(
        string userId,
        address indexed owner,
        address claimer,
        address _contract,
        uint256 indexed tokenId,
        uint256 amount,
        address[] signers
    );

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

    event BeneficiaryChanged(
        string userId,
        address indexed owner,
        address _contract,
        uint256 tokenId,
        address newBeneficiary
    );

    /**
     * `tokenId` will be `0` in case of ERC20
     */
    event BeneficiaryPercentageChanged(
        string userId,
        address indexed owner,
        address _contract,
        uint256 indexed tokenId,
        address beneficiary,
        uint8 newpercentage
    );

    /**
     * Structs
     */
    struct Beneficiary {
        address account;
        uint8 allowedPercentage;
        uint256 totalAmount;
        uint256 claimedAmount;
    }

    struct Asset {
        address owner;
        address _contract;
        uint256 tokenId;
        uint256 totalAmount;
        uint256 totalRemainingAmount;
        uint8 totalPercentage;
        Beneficiary[] beneficiaries;
        uint256 remainingBeneficiaries;
    }

    struct UserAssets {
        Asset[] assets;
        bool backupWalletStatus;
        uint8 backupWalletIndex;
    }

    modifier onlyListedUser(address user) {
        require(listedMembers[user], "LegacyAssetManager: User not listed");
        _;
    }

    modifier assetNotListed(
        address user,
        address _contract,
        uint256 tokenId
    ) {
        require(
            !listedAssets[user][_contract][tokenId],
            "LegacyAssetManager: Asset is already listed"
        );
        _;
    }

    constructor(uint16 _minAdminSignature) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(LEGACY_ADMIN, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ASSET_AUTHORIZER, DEFAULT_ADMIN_ROLE);
        _setupRole(LEGACY_ADMIN, _msgSender());
        _setupRole(ASSET_AUTHORIZER, _msgSender());
        minAdminSignature = _minAdminSignature;
    }

    function createUserVault(
        string calldata userId,
        uint256 nonce,
        bytes calldata signature
    ) external whenNotPaused {
        _authorizeUser(_msgSender(), nonce, signature);
        vaultFactory.createVault(userId, _msgSender());
    }

    function addAssets(
        string calldata userId,
        address[] memory contracts,
        uint256[] memory tokenIds,
        uint256[] calldata totalAmount,
        address[][] calldata beneficiaryAddresses,
        uint8[][] calldata beneficiaryPercentages
    ) external whenNotPaused nonReentrant onlyListedUser(_msgSender()) {
        require(
            contracts.length == tokenIds.length &&
                tokenIds.length == beneficiaryAddresses.length &&
                beneficiaryAddresses.length == totalAmount.length &&
                totalAmount.length == beneficiaryPercentages.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        for (uint i = 0; i < contracts.length; i++) {
            _addAssetSingle(
                userId,
                contracts[i],
                tokenIds[i],
                totalAmount[i],
                beneficiaryAddresses[i],
                beneficiaryPercentages[i]
            );
        }
    }

    function _addAssetSingle(
        string memory userId,
        address _contract,
        uint256 tokenId,
        uint256 totalAmount,
        address[] memory beneficiaryAddresses,
        uint8[] calldata beneficiaryPercentages
    ) internal assetNotListed(_msgSender(), _contract, tokenId) {
        if (IERC165(_contract).supportsInterface(0x80ac58cd)) {
            require(
                IERC721(_contract).getApproved(tokenId) ==
                    vaultFactory.getVault(_msgSender()) ||
                    IERC721(_contract).isApprovedForAll(
                        _msgSender(),
                        vaultFactory.getVault(_msgSender())
                    ),
                "LegacyAssetManager: Asset not approved"
            );
            require(
                beneficiaryAddresses.length == 1 &&
                    beneficiaryPercentages.length == 1,
                "LegacyAssetManager: Cannot divide ERC721 asset"
            );
            require(
                IERC721(_contract).ownerOf(tokenId) == _msgSender(),
                "LegacyAssetManager: Caller is not the token owner"
            );
            Beneficiary[] memory _beneficiaries = new Beneficiary[](1);
            _beneficiaries[0] = Beneficiary(beneficiaryAddresses[0], 100, 0, 0);

            userAssets[_msgSender()].assets.push(
                Asset(
                    _msgSender(),
                    _contract,
                    tokenId,
                    0,
                    0,
                    100,
                    _beneficiaries,
                    1
                )
            );
            listedAssets[_msgSender()][_contract][tokenId] = true;

            emit AssetAdded(
                userId,
                _msgSender(),
                _contract,
                tokenId,
                0,
                beneficiaryAddresses,
                beneficiaryPercentages
            );
        } else if (IERC20(_contract).balanceOf(beneficiaryAddresses[0]) >= 0) {
            bool _erc1155 = IERC165(_contract).supportsInterface(0xd9b67a26);

            if (_erc1155) {
                require(
                    IERC1155(_contract).balanceOf(_msgSender(), tokenId) > 0 &&
                        IERC1155(_contract).balanceOf(_msgSender(), tokenId) >=
                        totalAmount,
                    "LegacyAssetManager: Insufficient token balance"
                );
            }
            require(
                beneficiaryAddresses.length == beneficiaryPercentages.length,
                "LegacyAssetManager: Arguments length mismatch"
            );
            if (!_erc1155) {
                uint256 _totalAmount = IERC20(_contract).allowance(
                    _msgSender(),
                    vaultFactory.getVault(_msgSender())
                );
                require(
                    _totalAmount > 0,
                    "LegacyAssetManager: Insufficient allowance for the asset"
                );
            }

            uint8 totalPercentage;
            Beneficiary[] memory _beneficiaries = new Beneficiary[](
                beneficiaryAddresses.length
            );
            for (uint i = 0; i < beneficiaryAddresses.length; i++) {
                require(
                    beneficiaryPercentages[i] > 0,
                    "LegacyAssetManager: Beneficiary percentage must be > 0"
                );
                uint256 amount = (totalAmount * beneficiaryPercentages[i]) /
                    100;
                _beneficiaries[i] = Beneficiary(
                    beneficiaryAddresses[i],
                    beneficiaryPercentages[i],
                    amount,
                    0
                );
                totalPercentage += beneficiaryPercentages[i];
                require(
                    totalPercentage <= 100,
                    "LegacyAssetManager: Beneficiary percentages exceed 100"
                );
            }
            if (!_erc1155) {
                userAssets[_msgSender()].assets.push(
                    Asset(
                        _msgSender(),
                        _contract,
                        0,
                        totalAmount,
                        totalAmount,
                        totalPercentage,
                        _beneficiaries,
                        beneficiaryAddresses.length
                    )
                );
                listedAssets[_msgSender()][_contract][0] = true;

                emit AssetAdded(
                    userId,
                    _msgSender(),
                    _contract,
                    0,
                    totalAmount,
                    beneficiaryAddresses,
                    beneficiaryPercentages
                );
            } else {
                userAssets[_msgSender()].assets.push(
                    Asset(
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
                listedAssets[_msgSender()][_contract][tokenId] = true;

                emit AssetAdded(
                    userId,
                    _msgSender(),
                    _contract,
                    tokenId,
                    totalAmount,
                    beneficiaryAddresses,
                    beneficiaryPercentages
                );
            }
        }
    }

    function removeAsset(
        string memory userId,
        address _contract,
        uint256 tokenId
    ) external nonReentrant {
        require(
            listedAssets[_msgSender()][_contract][tokenId],
            "LegacyAssetManager: Asset not listed"
        );
        uint256 assetIndex = _findAssetIndex(_msgSender(), _contract, tokenId);
        require(
            userAssets[_msgSender()].assets[assetIndex].remainingBeneficiaries >
                0,
            "LegacyAssetManager: Asset has been transferred to the beneficiaries"
        );
        userAssets[_msgSender()].assets[assetIndex] = userAssets[_msgSender()]
            .assets[userAssets[_msgSender()].assets.length - 1];
        userAssets[_msgSender()].assets.pop();
        listedAssets[_msgSender()][_contract][tokenId] = false;
        emit AssetRemoved(userId, _msgSender(), _contract, tokenId);
    }

    function addBackupWallet(
        string memory userId,
        uint8 index,
        address _backupWallet
    ) external onlyListedUser(_msgSender()) {
        require(
            !userAssets[_msgSender()].backupWalletStatus,
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
        for (uint i = 0; i < userAssets[owner].assets.length; i++) {
            if (
                IERC165(userAssets[owner].assets[i]._contract)
                    .supportsInterface(0xd9b67a26)
            ) {
                IERC1155 _contract = IERC1155(
                    userAssets[owner].assets[i]._contract
                );
                uint256 userBalance = _contract.balanceOf(
                    owner,
                    userAssets[owner].assets[i].tokenId
                );
                if (
                    userBalance > 0 &&
                    _contract.isApprovedForAll(owner, address(userVault))
                ) {
                    userVault.transferErc1155TokensAllowed(
                        address(_contract),
                        owner,
                        _msgSender(),
                        userAssets[owner].assets[i].tokenId,
                        userBalance
                    );
                }
            } else if (
                IERC165(userAssets[owner].assets[i]._contract)
                    .supportsInterface(0x80ac58cd)
            ) {
                IERC721 _contract = IERC721(
                    userAssets[owner].assets[i]._contract
                );
                uint256 tokenId = userAssets[owner].assets[i].tokenId;
                if (_contract.ownerOf(tokenId) == owner) {
                    userVault.transferErc721TokensAllowed(
                        address(_contract),
                        owner,
                        _msgSender(),
                        tokenId
                    );
                }
            } else if (
                IERC20(userAssets[owner].assets[i]._contract).balanceOf(
                    owner
                ) >= 0
            ) {
                IERC20 _contract = IERC20(
                    userAssets[owner].assets[i]._contract
                );
                uint256 userBalance = _contract.balanceOf(owner);
                uint256 allowance = _contract.allowance(
                    owner,
                    address(userVault)
                );
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
        }
        userAssets[owner].backupWalletStatus = true;
        if (backupWallets[owner][0] == _msgSender()) {
            userAssets[owner].backupWalletIndex = 0;
        } else {
            userAssets[owner].backupWalletIndex = 1;
        }
        emit BackupWalletSwitched(userId, owner, _msgSender());
    }

    function claimAsset(
        string memory userId,
        address owner,
        address _contract,
        uint256 tokenId,
        uint256 nonce,
        bytes[] calldata signatures
    ) external whenNotPaused nonReentrant {
        bytes32 hashedMessage = keccak256(
            abi.encodePacked(owner, _msgSender(), _contract, tokenId, nonce)
        );
        uint256 beneficiaryIndex;
        uint8 contractType;
        uint256 ownerBalance;
        uint256 allowedPercentage;
        uint256 remainingAmount;
        if (IERC165(_contract).supportsInterface(0x80ac58cd)) {
            contractType = 1; //ERC721
        } else if (IERC165(_contract).supportsInterface(0xd9b67a26)) {
            contractType = 2; //ERC1155
        } else if (IERC20(_contract).balanceOf(owner) >= 0) {
            contractType = 3; //ERC20
        } else {
            revert("LegacyAssetManager: Invalid contract");
        }
        address[] memory signers = _verifySigners(
            hashedMessage,
            nonce,
            signatures
        );
        uint256 assetIndex = _findAssetIndex(owner, _contract, tokenId);
        if (contractType == 2 || contractType == 3) {
            beneficiaryIndex = _findBeneficiaryIndex(
                _msgSender(),
                userAssets[owner].assets[assetIndex]
            );

            remainingAmount =
                userAssets[owner]
                    .assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .totalAmount -
                userAssets[owner]
                    .assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .claimedAmount;
            require(
                remainingAmount > 0,
                "LegacyAssetManager: Beneficiary has already claimed the asset"
            );
        } else if (contractType == 1) {
            require(
                userAssets[owner].assets[assetIndex].remainingBeneficiaries ==
                    0,
                "LegacyAssetManager: Beneficiary has already claimed the asset"
            );
            require(
                userAssets[owner].assets[assetIndex].beneficiaries[0].account ==
                    _msgSender(),
                "LegacyAssetManager: Unauthorized claim call"
            );
        }

        address vaultAddress = vaultFactory.getVault(owner);
        address currentOwner;
        if (userAssets[owner].backupWalletStatus) {
            currentOwner = backupWallets[owner][
                userAssets[owner].backupWalletIndex
            ];
        } else {
            currentOwner = owner;
        }
        if (contractType == 2) {
            ownerBalance = IERC1155(_contract).balanceOf(currentOwner, tokenId);
            require(
                ownerBalance > 0,
                "LegacyAssetManager: Owner has zero balance for this asset"
            );
        }
        if (contractType == 3) {
            ownerBalance = IERC20(_contract).balanceOf(currentOwner);
            uint256 allowance = IERC20(_contract).allowance(
                currentOwner,
                vaultAddress
            );
            require(
                ownerBalance > 0 && allowance > 0,
                "LegacyAssetManager: Owner has zero balance or zero allowance for this asset"
            );

            if (
                userAssets[owner].assets[assetIndex].beneficiaries.length ==
                userAssets[owner].assets[assetIndex].remainingBeneficiaries &&
                allowance != userAssets[owner].assets[assetIndex].totalAmount
            ) {
                userAssets[owner].assets[assetIndex].totalAmount = allowance;
            }
        }
        if (contractType == 2 || contractType == 3) {
            allowedPercentage = userAssets[owner]
                .assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .allowedPercentage;
        }
        if (contractType == 3) {
            if (
                userAssets[owner]
                    .assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .claimedAmount == 0
            ) {
                uint256 currentAmount = (userAssets[owner]
                    .assets[assetIndex]
                    .totalAmount * allowedPercentage) / 100;
                if (
                    currentAmount !=
                    userAssets[owner]
                        .assets[assetIndex]
                        .beneficiaries[beneficiaryIndex]
                        .totalAmount
                ) {
                    userAssets[owner]
                        .assets[assetIndex]
                        .beneficiaries[beneficiaryIndex]
                        .totalAmount = currentAmount;
                }
            }
        }
        uint256 dueAmount;
        if (contractType == 2 || contractType == 3) {
            if (
                ownerBalance >=
                userAssets[owner].assets[assetIndex].totalRemainingAmount ||
                ((ownerBalance * allowedPercentage) / 100) > remainingAmount
            ) {
                dueAmount = remainingAmount;
            } else {
                dueAmount = (ownerBalance * allowedPercentage) / 100;
            }

            userAssets[owner]
                .assets[assetIndex]
                .totalRemainingAmount -= dueAmount;
            userAssets[owner]
                .assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .claimedAmount += dueAmount;
            if (
                userAssets[owner]
                    .assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .claimedAmount ==
                userAssets[owner]
                    .assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .totalAmount
            ) {
                userAssets[owner].assets[assetIndex].remainingBeneficiaries--;
            }
        }
        if (contractType == 1) {
            ILegacyVault(vaultAddress).transferErc721TokensAllowed(
                _contract,
                currentOwner,
                _msgSender(),
                tokenId
            );
            userAssets[owner].assets[assetIndex].remainingBeneficiaries = 0;
            emit AssetClaimed(
                userId,
                owner,
                _msgSender(),
                _contract,
                tokenId,
                0,
                signers
            );
        } else if (contractType == 2) {
            ILegacyVault(vaultAddress).transferErc1155TokensAllowed(
                _contract,
                currentOwner,
                _msgSender(),
                tokenId,
                dueAmount
            );

            emit AssetClaimed(
                userId,
                owner,
                _msgSender(),
                _contract,
                tokenId,
                dueAmount,
                signers
            );
        } else if (contractType == 3) {
            ILegacyVault(vaultAddress).transferErc20TokensAllowed(
                _contract,
                currentOwner,
                _msgSender(),
                dueAmount
            );

            emit AssetClaimed(
                userId,
                owner,
                _msgSender(),
                _contract,
                0,
                dueAmount,
                signers
            );
        }
    }

    function _findAssetIndex(
        address user,
        address _contract,
        uint256 tokenId
    ) internal view returns (uint256) {
        for (uint i = 0; i < userAssets[user].assets.length; i++) {
            if (
                userAssets[user].assets[i]._contract == _contract &&
                userAssets[user].assets[i].tokenId == tokenId
            ) {
                return i;
            }
        }
        revert("LegacyAssetManager: Asset not found");
    }

    function _findBeneficiaryIndex(
        address beneficiary,
        Asset memory _asset
    ) internal pure returns (uint256) {
        for (uint i = 0; i < _asset.beneficiaries.length; i++) {
            if (_asset.beneficiaries[i].account == beneficiary) {
                return i;
            }
        }
        revert("LegacyAssetManager: Beneficiary not found");
    }

    function setBeneficiaryPercentage(
        string memory userId,
        address _contract,
        uint256 tokenId,
        address beneficiary,
        uint8 newPercentage
    ) external {
        uint256 assetIndex = _findAssetIndex(_msgSender(), _contract, tokenId);
        uint256 beneficiaryIndex = _findBeneficiaryIndex(
            beneficiary,
            userAssets[_msgSender()].assets[assetIndex]
        );
        require(
            userAssets[_msgSender()]
                .assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .totalAmount -
                userAssets[_msgSender()]
                    .assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .claimedAmount >
                0,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );
        uint8 currentPercentage = userAssets[_msgSender()]
            .assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;
        require(
            (userAssets[_msgSender()].assets[assetIndex].totalPercentage -
                currentPercentage) +
                newPercentage <=
                100,
            "LegacyAssetManager: Beneficiary percentage exceeds total of 100"
        );
        userAssets[_msgSender()]
            .assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage = newPercentage;
        userAssets[_msgSender()].assets[assetIndex].totalPercentage =
            (userAssets[_msgSender()].assets[assetIndex].totalPercentage -
                currentPercentage) +
            newPercentage;
        emit BeneficiaryPercentageChanged(
            userId,
            _msgSender(),
            _contract,
            tokenId,
            beneficiary,
            newPercentage
        );
    }

    function setERC721Beneficiary(
        string memory userId,
        address _contract,
        uint256 tokenId,
        address newBeneficiary
    ) external {
        uint256 assetIndex = _findAssetIndex(_msgSender(), _contract, tokenId);
        require(
            userAssets[_msgSender()]
                .assets[assetIndex]
                .remainingBeneficiaries == 0,
            "LegacyAssetManager: Asset has been claimed"
        );
        Beneficiary memory _beneficiaries;
        _beneficiaries.account = newBeneficiary;
        _beneficiaries.allowedPercentage = 100;
        _beneficiaries.totalAmount = 0;
        _beneficiaries.claimedAmount = 0;
        userAssets[_msgSender()].assets[assetIndex].beneficiaries[
                0
            ] = _beneficiaries;
        emit BeneficiaryChanged(
            userId,
            _msgSender(),
            _contract,
            tokenId,
            newBeneficiary
        );
    }

    function setVaultFactory(
        address _vaultFactory
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultFactory = ILegacyVaultFactory(_vaultFactory);
    }

    function setMinAdminSignature(
        uint16 _minAdminSignature
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minAdminSignature = _minAdminSignature;
    }

    function _authorizeUser(
        address user,
        uint256 nonce,
        bytes calldata signature
    ) internal {
        if (!listedMembers[user]) {
            require(
                !burnedNonces[nonce],
                "LegacyAssetManger: Nonce already used"
            );
            bytes32 hashedMessage = keccak256(abi.encodePacked(user, nonce));
            address signer = _verifySignature(hashedMessage, signature);
            require(
                hasRole(ASSET_AUTHORIZER, signer),
                "LegacyAssetManager: Unauthorized signature"
            );
            burnedNonces[nonce] = true;
            listedMembers[user] = true;
        }
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

    function _verifySignature(
        bytes32 _hashedMessage,
        bytes calldata signature
    ) internal pure returns (address) {
        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(
            _hashedMessage
        );
        return ECDSA.recover(ethSignedMessageHash, signature);
    }

    function pauseContract()
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _pause();
    }

    function unpauseContract()
        external
        whenPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _unpause();
    }

    function withdrawEther(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(to).transfer(address(this).balance);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
