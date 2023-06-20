// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/ILegacyVaultFactory.sol";
import "../interfaces/ILegacyVault.sol";
import "../interfaces/ILegacyAssetManagerERC721.sol";
import "../interfaces/ILegacyAssetManager.sol";

contract LegacyAssetManagerERC721 is ILegacyAssetManagerERC721 ,AccessControl, Pausable, ReentrancyGuard {

    bytes32 public constant LEGACY_ADMIN = keccak256("LEGACY_ADMIN");
    bytes32 public constant ASSET_AUTHORIZER = keccak256("ASSET_AUTHORIZER");

    ILegacyVaultFactory public vaultFactory;
    uint16 public minAdminSignature;
    mapping(address => UserAssets) public userAssets;
    mapping(address => bool) public listedMembers;
    mapping(address => mapping(address => mapping(uint256 => bool)))public listedAssets;
    mapping(uint256 => bool) public burnedNonces;

    event ERC721AssetAdded(
        string userId,
        address indexed owner,
        address indexed _contract,
        uint256 indexed tokenId,
        address beneficiary
    );

    event ERC721AssetRemoved(
        string userId,
        address indexed owner,
        address _contract,
        uint256 indexed tokenId
    );

    event ERC721AssetClaimed(
        string userId,
        address indexed owner,
        address claimer,
        address _contract,
        uint256 indexed tokenId,
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

    function addERC721Assets(
        string calldata userId,
        address[] calldata _contracts,
        uint256[] calldata tokenIds,
        address[] calldata beneficiaries
    ) external whenNotPaused nonReentrant onlyListedUser(_msgSender()) {
        require(
            _contracts.length == tokenIds.length &&
                tokenIds.length == beneficiaries.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        for (uint i = 0; i < tokenIds.length; i++) {
            _addERC721Single(
                userId,
                _contracts[i],
                tokenIds[i],
                beneficiaries[i]
            );
        }
    }

    function _addERC721Single(
        string memory userId,
        address _contract,
        uint256 tokenId,
        address beneficiary
    ) internal assetNotListed(_msgSender(), _contract, tokenId) {
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
                vaultFactory.getVault(_msgSender()) ||
                IERC721(_contract).isApprovedForAll(
                    _msgSender(),
                    vaultFactory.getVault(_msgSender())
                ),
            "LegacyAssetManager: Asset not approved"
        );
        userAssets[_msgSender()].erc721Assets.push(
            ERC721Asset(_msgSender(), _contract, tokenId, beneficiary, false)
        );
        listedAssets[_msgSender()][_contract][tokenId] = true;

        emit ERC721AssetAdded(
            userId,
            _msgSender(),
            _contract,
            tokenId,
            beneficiary
        );
    }

    function removeERC721Asset(
        string memory userId,
        address _contract,
        uint256 tokenId
    ) external nonReentrant {
        uint256 assetIndex = _findERC721AssetIndex(
            _msgSender(),
            _contract,
            tokenId
        );
        require(
            !userAssets[_msgSender()].erc721Assets[assetIndex].transferStatus,
            "LegacyAssetManager: Asset has been transferred to the beneficiary"
        );
        userAssets[_msgSender()].erc721Assets[assetIndex] = userAssets[
            _msgSender()
        ].erc721Assets[userAssets[_msgSender()].erc721Assets.length - 1];
        userAssets[_msgSender()].erc721Assets.pop();
        listedAssets[_msgSender()][_contract][tokenId] = false;
        emit ERC721AssetRemoved(userId, _msgSender(), _contract, tokenId);
    }
   
    function claimERC721Asset(
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
        uint256 assetIndex = _findERC721AssetIndex(owner, _contract, tokenId);

        require(
            !userAssets[owner].erc721Assets[assetIndex].transferStatus,
            "LegacyAssetManager: Beneficiary has already claimed the asset"
        );
        require(
            userAssets[owner].erc721Assets[assetIndex].beneficiary ==
                _msgSender(),
            "LegacyAssetManager: Unauthorized claim call"
        );

        address vaultAddress = vaultFactory.getVault(owner);
        address from;
        if (userAssets[owner].backupWalletStatus) {
            from = ILegacyVault(ILegacyVaultFactory(vaultFactory).getVault(owner)).getBackupWallet(owner)[userAssets[owner].backupWalletIndex];
        } else {
            from = owner;
        }

        ILegacyVault(vaultAddress).transferErc721TokensAllowed(
            _contract,
            from,
            _msgSender(),
            tokenId
        );
        userAssets[owner].erc721Assets[assetIndex].transferStatus = true;
        emit ERC721AssetClaimed(
            userId,
            owner,
            _msgSender(),
            _contract,
            tokenId,
            _verifySigners(
            hashedMessage,
            nonce,
            signatures
        )
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
        revert("LegacyAssetManager: Asset not found");
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