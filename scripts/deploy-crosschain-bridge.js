const fs = require("fs");
const path = require("path");
require("dotenv").config();

function parseList(v) {
  return (v || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // Token to bridge: set BRIDGE_TOKEN or it deploys a simple ERC20 from TokenManager if available
  let token = process.env.BRIDGE_TOKEN || "";

  if (!token) {
    // If TokenManager is an ERC20-ish helper in your repo, use it. If not, set BRIDGE_TOKEN in .env.
    const Token = await ethers.getContractFactory("TokenManager");
    const t = await Token.deploy("BridgeToken", "BRG", 18);
    await t.deployed();
    token = t.address;
    console.log("Deployed BridgeToken (TokenManager):", token);
  }

  const thisChainId = Number(process.env.THIS_CHAIN_ID || "8453"); // Base mainnet default
  const validators = parseList(process.env.VALIDATORS);
  const threshold = Number(process.env.THRESHOLD || "1");

  if (validators.length === 0) validators.push(deployer.address);

  const Bridge = await ethers.getContractFactory("CrossChainBridge");
  const bridge = await Bridge.deploy(token, thisChainId, validators, threshold);
  await bridge.deployed();

  console.log("CrossChainBridge:", bridge.address);

  const out = {
    network: hre.network.name,
    chainId: (await ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      Token: token,
      CrossChainBridge: bridge.address
    },
    params: { thisChainId, validators, threshold }
  };

  const outPath = path.join(__dirname, "..", "deployments.json");
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("Saved:", outPath);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
