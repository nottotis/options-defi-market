// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "src/Vault.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "forge-std/Test.sol";

contract VaultTest is Test {
    Vault vault;
    ERC20 collateral;
    ERC20 asset;
    address constant owner = address(1);
    function setUp() public {
        collateral = new ERC20PresetFixedSupply("Mock USDT","mUSDT",10_000 ether,owner);
        asset = new ERC20PresetFixedSupply("Mock ETH","mETH",10_000 ether,owner);
        vault = new Vault(address(collateral),address(asset));
    }

    function testExample() public {
        assertEq(collateral.balanceOf(owner), 10_000 ether);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 ether;
        vm.startPrank(owner);
        collateral.approve(address(vault), depositAmount);
        vault.depositCollateral(depositAmount);
        assertEq(vault.balance(owner), depositAmount);
        assertEq(collateral.balanceOf(address(vault)), depositAmount);
    }

    function testWithdraw() public{
        testDeposit();
        vault.withdrawCollateral(vault.balance(owner));
        assertEq(vault.balance(owner), 0);
        assertEq(collateral.balanceOf(address(vault)), 0);
    }
}
