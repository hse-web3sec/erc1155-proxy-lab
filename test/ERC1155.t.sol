// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MyToken} from "src/MyToken.sol";
import {MyTokenV2} from "src/ERC1155v2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract ERC1155Test is Test {
    MyToken token;
    MyTokenV2 tokenV2;
    ERC1967Proxy proxy;
    address proxy_test;
    address owner = address(0x01);

    function setUp() public {
        bytes memory data = abi.encodeCall(MyToken.initialize, owner);

        proxy_test = Upgrades.deployTransparentProxy("MyToken.sol:MyToken", owner, data);

        token = MyToken(address(proxy_test));
    }

    function test_mint() public {
        vm.prank(owner);
        token.mint(owner, 0, 100 * 1e18, "0x00");

        assertEq(token.balanceOf(owner, 0), 100 * 1e18);

        vm.startPrank(owner);
        Upgrades.upgradeProxy(proxy_test, "ERC1155v2.sol:MyTokenV2", "");
        vm.stopPrank();

        tokenV2 = MyTokenV2(address(proxy_test));

        assertEq(tokenV2.version(), 2);

        vm.startPrank(owner);

        vm.expectRevert();
        tokenV2.mint(owner, 0, 100 * 1e18, "0x00");
        assertEq(tokenV2.balanceOf(owner, 0), 100 * 1e18);
        vm.stopPrank();
    }
}
