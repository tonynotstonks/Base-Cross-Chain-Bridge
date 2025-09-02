// base-crosschain-bridge/contracts/TokenBridge.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenBridge is Ownable {
    struct BridgeConfig {
        bool enabled;
        uint256 feePercentage;
        uint256 maxAmount;
        uint256 minAmount;
    }
    
    mapping(address => BridgeConfig) public bridgeConfigs;
    
    event BridgeConfigUpdated(address indexed token, BridgeConfig config);
    event TokensBridged(address indexed from, address indexed to, address indexed token, uint256 amount);
    
    function setBridgeConfig(
        address token,
        bool enabled,
        uint256 feePercentage,
        uint256 maxAmount,
        uint256 minAmount
    ) external onlyOwner {
        bridgeConfigs[token] = BridgeConfig({
            enabled: enabled,
            feePercentage: feePercentage,
            maxAmount: maxAmount,
            minAmount: minAmount
        });
        
        emit BridgeConfigUpdated(token, bridgeConfigs[token]);
    }
    
    function bridgeTokens(
        address token,
        uint256 amount,
        address destination
    ) external {
        BridgeConfig storage config = bridgeConfigs[token];
        require(config.enabled, "Bridge not enabled");
        require(amount >= config.minAmount, "Amount below minimum");
        require(amount <= config.maxAmount, "Amount above maximum");
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        uint256 fee = (amount * config.feePercentage) / 10000;
        if (fee > 0) {
            IERC20(token).transfer(owner(), fee);
        }
        
        emit TokensBridged(msg.sender, destination, token, amount);
    }
    
    function getBridgeConfig(address token) external view returns (BridgeConfig memory) {
        return bridgeConfigs[token];
    }
}
