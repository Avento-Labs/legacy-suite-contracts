// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface ILegacyVault {
    function transferErc20TokensAllowed(
        address _contractAddress,
        address _ownerAddress,
        address _recipientAddress,
        uint256 _amount
    ) external;

    function transferErc721TokensAllowed(
        address _contractAddress,
        address _ownerAddress,
        address _recipientAddress,
        uint256 _tokenId
    ) external;

    function transferErc1155TokensAllowed(
        address _contractAddress,
        address _ownerAddress,
        address _recipientAddress,
        uint256 _tokenId,
        uint256 _amount
    ) external;

    function pauseContract() external;

    function unpauseContract() external;
}
