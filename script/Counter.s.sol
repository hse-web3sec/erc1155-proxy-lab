// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";

contract CounterScript is Script {
    // Read the existing Counter at the selected RPC block without signing a transaction.
    function run() public returns (uint256 number) {
        number = _counter().number();
        console2.log("number:", number);
    }

    // Deploy and increment in two transactions, as demonstrated in the lecture.
    function deploy() public returns (Counter counter) {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        counter = new Counter();
        counter.increment();
        vm.stopBroadcast();
        console2.log("Counter:", address(counter));
        console2.log("number:", counter.number());
    }

    // Without the CLI --broadcast flag, this changes only the local simulation.
    function increment() public {
        Counter counter = _counter();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        counter.increment();
        vm.stopBroadcast();
        console2.log("number:", counter.number());
    }

    function _counter() internal returns (Counter) {
        address target = vm.envAddress("COUNTER_ADDRESS");
        require(target.code.length > 0, "No Counter code at this address and block");
        return Counter(target);
    }
}
