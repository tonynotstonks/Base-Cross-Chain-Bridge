# base-crosschain-bridge/contracts/Bridge.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CrossChainBridge is Ownable {
    struct BridgeRequest {
        uint256 requestId;
        address sender;
        address receiver;
        IERC20 token;
        uint256 amount;
        uint256 timestamp;
        bool completed;
    }
    
    mapping(uint256 => BridgeRequest) public bridgeRequests;
    mapping(bytes32 => bool) public completedRequests;
    
    uint256 public nextRequestId;
    address public baseChainAddress;
    address public destinationChainAddress;
    
    event BridgeInitiated(
        uint256 indexed requestId,
        address indexed sender,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 timestamp
    );
    
    event BridgeCompleted(
        uint256 indexed requestId,
        address indexed receiver,
        address token,
        uint256 amount
    );
    
    constructor(
        address _baseChainAddress,
        address _destinationChainAddress
    ) {
        baseChainAddress = _baseChainAddress;
        destinationChainAddress = _destinationChainAddress;
    }
    
    function initiateBridge(
        address receiver,
        IERC20 token,
        uint256 amount
    ) external {
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        uint256 requestId = nextRequestId++;
        bytes32 requestHash = keccak256(abi.encodePacked(receiver, address(token), amount, requestId));
        
        bridgeRequests[requestId] = BridgeRequest({
            requestId: requestId,
            sender: msg.sender,
            receiver: receiver,
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            completed: false
        });
        
        completedRequests[requestHash] = false;
        
        emit BridgeInitiated(requestId, msg.sender, receiver, address(token), amount, block.timestamp);
    }
    
    function completeBridge(
        uint256 requestId,
        bytes32 requestHash
    ) external {
        require(completedRequests[requestHash] == false, "Request already completed");
        require(bridgeRequests[requestId].completed == false, "Request already completed");
        
        BridgeRequest storage request = bridgeRequests[requestId];
        require(request.sender != address(0), "Invalid request");
        
        completedRequests[requestHash] = true;
        request.completed = true;
        
        // Transfer tokens to receiver
        request.token.transfer(request.receiver, request.amount);
        
        emit BridgeCompleted(requestId, request.receiver, address(request.token), request.amount);
    }
    
    function withdrawTokens(
        IERC20 token,
        uint256 amount
    ) external onlyOwner {
        token.transfer(owner(), amount);
    }
}
