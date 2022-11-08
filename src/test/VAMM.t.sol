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

    // Setup before each tests
    function setUp() public {
        // Create and mints collateral token to owner address
        collateral = new ERC20PresetFixedSupply("Mock USDT","mUSDT",UINT256_MAX,owner);
        // Create and mints asset token to owner address
        asset = new ERC20PresetFixedSupply("Mock ETH","mETH",UINT256_MAX,owner);

        vm.prank(owner);
        // Tranfers 10000 mUSDT to alice
        collateral.transfer(alice, 10000 ether);

        uint256 x = 1_000 ether;//eth
        uint256 y = x*1_500;//usdt
        // Initialize VAMM with virtual liquidity of 1000 mEther and 1000*1500 mUSDT (initial price of $1500)
        vamm = new VAMM(address(collateral),address(asset),y,x);
    }

    // Helper function to send collateral to address
    function sendCollateral(address to, uint256 amount) public {
        vm.prank(owner);
        collateral.transfer(to, amount);
    }

    // Test to check price amounts to $1,500
    function testGetPrice() public{
        assertEq(vamm.getPrice(), 1_500 ether);
    }

    // Test long function
    function testLong() public {
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * 10 ether) / (vamm.reserveCollateral() + 10 ether) -1;

        vm.startPrank(alice);
        // Alice approve collateral for VAMM contract
        collateral.approve(address(vamm), 10 ether);
        // Alice enters long trade with $10 
        vamm.long(10 ether);

        assertEq(aliceBalance - 10 ether, collateral.balanceOf(alice));
        (uint256 size, uint256 liqPrice, uint256 costBasis,, VAMM.Side side) = vamm.positions(alice);
        assertEq(size, expectedSize,"Size not equal.");
        assertEq(liqPrice, 0,"Liquidation price not equal.");
        assertEq(costBasis, vamm.getPrice(),"Size not equal.");
        assertEq(uint(side), uint(VAMM.Side.LONG),"Side not equal.");
        vm.stopPrank();
    }
    
    // Test long function with fuzzy uint25
    // Same as testLong() but with more flexibility
    function testLongWithAmount(uint256 longAmount) public {
        vm.assume(longAmount<=10000 ether);
        vm.assume(longAmount>0.01 ether);
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * longAmount) / (vamm.reserveCollateral() + longAmount) -1;

        vm.startPrank(alice);
        // Alice approve collateral for VAMM contract
        collateral.approve(address(vamm), longAmount);
        // Alice enters long trade with $longAmount
        vamm.long(longAmount);
        assertEq(aliceBalance - longAmount, collateral.balanceOf(alice));
        (uint256 size, uint256 liqPrice, uint256 costBasis,, VAMM.Side side) = vamm.positions(alice);
        assertEq(size, expectedSize,"Size not equal.");
        assertEq(liqPrice, 0,"Liquidation price not equal.");
        assertEq(costBasis, vamm.getPrice(),"Size not equal.");
        assertEq(uint(side), uint(VAMM.Side.LONG),"Side not equal.");
        vm.stopPrank();
    }

    // Test short function
    function testShort() public{
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * 10 ether) / (vamm.reserveCollateral() - 10 ether) +1;

        vm.startPrank(alice);
        // Alice approve collateral for VAMM contract
        collateral.approve(address(vamm), 10 ether);
        // Alice enters short trade with $10 
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

    // Test short function with fuzzy uint25
    // Same as testShort() but with more flexibility
    function testShortWithAmount(uint256 shortAmount) public{
        vm.assume(shortAmount<=10000 ether);
        vm.assume(shortAmount>0.01 ether);
        uint256 aliceBalance = collateral.balanceOf(alice);
        uint256 expectedSize = (vamm.reserveAsset() * shortAmount) / (vamm.reserveCollateral() - shortAmount) +1;

        vm.startPrank(alice);
        // Alice approve collateral for VAMM contract
        collateral.approve(address(vamm), shortAmount);
        vamm.short(shortAmount);
        // Alice enters short trade with $shortAmount 
        uint256 expectedLiqPrice = vamm.getPrice() * (10_000 + vamm.liquidationRatio()) / 10_000;
        assertEq(aliceBalance - shortAmount, collateral.balanceOf(alice));
        (uint256 size, uint256 liqPrice, uint256 costBasis,, VAMM.Side side) = vamm.positions(alice);
        assertEq(size, expectedSize,"Size not equal.");
        assertEq(liqPrice, expectedLiqPrice,"Liquidation price not equal.");
        assertEq(costBasis, vamm.getPrice(),"Size not equal.");
        assertEq(uint(side), uint(VAMM.Side.SHORT),"Side not equal.");
        vm.stopPrank();
    }

    // Test if price increased on long trade
    // Bob enter long trade and exit with profit
    // Charlie enter long trade and exit with loss
    // Bob long -> Charlie Long -> Bob close(in profit) -> Charlie close(in loss)
    function testPriceIncreaseOnLong() public{
        address bob = address(uint160(uint256(keccak256("bob"))));
        address charlie = address(uint160(uint256(keccak256("charlie"))));
        sendCollateral(bob, 1000 ether);
        sendCollateral(charlie, 1000 ether);

        vm.startPrank(bob);
        collateral.approve(address(vamm), 1000 ether);
        assertTrue(vamm.getPrice() == 1500 ether, "Price should equal $1500.");
        vamm.long(1000 ether);
        vm.stopPrank();
        assertTrue(vamm.getPrice() > 1500 ether, "Price should increase after long trade.");

        (uint256 bobSize,,,,) = vamm.positions(bob);
        assertTrue(bobSize > 0, "Bob should hold position.");

        vm.startPrank(charlie);
        collateral.approve(address(vamm), 1000 ether);
        vamm.long(1000 ether);
        vm.stopPrank();
        (uint256 charlieSize,,,,) = vamm.positions(charlie);
        assertTrue(charlieSize > 0, "Charlie should hold position.");

        vm.prank(bob);
        vamm.closeTrade();
        assertTrue(collateral.balanceOf(bob) > 1000 ether,"Bob should have more collateral(profit).");
        vm.prank(charlie);
        vamm.closeTrade();
        assertTrue(collateral.balanceOf(charlie) < 1000 ether,"Charlie should have less collateral(loss incurred).");

        (,uint256 liqPrice,,,) = vamm.positions(charlie);
        assertTrue(liqPrice == 0,"Liquidation price not 0.");

        assertApproxEqAbs(vamm.getPrice(), 1500 ether,1e5,"Asset price should not change too much.");
        assertApproxEqAbs(vamm.reserveCollateral(), 1500*1000 ether, 1e5,"Collateral amount should not change too much.");
    }

    // Test if price increased on short trade
    // Same as testPriceIncreaseOnLong() but with short trades
    function testPriceDecreaseOnShort() public{
        address bob = address(uint160(uint256(keccak256("bob"))));
        address charlie = address(uint160(uint256(keccak256("charlie"))));
        sendCollateral(bob, 1000 ether);
        sendCollateral(charlie, 1000 ether);

        vm.startPrank(bob);
        collateral.approve(address(vamm), 1000 ether);
        assertTrue(vamm.getPrice() == 1500 ether, "Price should equal $1500.");
        vamm.short(1000 ether);
        vm.stopPrank();
        assertTrue(vamm.getPrice() < 1500 ether, "Price should decrease after short trade.");

        (uint256 bobSize,,,,) = vamm.positions(bob);
        assertTrue(bobSize > 0, "Bob should hold position.");

        vm.startPrank(charlie);
        collateral.approve(address(vamm), 1000 ether);
        vamm.short(1000 ether);
        vm.stopPrank();
        (uint256 charlieSize,,,,) = vamm.positions(charlie);
        assertTrue(charlieSize > 0, "Charlie should hold position.");

        vm.prank(bob);
        vamm.closeTrade();
        assertTrue(collateral.balanceOf(bob) > 1000 ether,"Bob should have more collateral(profit).");
        vm.prank(charlie);
        vamm.closeTrade();
        assertTrue(collateral.balanceOf(charlie) < 1000 ether,"Charlie should have less collateral(loss incurred).");

        (,uint256 liqPrice,,,) = vamm.positions(charlie);
        assertTrue(liqPrice == 0,"Liquidation price should 0.");

        assertApproxEqAbs(vamm.getPrice(), 1500 ether,1e5,"Asset price should not change too much.");
        assertApproxEqAbs(vamm.reserveCollateral(), 1500*1000 ether, 1e5,"Collateral amount should not change too much.");
    }

