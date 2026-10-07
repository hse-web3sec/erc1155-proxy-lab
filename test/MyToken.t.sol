// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MyToken} from "../src/MyToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MyTokenTest is Test {
    MyToken token;
    MyToken implementation;
    address owner = address(this);
    address alice = address(0x123);
    address bob = address(0x456);

    function setUp() public {
        implementation = new MyToken();
        bytes memory initData = abi.encodeCall(MyToken.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = MyToken(address(proxy));
    }

    function testMint() public {
        token.mint(alice, 1, 100, "");
        assertEq(token.balanceOf(alice, 1), 100);
    }

    function testBurn() public {
        token.mint(alice, 1, 100, "");
        vm.prank(alice);
        token.burn(alice, 1, 30);
        assertEq(token.balanceOf(alice, 1), 70);
    }

    function testMintBatch() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;
        token.mintBatch(alice, ids, amounts, "");
        assertEq(token.balanceOf(alice, 1), 10);
        assertEq(token.balanceOf(alice, 2), 20);
        assertEq(token.balanceOf(alice, 3), 30);
    }

    function testOwnerAndURI() public {
        assertEq(token.owner(), owner);
        assertEq(token.uri(1), "");
        token.setURI("ipfs://example/{id}.json");
        assertEq(token.uri(1), "ipfs://example/{id}.json");
    }

    function testOwnerOnlyOperations() public {
        bytes memory unauthorized = abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, bob);
        vm.startPrank(bob);
        vm.expectRevert(unauthorized);
        token.mint(alice, 1, 100, "");
        vm.expectRevert(unauthorized);
        token.setURI("ipfs://unauthorized/{id}.json");
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 1;
        amounts[0] = 100;
        vm.expectRevert(unauthorized);
        token.mintBatch(alice, ids, amounts, "");
        vm.stopPrank();
        assertEq(token.balanceOf(alice, 1), 0);
    }

    function testInitializationLocked() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize(bob);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(bob);
        assertEq(token.owner(), owner);
    }

    function testProxyCannotUpgrade() public {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 original = vm.load(address(token), implementationSlot);
        MyToken replacement = new MyToken();
        (bool success,) = address(token)
            .call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(replacement), bytes("")));
        assertFalse(success);
        (success,) = address(token).call(abi.encodeWithSignature("upgradeTo(address)", address(replacement)));
        assertFalse(success);
        assertEq(vm.load(address(token), implementationSlot), original);
        assertEq(address(uint160(uint256(original))), address(implementation));
    }
}
