// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YieldFarm
 * @dev A farming contract that accepts LP tokens and distributes reward tokens per block.
 * This is the core engine of yield farming strategies.
 */
contract YieldFarm is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // The LP Token users must stake (e.g., ETH-USDC LP)
    IERC20 public immutable lpToken;
    // The Reward Token users earn (e.g., FARM Token)
    IERC20 public immutable rewardToken;

    // Reward configuration
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare; // Accumulated rewards per share

    // Total staked LP tokens
    uint256 public totalStaked;

    // User information
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has staked
        uint256 rewardDebt; // Reward debt to handle pending rewards calculation
    }
    mapping(address => UserInfo) public userInfo;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 amount);

    constructor(address _lpToken, address _rewardToken, uint256 _rewardPerBlock) {
        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
        rewardPerBlock = _rewardPerBlock;
        lastRewardBlock = block.number;
    }

    /**
     * @dev Update reward variables based on blocks passed
     */
    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 blocksPassed = block.number - lastRewardBlock;
        uint256 reward = blocksPassed * rewardPerBlock;
        accRewardPerShare += (reward * 1e18) / totalStaked;
        lastRewardBlock = block.number;
    }

    /**
     * @dev Calculate pending rewards for a user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShareLocal = accRewardPerShare;
        
        // Calculate pending rewards based on current pool state
        uint256 pending = (user.amount * accRewardPerShareLocal) / 1e18 - user.rewardDebt;
        return pending;
    }

    /**
     * @dev Stake LP tokens to the farm
     * @param amount Amount of LP tokens to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        
        if (user.amount > 0) {
            // Calculate pending rewards before updating balance
            uint256 pending = (user.amount * accRewardPerShare) / 1e18 - user.rewardDebt;
            if (pending > 0) {
                rewardToken.safeTransfer(msg.sender, pending);
                emit Harvest(msg.sender, pending);
            }
        }

        if (amount > 0) {
            lpToken.safeTransferFrom(msg.sender, address(this), amount);
            user.amount += amount;
            totalStaked += amount;
        }

        // Update reward debt
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev Withdraw LP tokens and claim rewards
     * @param amount Amount of LP tokens to withdraw
     */
    function withdraw(uint256 amount) public nonReentrant {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= amount, "Insufficient balance");

        // Calculate and transfer pending rewards
        uint256 pending = (user.amount * accRewardPerShare) / 1e18 - user.rewardDebt;
        if (pending > 0) {
            rewardToken.safeTransfer(msg.sender, pending);
            emit Harvest(msg.sender, pending);
        }

        if (amount > 0) {
            user.amount -= amount;
            totalStaked -= amount;
            lpToken.safeTransfer(msg.sender, amount);
        }

        // Update reward debt
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Claim rewards without withdrawing stake
     */
    function harvest() external {
        withdraw(0);
    }
}