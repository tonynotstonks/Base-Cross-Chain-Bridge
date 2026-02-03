// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract CrossChainBridgeV2 is Ownable, ReentrancyGuard {
    using MerkleProof for bytes32[];

    struct BridgeRequest {
        uint256 requestId;
        address sender;
        address receiver;
        IERC20 token;
        uint256 amount;
        uint256 chainId;
        uint256 timestamp;
        bool completed;
        bytes32 txHash;
        uint256 nonce;
        bytes signature;
    }

    struct ChainConfig {
        bool enabled;
        address bridgeContract;
        uint256 chainId;
        uint256 gasLimit;
        uint256 fee;
    }

    struct MerkleRoot {
        bytes32 root;
        uint256 timestamp;
        uint256 expiry;
    }

    mapping(uint256 => BridgeRequest) public bridgeRequests;
    mapping(uint256 => ChainConfig) public chainConfigs;
    mapping(bytes32 => bool) public processedTransactions;
    mapping(bytes32 => MerkleRoot) public merkleRoots;
    
    uint256 public nextRequestId;
    uint256 public feePercentage;
    uint256 public minimumAmount;
    uint256 public maximumAmount;
    uint256 public transactionTimeout;
    uint256 public constant MAX_CHAIN_ID = 1000000;
    
    // Events
    event TransactionInitiated(
        uint256 indexed requestId,
        address indexed sender,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 chainId,
        uint256 timestamp
    );
    
    event TransactionCompleted(
        uint256 indexed requestId,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 fee
    );
    
    event ChainConfigured(
        uint256 indexed chainId,
        address bridgeContract,
        bool enabled,
        uint256 gasLimit,
        uint256 fee
    );
    
    event FeeUpdated(uint256 newFee);
    event LimitUpdated(uint256 minimumAmount, uint256 maximumAmount);
    event TimeoutUpdated(uint256 newTimeout);
    event MerkleRootUpdated(bytes32 indexed root, uint256 timestamp, uint256 expiry);
    event TransactionCancelled(uint256 indexed requestId, address indexed sender);

    constructor(
        uint256 _feePercentage,
        uint256 _minimumAmount,
        uint256 _maximumAmount,
        uint256 _transactionTimeout
    ) {
        feePercentage = _feePercentage;
        minimumAmount = _minimumAmount;
        maximumAmount = _maximumAmount;
        transactionTimeout = _transactionTimeout;
    }

    // Configure chain
    function configureChain(
        uint256 chainId,
        address bridgeContract,
        bool enabled,
        uint256 gasLimit,
        uint256 fee
    ) external onlyOwner {
        require(chainId > 0 && chainId < MAX_CHAIN_ID, "Invalid chain ID");
        require(bridgeContract != address(0), "Invalid bridge contract");
        require(gasLimit > 0, "Invalid gas limit");
        require(fee <= 10000, "Fee too high"); // Maximum 100%
        
        chainConfigs[chainId] = ChainConfig({
            enabled: enabled,
            bridgeContract: bridgeContract,
            chainId: chainId,
            gasLimit: gasLimit,
            fee: fee
        });
        
        emit ChainConfigured(chainId, bridgeContract, enabled, gasLimit, fee);
    }

    // Set fee percentage
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= 10000, "Fee too high"); // Maximum 100%
        feePercentage = newFee;
        emit FeeUpdated(newFee);
    }

    // Set amount limits
    function setAmountLimits(uint256 newMinimum, uint256 newMaximum) external onlyOwner {
        require(newMinimum <= newMaximum, "Minimum cannot exceed maximum");
        minimumAmount = newMinimum;
        maximumAmount = newMaximum;
        emit LimitUpdated(newMinimum, newMaximum);
    }

    // Set transaction timeout
    function setTransactionTimeout(uint256 newTimeout) external onlyOwner {
        transactionTimeout = newTimeout;
        emit TimeoutUpdated(newTimeout);
    }

    // Initiate bridge
    function initiateBridge(
        uint256 chainId,
        address receiver,
        IERC20 token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external payable nonReentrant {
        require(chainConfigs[chainId].enabled, "Chain not enabled");
        require(chainId != block.chainid, "Cannot bridge to same chain");
        require(amount >= minimumAmount, "Amount below minimum");
        require(amount <= maximumAmount, "Amount above maximum");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(chainConfigs[chainId].chainId == chainId, "Wrong chain ID");
        
        // Verify signature (example)
        bytes32 messageHash = keccak256(abi.encodePacked(
            msg.sender,
            receiver,
            address(token),
            amount,
            chainId,
            nonce,
            block.timestamp
        ));
        
        // Verify signature (implementation depends on specific system)
        // This is just an example - real implementation would use actual signature verification
        
        // Calculate fees
        uint256 fee = (amount * feePercentage) / 10000;
        uint256 amountToSend = amount - fee;
        
        // Transfer tokens
        token.transferFrom(msg.sender, address(this), amount);
        
        // Deduct fees
        if (fee > 0) {
            token.transfer(owner(), fee);
        }
        
        // Create transaction
        uint256 transactionId = nextRequestId++;
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            receiver,
            address(token),
            amount,
            chainId,
            block.timestamp
        ));
        
        bridgeRequests[transactionId] = BridgeRequest({
            requestId: transactionId,
            sender: msg.sender,
            receiver: receiver,
            token: token,
            amount: amountToSend,
            chainId: chainId,
            timestamp: block.timestamp,
            completed: false,
            txHash: txHash,
            nonce: nonce,
            signature: signature
        });
        
        processedTransactions[txHash] = true;
        
        emit TransactionInitiated(
            transactionId,
            msg.sender,
            receiver,
            address(token),
            amount,
            chainId,
            block.timestamp
        );
    }

    // Complete bridge
    function completeBridge(
        uint256 transactionId,
        bytes32 txHash,
        uint256 chainId,
        bytes32[] calldata proof
    ) external nonReentrant {
        BridgeRequest storage transaction = bridgeRequests[transactionId];
        require(transaction.requestId != 0, "Invalid transaction");
        require(!transaction.completed, "Transaction already completed");
        require(processedTransactions[txHash], "Transaction not initiated");
        require(transaction.chainId == chainId, "Chain ID mismatch");
        require(block.timestamp < transaction.timestamp + transactionTimeout, "Transaction timeout");
        
        // Verify Merkle proof (if used)
        if (proof.length > 0) {
            // Verify Merkle proof
        }
        
        // Verify transaction hash
        bytes32 expectedHash = keccak256(abi.encodePacked(
            transaction.sender,
            transaction.receiver,
            address(transaction.token),
            transaction.amount,
            transaction.chainId,
            transaction.timestamp
        ));
        require(expectedHash == txHash, "Invalid transaction hash");
        
        // Transfer tokens to receiver
        transaction.token.transfer(transaction.receiver, transaction.amount);
        
        // Mark as completed
        transaction.completed = true;
        
        emit TransactionCompleted(
            transactionId,
            transaction.receiver,
            address(transaction.token),
            transaction.amount,
            chainConfigs[chainId].fee
        );
    }

    // Cancel transaction
    function cancelTransaction(
        uint256 transactionId
    ) external {
        BridgeRequest storage transaction = bridgeRequests[transactionId];
        require(transaction.requestId != 0, "Invalid transaction");
        require(!transaction.completed, "Transaction already completed");
        require(transaction.sender == msg.sender, "Not sender");
        require(block.timestamp >= transaction.timestamp + transactionTimeout, "Transaction not timed out");
        
        // Return tokens to sender
        transaction.token.transfer(transaction.sender, transaction.amount);
        
        // Mark as cancelled
        transaction.completed = true;
        
        emit TransactionCancelled(transactionId, transaction.sender);
    }

    // Set Merkle root
    function setMerkleRoot(
        bytes32 root,
        uint256 expiry
    ) external onlyOwner {
        merkleRoots[root] = MerkleRoot({
            root: root,
            timestamp: block.timestamp,
            expiry: expiry
        });
        
        emit MerkleRootUpdated(root, block.timestamp, expiry);
    }

    // Get transaction info
    function getTransactionInfo(uint256 transactionId) external view returns (BridgeRequest memory) {
        return bridgeRequests[transactionId];
    }

    // Get chain config
    function getChainConfig(uint256 chainId) external view returns (ChainConfig memory) {
        return chainConfigs[chainId];
    }

    // Check transaction status
    function getTransactionStatus(uint256 transactionId) external view returns (bool) {
        return bridgeRequests[transactionId].completed;
    }

    // Get bridge stats
    function getBridgeStats() external view returns (
        uint256 totalTransactions,
        uint256 completedTransactions,
        uint256 pendingTransactions,
        uint256 totalVolume
    ) {
        // Implementation would go here
        return (0, 0, 0, 0);
    }

    // Get active chains
    function getActiveChains() external view returns (uint256[] memory) {
        uint256[] memory chains = new uint256[](100); // Example
        uint256 count = 0;
        for (uint256 i = 1; i < 100; i++) {
            if (chainConfigs[i].enabled) {
                chains[count++] = i;
            }
        }
        return chains;
    }

    // Get user transactions
    function getUserTransactions(address user) external view returns (uint256[] memory) {
        // Implementation would go here
        return new uint256[](0);
    }
    // Добавить в структуру:
