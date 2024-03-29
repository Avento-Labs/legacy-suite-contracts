// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("Mock-ERC20", "mock") {
        _mint(msg.sender, 1 * 10**6 * 10**18);
    }
}
