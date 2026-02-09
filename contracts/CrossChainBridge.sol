// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Educational bridge: Lock on source, Mint on destination (or vice versa).
  Improvements:
  - Replay protection via nonces + message hash
  - Threshold validator signatures (simplified)
  WARNING: Not production-ready.
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BaseCrossChainBridge is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    IERC20 public immutable token;           // bridged token (lock/mint model simplified)
    uint256 public immutable thisChainId;    // set at deploy
    uint256 public threshold;                // required validator signatures

    mapping(address => bool) public isValidator;
    uint256 public validatorCount;

    mapping(uint256 => bool) public usedNonce; // nonce replay protection

    event Locked(address indexed user, uint256 amount, uint256 indexed toChainId, address indexed to, uint256 nonce);
    event Released(address indexed user, uint256 amount, uint256 indexed fromChainId, address indexed to, uint256 nonce);

    constructor(address _token, uint256 _thisChainId, address[] memory validators, uint256 _threshold)
        Ownable(msg.sender)
    {
        require(_token != address(0), "token=0");
        require(validators.length > 0, "no validators");
        require(_threshold > 0 && _threshold <= validators.length, "bad threshold");

        token = IERC20(_token);
        thisChainId = _thisChainId;
        threshold = _threshold;

        for (uint256 i = 0; i < validators.length; i++) {
            address v = validators[i];
            require(v != address(0), "validator=0");
            require(!isValidator[v], "dup");
            isValidator[v] = true;
            validatorCount++;
        }
    }

    function setThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0 && _threshold <= validatorCount, "bad threshold");
        threshold = _threshold;
    }

    // User locks tokens on source chain.
    function lock(uint256 amount, uint256 toChainId, address to, uint256 nonce) external nonReentrant {
        require(amount > 0, "amount=0");
        require(to != address(0), "to=0");
        require(toChainId != thisChainId, "same chain");
        require(!usedNonce[nonce], "nonce used");

        usedNonce[nonce] = true;
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(msg.sender, amount, toChainId, to, nonce);
    }

    // Release tokens on destination chain, authorized by validator signatures over message.
    function release(
        address from,
        address to,
        uint256 amount,
        uint256 fromChainId,
        uint256 nonce,
        bytes[] calldata signatures
    ) external nonReentrant {
        require(to != address(0), "to=0");
        require(amount > 0, "amount=0");
        require(fromChainId != thisChainId, "bad fromChain");
        require(!usedNonce[nonce], "nonce used");
        require(signatures.length >= threshold, "not enough sigs");

        bytes32 msgHash = keccak256(abi.encodePacked("RELEASE", from, to, amount, fromChainId, thisChainId, nonce))
            .toEthSignedMessageHash();

        _verifyThreshold(msgHash, signatures);

        usedNonce[nonce] = true;
        token.safeTransfer(to, amount);

        emit Released(from, amount, fromChainId, to, nonce);
    }

    function _verifyThreshold(bytes32 msgHash, bytes[] calldata signatures) internal view {
        // naive duplicate-check via last seen address array (educational)
        address[] memory seen = new address[](signatures.length);
        uint256 valid;

        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = msgHash.recover(signatures[i]);
            if (!isValidator[signer]) continue;

            bool dup;
            for (uint256 j = 0; j < valid; j++) {
                if (seen[j] == signer) { dup = true; break; }
            }
            if (dup) continue;

            seen[valid] = signer;
            valid++;
            if (valid >= threshold) return;
        }

        revert("threshold not met");
    }
}
