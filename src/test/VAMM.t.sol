// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "src/VAMM.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "forge-std/Test.sol";

contract VAMMTest is Test {
    VAMM vamm;
    ERC20 collateral;
    ERC20 asset;
    address constant owner = address(1);
    address constant alice = address(2);
    function setUp() public {
        collateral = new ERC20PresetFixedSupply("Mock USDT","mUSDT",UINT256_MAX,owner);
        asset = new ERC20PresetFixedSupply("Mock ETH","mETH",UINT256_MAX,owner);
        vm.prank(owner);
        collateral.transfer(alice, 10000 ether);

        uint256 x = 1_000 ether;//eth
        uint256 y = x*1_500;//usdt
        vamm = new VAMM(address(collateral),address(asset),y,x);
    }

    function sendCollateral(address to, uint256 amount) public {
        vm.prank(owner);
        collateral.transfer(to, amount);
    }

    function testGetPrice() public{
        assertEq(vamm.getPrice(), 1_500 ether);
    }

    function testLong() public {
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * 10 ether) / (vamm.reserveCollateral() + 10 ether) -1;

        vm.startPrank(alice);
        collateral.approve(address(vamm), 10 ether);
        vamm.long(10 ether);
        assertEq(aliceBalance - 10 ether, collateral.balanceOf(alice));
        (uint256 size, uint256 liqPrice, uint256 costBasis,, VAMM.Side side) = vamm.positions(alice);
        assertEq(size, expectedSize,"Size not equal.");
        assertEq(liqPrice, 0,"Liquidation price not equal.");
        assertEq(costBasis, vamm.getPrice(),"Size not equal.");
        assertEq(uint(side), uint(VAMM.Side.LONG),"Side not equal.");
        vm.stopPrank();
    }
    
    function testLongWithAmount(uint256 longAmount) public {
        vm.assume(longAmount<=10000 ether);
        vm.assume(longAmount>0.01 ether);
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * longAmount) / (vamm.reserveCollateral() + longAmount) -1;

        vm.startPrank(alice);
        collateral.approve(address(vamm), longAmount);
        vamm.long(longAmount);
        assertEq(aliceBalance - longAmount, collateral.balanceOf(alice));
        (uint256 size, uint256 liqPrice, uint256 costBasis,, VAMM.Side side) = vamm.positions(alice);
        assertEq(size, expectedSize,"Size not equal.");
        assertEq(liqPrice, 0,"Liquidation price not equal.");
        assertEq(costBasis, vamm.getPrice(),"Size not equal.");
        assertEq(uint(side), uint(VAMM.Side.LONG),"Side not equal.");
        vm.stopPrank();
    }

    function testShort() public{
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * 10 ether) / (vamm.reserveCollateral() - 10 ether) +1;

        vm.startPrank(alice);
        collateral.approve(address(vamm), 10 ether);
        vamm.short(10 ether);
        uint256 expectedLiqPrice = vamm.getPrice() * 180 / 100;
        assertEq(aliceBalance - 10 ether, collateral.balanceOf(alice));
        (uint256 size, uint256 liqPrice, uint256 costBasis,, VAMM.Side side) = vamm.positions(alice);
        assertEq(size, expectedSize,"Size not equal.");
        assertEq(liqPrice, expectedLiqPrice,"Liquidation price not equal.");
        assertEq(costBasis, vamm.getPrice(),"Size not equal.");
        assertEq(uint(side), uint(VAMM.Side.SHORT),"Side not equal.");
        vm.stopPrank();
    }
    function testShortWithAmount(uint256 shortAmount) public{
        vm.assume(shortAmount<=10000 ether);
        vm.assume(shortAmount>0.01 ether);
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * shortAmount) / (vamm.reserveCollateral() - shortAmount) +1;

        vm.startPrank(alice);
        collateral.approve(address(vamm), shortAmount);
        vamm.short(shortAmount);
        uint256 expectedLiqPrice = vamm.getPrice() * (10_000 + vamm.liquidationRatio()) / 10_000;
        assertEq(aliceBalance - shortAmount, collateral.balanceOf(alice));
        (uint256 size, uint256 liqPrice, uint256 costBasis,, VAMM.Side side) = vamm.positions(alice);
        assertEq(size, expectedSize,"Size not equal.");
        assertEq(liqPrice, expectedLiqPrice,"Liquidation price not equal.");
        assertEq(costBasis, vamm.getPrice(),"Size not equal.");
        assertEq(uint(side), uint(VAMM.Side.SHORT),"Side not equal.");
        vm.stopPrank();
    }

    function testPriceIncreaseOnLong() public{
        emit log_named_uint("Price before",vamm.getPrice());
        emit log_named_uint("Coll before",vamm.reserveCollateral());
        address bob = address(uint160(uint256(keccak256("bob"))));
        address charlie = address(uint160(uint256(keccak256("charlie"))));
        sendCollateral(bob, 1000 ether);
        sendCollateral(charlie, 1000 ether);


        emit log_named_uint("Bob balance before close", collateral.balanceOf(bob));
        emit log_named_uint("Balance col", collateral.balanceOf(address(vamm)));
        vm.startPrank(bob);
        collateral.approve(address(vamm), 1000 ether);
        vamm.long(1000 ether);
        vm.stopPrank();
        emit log_named_uint("Price after bob long",vamm.getPrice());
        (uint256 bobSize,,,,) = vamm.positions(bob);
        emit log_named_uint("Bob size",bobSize);

        vm.startPrank(charlie);
        collateral.approve(address(vamm), 1000 ether);
        vamm.long(1000 ether);
        vm.stopPrank();
        emit log_named_uint("Price after charlie short",vamm.getPrice());
        (uint256 charlieSize,,,,) = vamm.positions(charlie);
        emit log_named_uint("Charlie size",charlieSize);

        vm.prank(bob);
        vamm.closeTrade();
        emit log_named_uint("Price after bob close",vamm.getPrice());
        emit log_named_uint("Bob balance after close", collateral.balanceOf(bob));
        emit log_named_uint("Balance col", collateral.balanceOf(address(vamm)));
        vm.prank(charlie);
        vamm.closeTrade();
        emit log_named_uint("Charlie balance after close", collateral.balanceOf(charlie));
        emit log_named_uint("Balance col after all closed", collateral.balanceOf(address(vamm)));

        (,uint256 liqPrice,,,) = vamm.positions(charlie);
        emit log_named_uint("Liquidation price", liqPrice);


        emit log_named_uint("Price after",vamm.getPrice());
        emit log_named_uint("Coll after",vamm.reserveCollateral());
    }
    function testPriceDecreaseOnShort() public{
        emit log_named_uint("Price before",vamm.getPrice());
        testShort();
        emit log_named_uint("Price after",vamm.getPrice());
    }

    function testCannotLongNotEnoughAllowance() public {
        vm.startPrank(alice);
        vm.expectRevert(bytes("Not enough allowance."));
        vamm.long(10 ether);
    }
    function testCannotLongNotEnoughCollateral() public {
        vm.startPrank(alice);
        collateral.approve(address(vamm), 10 ether);
        collateral.transfer(address(1337), collateral.balanceOf(alice));
        vm.expectRevert(bytes("Not enough collateral balance."));
        vamm.long(10 ether);
    }

    function testCannotMultiplePosition() public {
        testLong();

        vm.startPrank(alice);
        collateral.approve(address(vamm), 10 ether);
        vm.expectRevert(bytes("Position already existed."));
        vamm.long(10 ether);
    }

    function testCloseWhileLong(uint256 longAmount) public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testLongWithAmount(longAmount);

        vm.startPrank(alice);
        vamm.closeTrade();
        // assertEq(initialBalance, collateral.balanceOf(alice));
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1,"Balance does not match.");
        vm.stopPrank();
    }
    function testSimpleCloseWhileLong() public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testLongWithAmount(1000 ether);

        vm.startPrank(alice);
        vamm.closeTrade();
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1e2,"Balance does not match.");
        vm.stopPrank();
    }
    function testCloseWhileShort(uint256 shortAmount) public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testShortWithAmount(shortAmount);

        vm.startPrank(alice);
        vamm.closeTrade();
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1e2,"Balance does not match.");

        vm.stopPrank();
    }
    function testSimpleCloseWhileShort() public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testShortWithAmount(1000 ether);
        
        vm.startPrank(alice);
        vamm.closeTrade();
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1e2,"Balance does not match.");
        vm.stopPrank();
    }

    function testALotTrades() public{
        uint256 priceBefore = vamm.getPrice();
        uint256 kBefore = vamm.K();
        for(uint160 i = 5; i<1000;i++){
            uint256 shortAmount = 100 ether;
            sendCollateral(address(i),shortAmount);
            vm.startPrank(address(i));
            collateral.approve(address(vamm), shortAmount);
            vamm.short(shortAmount);
            vm.stopPrank();
        }
        for(uint160 i = 1005; i<2000;i++){
            uint256 longAmount = 100 ether;
            sendCollateral(address(i),longAmount);
            vm.startPrank(address(i));
            collateral.approve(address(vamm), longAmount);
            vamm.long(longAmount);
            vm.stopPrank();
        }


        for(uint160 i = 5; i<1000;i++){
            vm.startPrank(address(i));
            vamm.closeTrade();
            vm.stopPrank();
        }
        for(uint160 i = 1005; i<2000;i++){
            vm.startPrank(address(i));
            vamm.closeTrade();
            vm.stopPrank();
        }
        assertApproxEqRel(kBefore, vamm.K(),1e2,"K not equal.");
        assertApproxEqRel(priceBefore, vamm.getPrice(),1e2,"Price not equal.");

    }

    function testCannotLiquidateWhenLiquidationPriceNotReached() public {
        testShortWithAmount(100 ether);
        vm.expectRevert(bytes("Liquidation price not reached."));
        vamm.liquidatePosition(alice);
    }
    function testCannotLiquidateWhenNoSize() public {
        vm.expectRevert(bytes("No position."));
        vamm.liquidatePosition(alice);
    }
    function testCannotLiquidateWhenLong() public {
        testLongWithAmount(100 ether);
        vm.expectRevert(bytes("Only short position can be liquidated."));
        vamm.liquidatePosition(alice);
    }


    function testSimpleLiquidation() public {
        testShortWithAmount(100 ether);
        (uint256 size,uint256 aliceLiquidationPrice,,,) = vamm.positions(alice);
        assertTrue(size > 0,"No size.");
        longWithAddressAndAmount(address(1001),515000 ether);
        assertTrue(vamm.getPrice() > aliceLiquidationPrice,"Current price should over alice liq price.");

        address liquidator = address(1001);
        assertEq(collateral.balanceOf(liquidator), 0);
        vm.startPrank(liquidator);
        vamm.liquidatePosition(alice);
        vm.stopPrank();

        (uint256 newSize,,,,) = vamm.positions(alice);
        assertTrue(newSize == 0,"Alice size should 0 after liquidation.");
        assertTrue(collateral.balanceOf(liquidator) > 0,"Liquidator should receive half liquidation incentive.");
        assertTrue(collateral.balanceOf(address(vamm)) > 0,"VAMM should receive half liquidation incentive.");
    }

    function longWithAddressAndAmount(address user, uint256 amount) public{
            sendCollateral(user,amount);
            vm.startPrank(user);
            collateral.approve(address(vamm), amount);
            vamm.long(amount);
            vm.stopPrank();
    }
    function shortWithAddressAndAmount(address user, uint256 amount) public{
            sendCollateral(user,amount);
            vm.startPrank(user);
            collateral.approve(address(vamm), amount);
            vamm.short(amount);
            vm.stopPrank();
    }
}
