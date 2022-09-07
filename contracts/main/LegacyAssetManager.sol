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

contract LegacyAssetManager is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 constant LEGACY_ADMIN = keccak256("LEGACY_ADMIN");

    ILegacyVaultFactory public proxyFactory;

    mapping(address => UserAssets) public userAssets;
    mapping(address => ERC721Asset) public erc721beneficiaries;
    mapping(address => ERC20Asset) public erc20Beneficiaries;
    mapping(address => mapping(uint256 => bool)) public isAlreadyAdded;

    event ERC21AssetAdded(
        address owner,
        address indexed _contract,
        uint256 indexed tokenId,
        address beneficiary
    );

    event ERC20AssetAdded(
        address owner,
        address indexed _contract,
        uint256 totalAmount,
        address[] beneficiaries
    );

    event ERC721AssetRemoved(
        address owner,
        address indexed _contract,
        uint256 indexed tokenId
    );

    event ERC20AssetRemoved(
        address owner,
        address indexed _contract,
        uint256 totalAmount,
        uint256 remainingAmount
    );

    struct ERC20Benificiary {
        address account;
        uint256 allowedAmount;
        bool isTransferred;
    }

    struct ERC20Asset {
        address owner;
        address _contract;
        uint256 totalAmount;
        ERC20Benificiary[] beneficiaries;
        uint256 remainingAmount;
    }

    struct ERC721Asset {
        address owner;
        address _contract;
        uint256 tokenId;
        address beneficiary;
        bool isTransferred;
    }

    struct UserAssets {
        ERC721Asset[] erc721Assets;
        ERC20Asset[] erc20Assets;
        address backupWallet;
    }

    enum AssetType {
        erc721,
        erc20
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(LEGACY_ADMIN, msg.sender);
    }

    function addERC721Assets(
        address[] memory _contracts,
        uint256[] memory tokenIds,
        address[] memory beneficiaries
    ) public {
        require(
            _contracts.length == tokenIds.length &&
                tokenIds.length == beneficiaries.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        for (uint i = 0; i < tokenIds.length; i++) {
            addERC721Single(_contracts[i], tokenIds[i], beneficiaries[i]);
        }
    }

    function addERC721Single(
        address _contract,
        uint256 tokenId,
        address beneficiary
    ) public {
        require(
            !isAlreadyAdded[_contract][tokenId],
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
        userAssets[_msgSender()].erc721Assets.push(
            ERC721Asset(_msgSender(), _contract, tokenId, beneficiary, false)
        );
        isAlreadyAdded[_contract][tokenId] = true;
        emit ERC21AssetAdded(_msgSender(), _contract, tokenId, beneficiary);
    }

    function addERC20Assets(
        address[] memory contracts,
        uint256[] memory totalAmounts,
        address[][] memory beneficiaryAddresses,
        uint256[][] memory beneficiaryAmounts
    ) public {
        require(
            contracts.length == beneficiaryAddresses.length &&
                beneficiaryAddresses.length == totalAmounts.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        for (uint i = 0; i < contracts.length; i++) {
            addERC20Single(
                contracts[i],
                totalAmounts[i],
                beneficiaryAddresses[i],
                beneficiaryAmounts[i]
            );
        }
    }

    function addERC20Single(
        address _contract,
        uint256 totalAmount,
        address[] memory beneficiaryAddresses,
        uint256[] memory beneficiaryAmounts
    ) public {
        require(
            beneficiaryAddresses.length == beneficiaryAmounts.length,
            "LegacyAssetManager: Arguments length mismatch"
        );
        require(
            IERC20(_contract).balanceOf(_msgSender()) >= totalAmount,
            "LegacyAssetManager: Asset amount exceeds balance"
        );

        uint256 amountsSum;
        ERC20Benificiary[] memory _erc20Beneficiaries = new ERC20Benificiary[](
            beneficiaryAddresses.length
        );
        for (uint i = 0; i < beneficiaryAddresses.length; i++) {
            _erc20Beneficiaries[i] = ERC20Benificiary(
                beneficiaryAddresses[i],
                beneficiaryAmounts[i],
                false
            );
            amountsSum += beneficiaryAmounts[i];
            require(
                amountsSum <= totalAmount,
                "LegacyAssetManager: Beneficiary amounts exceeds total amount"
            );
        }
        userAssets[_msgSender()].erc20Assets.push(
            ERC20Asset(
                _msgSender(),
                _contract,
                totalAmount,
                _erc20Beneficiaries,
                totalAmount
            )
        );
        emit ERC20AssetAdded(
            _msgSender(),
            _contract,
            totalAmount,
            beneficiaryAddresses
        );
    }

    function removeERC721Single(address _contract, uint256 tokenId) public {
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
            !erc721Asset.isTransferred,
            "LegacyAssetManager: Asset has been transferred to the beneficiary"
        );
        _removeAsset(_msgSender(), AssetType.erc721, assetIndex);
        emit ERC721AssetRemoved(_msgSender(), _contract, tokenId);
    }

    function removeERC20Single(address _contract) public {
        uint256 assetIndex = _findERC20AssetIndex(_msgSender(), _contract);
        ERC20Asset memory erc20Asset = userAssets[_msgSender()].erc20Assets[
            assetIndex
        ];
        require(
            erc20Asset._contract != address(0),
            "LegacyAssetManager: Asset not found"
        );
        require(
            erc20Asset.remainingAmount > 0,
            "LegacyAssetManager: Asset has been transferred to the beneficiaries"
        );
        _removeAsset(_msgSender(), AssetType.erc20, assetIndex);
        emit ERC20AssetRemoved(
            _msgSender(),
            _contract,
            erc20Asset.totalAmount,
            erc20Asset.remainingAmount
        );
    }

    function _findERC721AssetIndex(
        address user,
        address _contract,
        uint256 tokenId
    ) internal view returns (uint256) {
        for (
            uint i = 0;
            i < userAssets[_msgSender()].erc721Assets.length;
            i++
        ) {
            if (
                userAssets[_msgSender()].erc721Assets[i]._contract ==
                _contract &&
                userAssets[_msgSender()].erc721Assets[i].tokenId == tokenId
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

    function addAdmin(address _admin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LEGACY_ADMIN, _admin);
    }

    function removeAdmin(address _admin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(LEGACY_ADMIN, _admin);
    }

    // TODO: addbeneficiary & removeBeneficary
    // Blocker: Need to discuss the business logic on this

    // TODO: Add the voucher logic for asset claim feature for beneficiaries
    function claimAsset() public {
        throw("Not implemented yet");
    }
}