struct MultiSigTransaction {
    uint256 transactionId;
    address[] signers;
    uint256 requiredSignatures;
    bool executed;
    bool cancelled;
    uint256 timestamp;
}

// Добавить функции:
function addMultiSigSigner(address signer) external onlyOwner {
    // Добавление подписчика
}

function removeMultiSigSigner(address signer) external onlyOwner {
    // Удаление подписчика
}

function createMultiSigTransaction(
    address[] memory signers,
    uint256 requiredSignatures,
    bytes memory data
) external {
    // Создание транзакции с мульти-подписью
}
// Добавить структуры:
struct TransactionMonitor {
    uint256 transactionId;
    address sender;
    address receiver;
    address token;
    uint256 amount;
    uint256 chainId;
    uint256 timestamp;
    uint256 status; // 0: pending, 1: completed, 2: failed, 3: cancelled
    string statusMessage;
    uint256 lastUpdate;
    bytes32 txHash;
    mapping(address => bool) notificationsSent;
}

struct Notification {
    uint256 id;
    address recipient;
    string title;
    string message;
    uint256 timestamp;
    bool read;
    uint256 type; // 0: transaction, 1: system, 2: security
}

// Добавить маппинги:
mapping(uint256 => TransactionMonitor) public transactionMonitors;
mapping(address => Notification[]) public userNotifications;
mapping(address => uint256) public userNotificationCount;

