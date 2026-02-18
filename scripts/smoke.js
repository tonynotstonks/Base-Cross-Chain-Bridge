require("dotenv").config();
const fs = require("fs");
const path = require("path");

async function main() {
  const depPath = path.join(__dirname, "..", "deployments.json");
  const deployments = JSON.parse(fs.readFileSync(depPath, "utf8"));

  const bridgeAddr = deployments.contracts.CrossChainBridge;
  const tokenAddr = deployments.contracts.Token;

  const [owner, user] = await ethers.getSigners();
  const bridge = await ethers.getContractAt("CrossChainBridge", bridgeAddr);
  const token = await ethers.getContractAt("TokenManager", tokenAddr);

  console.log("Bridge:", bridgeAddr);

  // Mint to user (TokenManager assumed mintable)
  const amt = ethers.utils.parseUnits("10", 18);
  await (await token.mint(user.address, amt)).wait();
  await (await token.connect(user).approve(bridgeAddr, amt)).wait();

  // Lock
  await (await bridge.connect(user).lock(amt, 999, user.address, 1)).wait();
  console.log("Locked");

  // Pause/unpause smoke
  await (await bridge.pause()).wait();
  console.log("Paused");
  await (await bridge.unpause()).wait();
  console.log("Unpaused");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

