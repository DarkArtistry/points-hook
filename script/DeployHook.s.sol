// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract DeployHook is Script {
    function run() external {
        uint privateKey = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");

        vm.startBroadcast(privateKey);

        // The CREATE2 deployer proxy used by forge script
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        // 2 Options:
        // 1. Our own contract calls CREATE2 — You write a deployer contract yourself that uses the CREATE2 opcode. But then  
        // the resulting address depends on your deployer contract's address, which might be different on each chain.
        // 2. The proxy at 0x4e59... — Since it's at the same address on every chain, the CREATE2 addresses it produces are    
        // also the same on every chain. That's the only reason it exists — cross-chain determinism.                           
      
        // For our PointsHook, you actually don't care about cross-chain determinism. You just need the address bits to match
        // the flags. So you could skip the proxy entirely and have your deploy script use a factory contract that calls
        // CREATE2, or even call the opcode directly in assembly.
      
        // Foundry just defaults to using the proxy when you write new Contract{salt: salt}() in a forge script. It's a
        // convenience, not a requirement. The HookMiner needs to know which deployer will be used so it can predict the
        // correct address — that's the only reason CREATE2_DEPLOYER is passed in.

        // Our hook only needs the AFTER_SWAP flag
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PointsHook).creationCode,
            constructorArgs
        );
        // type(PointsHook).creationCode is a Solidity built-in that gives you the bytecode used to deploy the contract — the  
        // constructor code plus the contract code.                                                                                                                                       
        // There are two kinds of bytecode:                                                                                                    
        // - creationCode — The bytecode that runs during deployment (constructor logic + returns the runtime code). Only used 
        // once.
        // - runtimeCode — The bytecode stored on-chain after deployment (the actual contract logic). This is what runs when
        // you call the contract.
        // HookMiner needs the creationCode because the CREATE2 address formula is:
        // address = keccak256(0xFF, deployer, salt, keccak256(creationCode + constructorArgs))
        // The creation code is part of the hash, so the miner needs it to predict what address each salt will produce. That's
        // also why constructorArgs is passed separately — they get appended to the creation code before hashing.

        // Deploy the hook using CREATE2 with the mined salt
        PointsHook hook = new PointsHook{salt: salt}(IPoolManager(poolManager));

        // Verify the hook deployed to the expected address
        require(address(hook) == hookAddress, "Hook address mismatch");

        console.log("PointsHook deployed to:", address(hook));

        vm.stopBroadcast();
    }
}