// Добавить события:
event TransactionMonitored(
    uint256 indexed transactionId,
    address indexed sender,
    address indexed receiver,
    address token,
    uint256 amount,
    uint256 chainId,
    uint256 timestamp,
    string statusMessage
);

event NotificationSent(
    uint256 indexed notificationId,
    address indexed recipient,
    string title,
    string message,
    uint256 timestamp,
    uint256 type
);

event TransactionStatusUpdated(
    uint256 indexed transactionId,
    uint256 status,
    string statusMessage,
    uint256 timestamp
);

// Добавить функции:
function monitorTransaction(
    uint256 transactionId,
    address sender,
    address receiver,
    address token,
    uint256 amount,
    uint256 chainId
) external {
    require(transactionId > 0, "Invalid transaction ID");
    
    TransactionMonitor storage monitor = transactionMonitors[transactionId];
    
    monitor.transactionId = transactionId;
    monitor.sender = sender;
    monitor.receiver = receiver;
    monitor.token = token;
    monitor.amount = amount;
    monitor.chainId = chainId;
    monitor.timestamp = block.timestamp;
    monitor.status = 0; // pending
    monitor.statusMessage = "Transaction initiated";
    monitor.lastUpdate = block.timestamp;
    
    emit TransactionMonitored(transactionId, sender, receiver, token, amount, chainId, block.timestamp, "Transaction initiated");
}

function updateTransactionStatus(
    uint256 transactionId,
    uint256 status,
    string memory statusMessage
) external {
    TransactionMonitor storage monitor = transactionMonitors[transactionId];
    require(monitor.transactionId != 0, "Transaction not found");
    
    monitor.status = status;
    monitor.statusMessage = statusMessage;
    monitor.lastUpdate = block.timestamp;
    
    emit TransactionStatusUpdated(transactionId, status, statusMessage, block.timestamp);
    
    // Send notification
    sendTransactionNotification(transactionId, status, statusMessage);
}

function sendTransactionNotification(
    uint256 transactionId,
    uint256 status,
    string memory statusMessage
) internal {
    TransactionMonitor storage monitor = transactionMonitors[transactionId];
    
    // Send notification to sender
    if (monitor.sender != address(0) && !monitor.notificationsSent[monitor.sender]) {
        sendNotification(monitor.sender, "Transaction Status Update", 
            string(abi.encodePacked("Transaction ", transactionId, " status: ", statusMessage)), 0);
        monitor.notificationsSent[monitor.sender] = true;
    }
    
    // Send notification to receiver
    if (monitor.receiver != address(0) && !monitor.notificationsSent[monitor.receiver]) {
        sendNotification(monitor.receiver, "Transaction Received", 
            string(abi.encodePacked("You received a transaction ", transactionId, " with status: ", statusMessage)), 0);
        monitor.notificationsSent[monitor.receiver] = true;
    }
}

function sendNotification(
    address recipient,
    string memory title,
    string memory message,
    uint256 type
) internal {
    uint256 notificationId = userNotificationCount[recipient]++;
    
    Notification memory notification = Notification({
        id: notificationId,
        recipient: recipient,
        title: title,
        message: message,
        timestamp: block.timestamp,
        read: false,
        type: type
    });
    
    userNotifications[recipient].push(notification);
    
    emit NotificationSent(notificationId, recipient, title, message, block.timestamp, type);
}

function getUserNotifications(address user) external view returns (Notification[] memory) {
    return userNotifications[user];
}

function markNotificationAsRead(address user, uint256 notificationId) external {
    require(notificationId < userNotifications[user].length, "Invalid notification ID");
    
    userNotifications[user][notificationId].read = true;
}

function getTransactionMonitor(uint256 transactionId) external view returns (TransactionMonitor memory) {
    return transactionMonitors[transactionId];
}

function getTransactionStatus(uint256 transactionId) external view returns (uint256) {
    return transactionMonitors[transactionId].status;
}

function getTransactionStatusMessage(uint256 transactionId) external view returns (string memory) {
    return transactionMonitors[transactionId].statusMessage;
}
}
