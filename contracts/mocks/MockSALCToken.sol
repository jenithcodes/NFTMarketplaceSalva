// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockSALCToken
 * @dev Mock version of SALC token for testing purposes
 */
contract MockSALCToken is ERC20, ERC20Burnable, Ownable {
    // Set decimals to match the real token (default is 18)
    uint8 private _decimals = 18;

    /**
     * @dev Constructor
     * @param initialSupply Initial supply to mint to deployer
     */
    constructor(uint256 initialSupply) ERC20("Mock SALC Token", "mSALC") Ownable(msg.sender) {
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    /**
     * @dev Mint new tokens (less restricted for testing)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Free mint function for testing - anyone can mint tokens to themselves
     * @param amount Amount to mint
     */
    function faucet(uint256 amount) external {
        // Limiting the amount per call to prevent abuse
        require(amount <= 10000 * 10**_decimals, "MockSALCToken: Amount too large");
        _mint(msg.sender, amount);
    }
    
    /**
     * @dev Burns a specific amount of tokens from the caller
     * @param amount The amount of token to be burned
     */
    function burn(uint256 amount) public override {
        super.burn(amount);
    }
    
    /**
     * @dev Burns a specific amount of tokens from the specified account
     * @param account The account whose tokens will be burned
     * @param amount The amount of token to be burned
     */
    function burnFrom(address account, uint256 amount) public override {
        super.burnFrom(account, amount);
    }
    
    /**
     * @dev Change the number of decimals (for testing different configurations)
     * @param newDecimals New number of decimals
     */
    function setDecimals(uint8 newDecimals) external onlyOwner {
        _decimals = newDecimals;
    }
    
    /**
     * @dev Override decimals function
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
} 