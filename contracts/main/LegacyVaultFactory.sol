// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/ILegacyVaultFactory.sol";
import "./LegacyVault.sol";

contract LegacyVaultFactory is ILegacyVaultFactory, AccessControl, Pausable {
    address public legacyAssetManager;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(address => LegacyVault) private memberToContract;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier validAddress(address _address) {
        require(_address != address(0), "Not valid address");
        _;
    }

    function createVault(address _memberAddress)
        external
        override
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        require(
            legacyAssetManager != address(0),
            "legacyBusiness needs to be set"
        );
        LegacyVault legacyVault = new LegacyVault(
            _memberAddress,
            address(legacyAssetManager)
        );
        memberToContract[_memberAddress] = legacyVault;
    }

    function deployedContractFromMember(address _memberAddress)
        external
        view
        override
        returns (address)
    {
        return address(memberToContract[_memberAddress]);
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
