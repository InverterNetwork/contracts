// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "forge-std/console.sol";

// import {INativeMinter} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/INativeMinter.sol";

contract NativeMinterMock {
    function mintNativeCoin(address to, uint256 amount) external {
        // log balanche of this contract 
        console.log("NativeMinterMock: balance: %d", address(this).balance);

        (bool success, ) = payable(address(to)).call{value: amount}("");
        
        if (!success) {
            revert("NativeMinterMock: Failed to transfer native token");
        }
    }

    receive() external payable {}
    fallback() external payable {}
}