// base-crosschain-bridge/scripts/monitor.js
const { ethers } = require("hardhat");

async function monitorBridge() {
  console.log("Monitoring Base Cross-Chain Bridge...");
  
  // Получаем адрес контракта
  const bridgeAddress = "0x...";
  
  const bridge = await ethers.getContractAt("CrossChainBridgeV3", bridgeAddress);
  
  // Мониторинг транзакций
  console.log("Monitoring bridge transactions...");
  
  // Получение статистики
  const stats = await bridge.getBridgeStats();
  console.log("Bridge Stats:", {
    totalTransactions: stats.totalTransactions.toString(),
    completedTransactions: stats.completedTransactions.toString(),
    pendingTransactions: stats.pendingTransactions.toString(),
    totalVolume: stats.totalVolume.toString(),
    totalFees: stats.totalFees.toString()
  });
  
  // Наблюдение за событиями
  bridge.on("TransactionInitiated", (transactionId, sender, receiver, token, amount, timestamp) => {
    console.log(`Transaction initiated: ${transactionId} from ${sender}`);
  });
  
  bridge.on("TransactionCompleted", (transactionId, receiver, token, amount) => {
    console.log(`Transaction completed: ${transactionId} to ${receiver}`);
  });
  
  console.log("Monitoring started. Press Ctrl+C to stop.");
  
  // Запуск мониторинга на 10 минут
  setTimeout(() => {
    console.log("Monitoring stopped.");
    process.exit(0);
  }, 600000); // 10 минут
}

monitorBridge()
  .catch(error => {
    console.error("Monitoring error:", error);
    process.exit(1);
  });
