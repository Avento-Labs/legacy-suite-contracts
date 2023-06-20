// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/ILegacyAssetManagerERC20.sol";
import "../interfaces/ILegacyVaultFactory.sol";
import "../interfaces/ILegacyVault.sol";
import "../interfaces/ILegacyAssetManager.sol";


contract LegacyAssetManagerERC20 is ILegacyAssetManagerERC20 ,AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant LEGACY_ADMIN = keccak256("LEGACY_ADMIN");
    bytes32 public constant ASSET_AUTHORIZER = keccak256("ASSET_AUTHORIZER");

    ILegacyVaultFactory public vaultFactory;
    uint16 public minAdminSignature;
    mapping(address => UserAssets) public userAssets;
    mapping(address => bool) public listedMembers;
    mapping(address => mapping(address => mapping(uint256 => bool)))public listedAssets;
    mapping(uint256 => bool) public burnedNonces;

    
    event ERC20AssetAdded(
        string userId,
        address indexed owner,
        address indexed _contract,
        uint256 totalAmount,
        address[] beneficiaries,
        uint8[] beneficiaryPercentages
    );

    event ERC20AssetRemoved(
        string userId,
        address indexed owner,
        address indexed _contract
    );

    event ERC20AssetClaimed(
        string userId,
        address indexed owner,
        address indexed claimer,
        address _contract,
        uint256 amount,
        address[] signers
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

    
       
    function addERC20Assets(
        string calldata userId,
        address[] calldata contracts,
        address[][] calldata beneficiaryAddresses,
        uint8[][] calldata beneficiaryPercentages
    ) external whenNotPaused nonReentrant onlyListedUser(_msgSender()) {
        require(
            contracts.length == beneficiaryAddresses.length &&
                beneficiaryAddresses.length == beneficiaryPercentages.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        for (uint i = 0; i < contracts.length; i++) {
            _addERC20Single(
                userId,
                contracts[i],
                beneficiaryAddresses[i],
                beneficiaryPercentages[i]
            );
        }
    }

    function _addERC20Single(
        string memory userId,
        address _contract,
        address[] calldata beneficiaryAddresses,
        uint8[] calldata beneficiaryPercentages
    ) internal assetNotListed(_msgSender(), _contract, 0) {
        require(
            beneficiaryAddresses.length == beneficiaryPercentages.length,
            "LegacyAssetManager: Arguments length mismatch"
        );

        uint256 totalAmount = IERC20(_contract).allowance(
            _msgSender(),
            vaultFactory.getVault(_msgSender())
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
            uint256 amount = (totalAmount * beneficiaryPercentages[i]) / 100;
            _erc20Beneficiaries[i] = Beneficiary(
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
        listedAssets[_msgSender()][_contract][0] = true;

        emit ERC20AssetAdded(
            userId,
            _msgSender(),
            _contract,
            totalAmount,
            beneficiaryAddresses,
            beneficiaryPercentages
        );
    }

    
    function removeERC20Asset(
        string memory userId,
        address _contract
    ) external nonReentrant {
        uint256 assetIndex = _findERC20AssetIndex(_msgSender(), _contract);
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
        listedAssets[_msgSender()][_contract][0] = false;
        emit ERC20AssetRemoved(userId, _msgSender(), _contract);
    }



    function claimERC20Asset(
        string memory userId,
        address owner,
        address _contract,
        uint256 nonce,
        bytes[] calldata signatures
    ) external whenNotPaused nonReentrant {
        bytes32 hashedMessage = keccak256(
            abi.encodePacked(owner, _msgSender(), _contract, nonce)
        );
        uint256 assetIndex = _findERC20AssetIndex(owner, _contract);

        uint256 beneficiaryIndex = _findERC20BeneficiaryIndex(
            _msgSender(),
            userAssets[owner].erc20Assets[assetIndex]
        );

        uint256 remainingAmount = userAssets[owner]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .totalAmount -
            userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .claimedAmount;
        require(
            remainingAmount > 0,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );

        address vaultAddress = vaultFactory.getVault(owner);
        address currentOwner;
        if (userAssets[owner].backupWalletStatus) {
            currentOwner = ILegacyVault(ILegacyVaultFactory(vaultFactory).getVault(owner)).getBackupWallet(owner)[
                userAssets[owner].backupWalletIndex
            ];
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

        uint8 allowedPercentage = userAssets[owner]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;

        if (
            userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .claimedAmount == 0
        ) {
            uint256 currentAmount = (userAssets[owner]
                .erc20Assets[assetIndex]
                .totalAmount * allowedPercentage) / 100;
            if (
                currentAmount !=
                userAssets[owner]
                    .erc20Assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .totalAmount
            ) {
                userAssets[owner]
                    .erc20Assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .totalAmount = currentAmount;
            }
        }

        uint256 dueAmount;
        if (
            ownerBalance >=
            userAssets[owner].erc20Assets[assetIndex].totalRemainingAmount ||
            ((ownerBalance * allowedPercentage) / 100) > remainingAmount
        ) {
            dueAmount = remainingAmount;
        } else {
            dueAmount = (ownerBalance * allowedPercentage) / 100;
        }

        userAssets[owner]
            .erc20Assets[assetIndex]
            .totalRemainingAmount -= dueAmount;
        userAssets[owner]
            .erc20Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .claimedAmount += dueAmount;
        if (
            userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .claimedAmount ==
            userAssets[owner]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .totalAmount
        ) {
            userAssets[owner].erc20Assets[assetIndex].remainingBeneficiaries--;
        }
        ILegacyVault(vaultAddress).transferErc20TokensAllowed(
            _contract,
            currentOwner,
            _msgSender(),
            dueAmount
        );

        emit ERC20AssetClaimed(
            userId,
            owner,
            _msgSender(),
            _contract,
            dueAmount,
            _verifySigners(
            hashedMessage,
            nonce,
            signatures
        )
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
        revert("LegacyAssetManager: Asset not found");
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
        revert("LegacyAssetManager: Asset not found");
    }

    function _findERC20AssetIndex(
        address user,
        address _contract
    ) internal view returns (uint256) {
        for (uint i = 0; i < userAssets[user].erc20Assets.length; i++) {
            if (userAssets[user].erc20Assets[i]._contract == _contract) {
                return i;
            }
        }
        revert("LegacyAssetManager: Asset not found");
    }

    function _findERC1155BeneficiaryIndex(
        address beneficiary,
        ERC1155Asset memory erc1155Asset
    ) internal pure returns (uint256) {
        for (uint i = 0; i < erc1155Asset.beneficiaries.length; i++) {
            if (erc1155Asset.beneficiaries[i].account == beneficiary) {
                return i;
            }
        }
        revert("LegacyAssetManager: Beneficiary not found");
    }

    function _findERC20BeneficiaryIndex(
        address beneficiary,
        ERC20Asset memory erc20Asset
    ) internal pure returns (uint256) {
        for (uint i = 0; i < erc20Asset.beneficiaries.length; i++) {
            if (erc20Asset.beneficiaries[i].account == beneficiary) {
                return i;
            }
        }
        revert("LegacyAssetManager: Beneficiary not found");
    }

    function setERC1155BeneficiaryPercentage(
        string memory userId,
        address _contract,
        uint256 tokenId,
        address beneficiary,
        uint8 newPercentage
    ) external {
        uint256 assetIndex = _findERC1155AssetIndex(
            _msgSender(),
            _contract,
            tokenId
        );
        uint256 beneficiaryIndex = _findERC1155BeneficiaryIndex(
            beneficiary,
            userAssets[_msgSender()].erc1155Assets[assetIndex]
        );
        require(
            userAssets[_msgSender()]
                .erc1155Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .totalAmount -
                userAssets[_msgSender()]
                    .erc1155Assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .claimedAmount >
                0,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );
        uint8 currentPercentage = userAssets[_msgSender()]
            .erc1155Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage;
        require(
            (userAssets[_msgSender()]
                .erc1155Assets[assetIndex]
                .totalPercentage - currentPercentage) +
                newPercentage <=
                100,
            "LegacyAssetManager: Beneficiary percentage exceeds total of 100"
        );
        userAssets[_msgSender()]
            .erc1155Assets[assetIndex]
            .beneficiaries[beneficiaryIndex]
            .allowedPercentage = newPercentage;
        userAssets[_msgSender()].erc1155Assets[assetIndex].totalPercentage =
            (userAssets[_msgSender()]
                .erc1155Assets[assetIndex]
                .totalPercentage - currentPercentage) +
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
        uint256 assetIndex = _findERC721AssetIndex(
            _msgSender(),
            _contract,
            tokenId
        );
        require(
            !userAssets[_msgSender()].erc721Assets[assetIndex].transferStatus,
            "LegacyAssetManager: Asset has been claimed"
        );
        userAssets[_msgSender()]
            .erc721Assets[assetIndex]
            .beneficiary = newBeneficiary;
        emit BeneficiaryChanged(
            userId,
            _msgSender(),
            _contract,
            tokenId,
            newBeneficiary
        );
    }

    function setERC20BeneficiaryPercentage(
        string memory userId,
        address _contract,
        address beneficiary,
        uint8 newPercentage
    ) external {
        uint256 assetIndex = _findERC20AssetIndex(_msgSender(), _contract);
        uint256 beneficiaryIndex = _findERC20BeneficiaryIndex(
            beneficiary,
            userAssets[_msgSender()].erc20Assets[assetIndex]
        );
        require(
            userAssets[_msgSender()]
                .erc20Assets[assetIndex]
                .beneficiaries[beneficiaryIndex]
                .totalAmount -
                userAssets[_msgSender()]
                    .erc20Assets[assetIndex]
                    .beneficiaries[beneficiaryIndex]
                    .claimedAmount >
                0,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
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
            userId,
            _msgSender(),
            _contract,
            0,
            beneficiary,
            newPercentage
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