// Test to revert on not enough allowance
    function testCannotLongNotEnoughAllowance() public {
        vm.startPrank(alice);
        vm.expectRevert(bytes("Not enough allowance."));
        vamm.long(10 ether);
    }

// Test to revert on not enough collateral
    function testCannotLongNotEnoughCollateral() public {
        vm.startPrank(alice);
        collateral.approve(address(vamm), 10 ether);
        collateral.transfer(address(1337), collateral.balanceOf(alice));
        vm.expectRevert(bytes("Not enough collateral balance."));
        vamm.long(10 ether);
    }

// Test to revert if already have ongoing trade
    function testCannotMultiplePosition() public {
        testLong();

        vm.startPrank(alice);
        collateral.approve(address(vamm), 10 ether);
        vm.expectRevert(bytes("Position already existed."));
        vamm.long(10 ether);
    }

// Test to close trade while long (Fuzzy)
    function testCloseWhileLong(uint256 longAmount) public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testLongWithAmount(longAmount);

        vm.startPrank(alice);
        vamm.closeTrade();
        // assertEq(initialBalance, collateral.balanceOf(alice));
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1,"Balance does not match.");
        vm.stopPrank();
    }

// Test to close trade while long (Simple)
    function testSimpleCloseWhileLong() public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testLongWithAmount(1000 ether);

        vm.startPrank(alice);
        vamm.closeTrade();
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1e2,"Balance does not match.");
        vm.stopPrank();
    }

