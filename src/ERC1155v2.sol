// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.7.0
pragma solidity ^0.8.27;

import {MyToken} from "src/MyToken.sol";

/// @custom:oz-upgrades-from MyToken
contract MyTokenV2 is MyToken {
    function version() public returns (uint256) {
        return 2;
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) public override onlyOwner {
        _mint(msg.sender, 0, 100000, "0x00");
        revert();
    }
}
