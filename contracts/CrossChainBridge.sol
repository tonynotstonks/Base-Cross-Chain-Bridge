// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract CrossChainBridge is Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public thisChainId;

    mapping(address => bool) public isValidator;
    uint256 public validatorCount;
    uint256 public threshold;

    mapping(bytes32 => bool) public processed;

    event Locked(address indexed user, uint256 amount, uint256 toChain);
    event Released(address indexed to, uint256 amount, bytes32 txHash);

    constructor(
        address _token,
        uint256 _chainId,
        address[] memory validators,
        uint256 _threshold
    ) {
        token = IERC20(_token);
        thisChainId = _chainId;

        for (uint i = 0; i < validators.length; i++) {
            isValidator[validators[i]] = true;
        }

        validatorCount = validators.length;
        threshold = _threshold;
    }

    function lock(uint256 amount, uint256 toChain) external whenNotPaused {
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, toChain);
    }

    function release(
        address to,
        uint256 amount,
        bytes32 txHash
    ) external {
        require(isValidator[msg.sender], "not validator");
        require(!processed[txHash], "processed");

        processed[txHash] = true;

        token.safeTransfer(to, amount);

        emit Released(to, amount, txHash);
    }

    function addValidator(address v) external onlyOwner {
        isValidator[v] = true;
        validatorCount++;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
