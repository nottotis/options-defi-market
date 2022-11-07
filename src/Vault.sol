// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vault is ReentrancyGuard {
    address public collateral;
    address public asset;
    mapping(address => uint256) public balance;
    address vCollateral;
    address vAsset;
    constructor(address _collateral, address _asset){
        collateral = _collateral;
        asset = _asset;
    }
    function depositCollateral(uint256 _amountToDeposit) public nonReentrant {
        IERC20(collateral).transferFrom(msg.sender, address(this), _amountToDeposit);
        balance[msg.sender] = _amountToDeposit;
    }

    function withdrawCollateral(uint256 _amountToWithdraw) public nonReentrant {
        require(_amountToWithdraw <= balance[msg.sender]);
        balance[msg.sender] -= _amountToWithdraw;
        IERC20(collateral).transfer( msg.sender, _amountToWithdraw);
    }
}

