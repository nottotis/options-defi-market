// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Virtual Automated Market Maker (VAMM) contract
 */
contract VAMM is ReentrancyGuard{
    enum Side{
        LONG,
        SHORT
    }

    struct Position{
        uint256 size; // Size of position/trade
        uint256 liquidationPrice; // Liquidation price (Short only)
        uint256 costBasis; // Asset price on entry
        uint256 entryAmount; // Collateral amount on entry
        Side side; // Side of position/trade
    }

    address public collateral; // Stablecoin address
    address public asset; // Asset address
    uint256 public reserveCollateral;  // Stablecoin reserve
    uint256 public reserveAsset;  // Asset reserve
    mapping(address=>Position) public positions;
    uint256 public liquidationRatio = 8000; //per ten thousand. 10000 : 100%, 100 : 1% etc
    uint256 public insuranceFunds = 0; // Keep track insurance fund after each liquidation


    constructor(address _collateral, address _asset, uint256 _reserveCollateral, uint256 _reserveAsset){ 
        collateral = _collateral;
        asset = _asset;
        reserveCollateral = _reserveCollateral;
        reserveAsset = _reserveAsset;
    }

    /**
     * @dev Enter long trade of underlying asset.
     * @param longAmount Amounts of collateral for the long trade
     */
    function long(uint256 longAmount) public nonReentrant {
        require(IERC20(collateral).allowance(msg.sender, address(this)) >= longAmount,"Not enough allowance.");
        require(IERC20(collateral).balanceOf(msg.sender) >= longAmount,"Not enough collateral balance.");
        uint256 outputAsset = _swap(longAmount, true);
        require(outputAsset>0,"No output. Check input amount.");
        require(positions[msg.sender].size == 0,"Position already existed.");

        // longs holds asset
        Position memory newPosition = Position(outputAsset,0,getPrice(),longAmount,Side.LONG);
        positions[msg.sender] = newPosition;

        IERC20(collateral).transferFrom(msg.sender, address(this), longAmount);
    }


    /**
     * @dev Enter short trade of underlying asset.
     * @param shortAmount Amounts of collateral for the short trade
     */
    function short(uint256 shortAmount) public nonReentrant {
        require(IERC20(collateral).allowance(msg.sender, address(this)) >= shortAmount,"Not enough allowance.");
        require(IERC20(collateral).balanceOf(msg.sender) >= shortAmount,"Not enough collateral balance.");
        uint256 outputAsset = _swap(shortAmount, false);
        require(outputAsset>0,"No output.");

        require(positions[msg.sender].size == 0,"Position already existed.");

        // shorts holds stablecoin
        uint256 liqPrice = getPrice() * (10_000 + liquidationRatio) / 10_000;
        Position memory newPosition = Position(outputAsset,liqPrice,getPrice(),shortAmount,Side.SHORT);
        positions[msg.sender] = newPosition;

        IERC20(collateral).transferFrom(msg.sender, address(this), shortAmount);

    }
    

    /**
     * @dev Liquidate user with bad debt(Assets price < Liquidation price). Anybody can liquidate bad debt.
     * @param toLiquidate Address to be liquidated
     */
    function liquidatePosition(address toLiquidate) public nonReentrant {
        require(positions[toLiquidate].size > 0,"No position.");
        require(positions[toLiquidate].side == Side.SHORT,"Only short position can be liquidated.");
        require(getPrice() > positions[toLiquidate].liquidationPrice,"Liquidation price not reached.");
        Position memory currentPosition = positions[toLiquidate];

        uint256 output = _close(currentPosition.size,false);
        output = currentPosition.entryAmount - (output - currentPosition.entryAmount);
        // remove position data
        delete positions[toLiquidate];

        uint256 forLiquidator = output/2;
        // half amount to vault
        insuranceFunds += (output - forLiquidator);
        // return half amount to liquidator
        IERC20(collateral).transfer(msg.sender, forLiquidator);
    }


    /**
     * @dev Close any outstanding long/short trade.
     */
    function closeTrade() public nonReentrant {
        require(positions[msg.sender].size != 0,"No position to close.");
        Position memory currentPosition = positions[msg.sender];

        if(currentPosition.side == Side.LONG){
            // swap size to AMM
            uint256 output = _close(currentPosition.size, true);
            // remove position data
            delete positions[msg.sender];
            // return swapped amount to msg.sender
            IERC20(collateral).transfer(msg.sender, output);
        }
        else if(currentPosition.side == Side.SHORT){
            if(getPrice() < currentPosition.liquidationPrice){
                // swap size to AMM
                uint256 output = _close(currentPosition.size,false);
                if(output < currentPosition.entryAmount){// +ve pnl
                    output = currentPosition.entryAmount + (currentPosition.entryAmount - output);
                }else{
                    output = currentPosition.entryAmount - (output - currentPosition.entryAmount);
                }
                // remove position data
                delete positions[msg.sender];
                // return swapped amount to msg.sender
                IERC20(collateral).transfer(msg.sender, output);

            }
            else{
                // liquidate thyself.
                liquidatePosition(msg.sender);
            }
            
        }
        else{
            revert("No position side.");
        }
    }


    /**
     * @dev Get price of asset in the VAMM
     * @return Asset price
     */
    function getPrice() public view returns (uint256){
        return reserveCollateral*1 ether/reserveAsset;
    }

    /**
     * @dev Helper function to get constant product value
     * @return K value
     */
    function K() public view returns (uint256){
        return reserveCollateral*reserveAsset;
    }

    /**
     * @dev Swap colllateral to asset size. 
     * @param amount Amount to enter trade
     * @param isLong True if long, false if short
     * @return Asset size
     */
    function _swap(uint256 amount, bool isLong) internal returns (uint256){
        // ydx / (x + dx) = dy
        // LONG: size should less 1e1, to keep K relatively constant
        // SHORT: size should more 1e1
        if(isLong){
            uint256 dy = (reserveAsset * amount) / (reserveCollateral + amount) -1;
            uint256 newX = reserveAsset - dy;
            uint256 newY = reserveCollateral + amount;
            reserveAsset = newX;
            reserveCollateral = newY;
            return dy;
        }
        else{
            uint256 dy = (reserveAsset * amount) / (reserveCollateral - amount) +1;
            uint256 newX = reserveAsset + dy;
            uint256 newY = reserveCollateral - amount;
            reserveAsset = newX;
            reserveCollateral = newY;
            return dy;
        }
    }

    /**
     * @dev Swap asset to collateral value
     * @param size Asset size to close
     * @param isLong True if long, false if short
     * @return Collateral amount
     */
    function _close(uint256 size, bool isLong) internal returns (uint256){
        // ydx / (x + dx) = dy
        if(isLong){
            uint256 dy = (reserveCollateral * size) / (reserveAsset + size);
            uint256 newX = reserveAsset + size;
            uint256 newY = reserveCollateral - dy;
            reserveAsset = newX;
            reserveCollateral = newY;
            return dy;
        }
        else{
            uint256 dy = (reserveCollateral * size) / (reserveAsset - size);
            uint256 newX = reserveAsset - size;
            uint256 newY = reserveCollateral + dy;
            reserveAsset = newX;
            reserveCollateral = newY;
            return dy;
        }
    }
}