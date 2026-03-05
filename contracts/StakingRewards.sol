// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title StakingRewards
 * @dev Standard staking contract using rewardPerToken logic for gas efficiency.
 * Users stake an ERC20 token (e.g., LP Token) and earn another ERC20 token as reward.
 */
contract StakingRewards is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken; // The token users stake (e.g., LP Token)
    IERC20 public immutable rewardsToken; // The token users earn as reward

    // Reward configuration
    uint256 public rewardRate; // Rewards per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    // User data
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances; // Staked balance per user

    uint256 private _totalSupply;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward);

    constructor(address _stakingToken, address _rewardsToken) {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    // --- View Functions ---

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Calculate current rewardPerToken including pending rewards
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((rewardRate * (block.timestamp - lastUpdateTime)) * 1e18) / _totalSupply);
    }

    /**
     * @dev Calculate earned rewards for a specific user
     */
    function earned(address account) public view returns (uint256) {
        return
            ((_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    // --- Modifiers ---

    /**
     * @dev Updates reward global state before modifying user data
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // --- State Changing Functions ---

    /**
     * @dev Stake tokens
     * @param amount Amount of stakingToken to deposit
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        
        // Transfer tokens from user to contract
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Withdraw staked tokens
     * @param amount Amount of stakingToken to withdraw
     */
    function withdraw(uint256 amount) public nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        
        stakingToken.safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Claim earned rewards
     */
    function getReward() public nonReentrant whenNotPaused updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @dev Exit: Withdraw all stake and claim all rewards
     */
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    // --- Admin Functions (Simplified for learning) ---
    // In production, add Ownable access control
    
    function notifyRewardAmount(uint256 reward) external updateReward(address(0)) {
        // Logic to add more rewards to the contract balance would go here
        // Ensure contract has enough rewardsToken balance before calling
        rewardRate = reward / 7 days; // Example: distribute over 7 days
        lastUpdateTime = block.timestamp;
        emit RewardAdded(reward);
    }
}