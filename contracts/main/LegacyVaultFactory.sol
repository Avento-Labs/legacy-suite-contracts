// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/ILegacyVaultFactory.sol";
import "./LegacyVault.sol";

contract LegacyVaultFactory is ILegacyVaultFactory, AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(address => LegacyVault) private memberToContract;
    mapping(address => address) public addressToMainWallet;
    mapping(address => uint16) public addressCount;
    address public legacyAssetManager;
    uint256 public maxWallets;

    event UserVaultCreated(string userId, address owner, address vault);

    event WalletAdded(
        string userId,
        address mainWallet,
        address newWallet,
        address vault
    );

    event WalletRemoved(
        string userId,
        address mainWallet,
        address removedWallet,
        address vault
    );

    constructor(address _legacyAssetManager, uint256 _maxWallets) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, _msgSender());
        legacyAssetManager = _legacyAssetManager;
        maxWallets = _maxWallets;
    }

    modifier validAddress(address _address) {
        require(
            _address != address(0),
            "LegacyVaultFactory: Not valid address"
        );
        _;
    }

    function createVault(string calldata userId, address _memberAddress)
        external
        override
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        require(
            legacyAssetManager != address(0),
            "LegacyVaultFactory: legacyBusiness not set"
        );
        LegacyVault legacyVault = new LegacyVault(
            _memberAddress,
            address(legacyAssetManager)
        );
        memberToContract[_memberAddress] = legacyVault;
        emit UserVaultCreated(userId, _memberAddress, address(legacyVault));
    }

    function getVault(address _listedAddress)
        public
        view
        override
        returns (address)
    {
        address _memberAddress = getMainWallet(_listedAddress);
        require(
            _memberAddress != address(0),
            "LegacyVaultFactory: User vault not deployed"
        );
        return address(memberToContract[_memberAddress]);
    }

    function getMainWallet(address _listedAddress)
        public
        view
        returns (address)
    {
        if (address(memberToContract[_listedAddress]) != address(0)) {
            return _listedAddress;
        }
        return addressToMainWallet[_listedAddress];
    }

    function addWallet(string calldata userId, address _memberAddress)
        external
    {
        require(
            address(memberToContract[_memberAddress]) != address(0),
            "LegacyVaultFactory: User vault not deployed"
        );
        require(
            addressCount[_memberAddress] + 1 <= maxWallets,
            "LegacyVaultFactory: Max wallet limit exceeded"
        );
        addressToMainWallet[_msgSender()] = _memberAddress;
        addressCount[_memberAddress]++;
        emit WalletAdded(
            userId,
            _memberAddress,
            _msgSender(),
            address(memberToContract[_memberAddress])
        );
    }

    function removeWallet(string calldata userId, address _listedAddress)
        external
    {
        require(
            address(memberToContract[_msgSender()]) != address(0),
            "LegacyVaultFactory: User vault not deployed"
        );
        require(
            addressToMainWallet[_listedAddress] == _msgSender(),
            "LegacyVaultFactory: Invalid address provided"
        );
        delete addressToMainWallet[_listedAddress];
        addressCount[_msgSender()]--;
        emit WalletRemoved(
            userId,
            _msgSender(),
            _listedAddress,
            address(memberToContract[_msgSender()])
        );
    }

    function setLegacyAssetManagerAddress(address _assetManager)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAddress(_assetManager)
    {
        legacyAssetManager = _assetManager;
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