// Test to close trade while short (Fuzzy)
    function testCloseWhileShort(uint256 shortAmount) public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testShortWithAmount(shortAmount);

        vm.startPrank(alice);
        vamm.closeTrade();
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1e2,"Balance does not match.");

        vm.stopPrank();
    }

// Test to close trade while short (Simple)
    function testSimpleCloseWhileShort() public{
        uint256 initialBalance = collateral.balanceOf(alice);
        testShortWithAmount(1000 ether);
        
        vm.startPrank(alice);
        vamm.closeTrade();
        assertApproxEqRel(collateral.balanceOf(alice), initialBalance, 1e2,"Balance does not match.");
        vm.stopPrank();
    }

// Test to open and close trade with about 2000 addresses (half long, half short)
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
        assertApproxEqRel(kBefore, vamm.K(),1e2,"K should (almost) equal.");
        assertApproxEqRel(priceBefore, vamm.getPrice(),1e2,"Price should (almost) equal.");

    }

// Test to revert on liqudating non-liquidatable address
    function testCannotLiquidateWhenLiquidationPriceNotReached() public {
        testShortWithAmount(100 ether);
        vm.expectRevert(bytes("Liquidation price not reached."));
        vamm.liquidatePosition(alice);
    }

// Test to revert when liquidating non-existent position
    function testCannotLiquidateWhenNoSize() public {
        vm.expectRevert(bytes("No position."));
        vamm.liquidatePosition(alice);
    }

// Test to revert when liquidating long position
    function testCannotLiquidateWhenLong() public {
        testLongWithAmount(100 ether);
        vm.expectRevert(bytes("Only short position can be liquidated."));
        vamm.liquidatePosition(alice);
    }


// Test to liquidate bad debt
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

//Helper function to long
    function longWithAddressAndAmount(address user, uint256 amount) public{
            sendCollateral(user,amount);
            vm.startPrank(user);
            collateral.approve(address(vamm), amount);
            vamm.long(amount);
            vm.stopPrank();
    }

//Helper function to short
    function shortWithAddressAndAmount(address user, uint256 amount) public{
            sendCollateral(user,amount);
            vm.startPrank(user);
            collateral.approve(address(vamm), amount);
            vamm.short(amount);
            vm.stopPrank();
    }
}
