// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MyUSD.sol";

error Staking__InvalidAmount();
error Staking__InsufficientBalance();
error Staking__InsufficientAllowance();
error Staking__TransferFailed();
error Staking__InvalidInterestRate();

contract Staking is Ownable, ReentrancyGuard {
    MyUSD public immutable myUSD;

    // Total shares in the pool
    uint256 public totalShares;

    // Exchange rate between shares and MyUSD (1e18 precision)
    uint256 public exchangeRate;

    // Last update timestamp
    uint256 public lastUpdateTime;

    // Interest rate in basis points (1% = 100)
    uint256 public interestRate;

    // User's share balance
    mapping(address => uint256) public userShares;

    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    event Staked(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event InterestRateUpdated(uint256 newRate);
    event InterestAccrued(uint256 amount);

    constructor(address _myUSD) Ownable(msg.sender) {
        myUSD = MyUSD(_myUSD);
        exchangeRate = PRECISION; // 1:1 initially
        lastUpdateTime = block.timestamp;
    }

    function setInterestRate(uint256 newRate) external onlyOwner {
        _accrueInterest();
        interestRate = newRate;
        emit InterestRateUpdated(newRate);
    }

    function _accrueInterest() internal {
        if (totalShares == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0) return;

        // Calculate interest based on total shares and exchange rate
        uint256 totalValue = (totalShares * exchangeRate) / PRECISION;
        uint256 interest = (totalValue * interestRate * timeElapsed) / (SECONDS_PER_YEAR * 10000);

        if (interest > 0) {
            // Update exchange rate to reflect new value
            exchangeRate += (interest * PRECISION) / totalShares;
            emit InterestAccrued(interest);
        }

        lastUpdateTime = block.timestamp;
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert Staking__InvalidAmount();

        _accrueInterest();

        // Calculate shares based on current exchange rate
        uint256 shares = (amount * PRECISION) / exchangeRate;

        // Update user's shares and total shares
        userShares[msg.sender] += shares;
        totalShares += shares;

        // Transfer tokens to contract
        bool success = myUSD.transferFrom(msg.sender, address(this), amount);
        if (!success) revert Staking__TransferFailed();

        emit Staked(msg.sender, amount, shares);
    }

    function withdraw(uint256 shareAmount) external nonReentrant {
        if (shareAmount == 0) revert Staking__InvalidAmount();
        if (userShares[msg.sender] < shareAmount) revert Staking__InsufficientBalance();

        _accrueInterest();

        // Calculate MyUSD amount based on current exchange rate
        uint256 amount = (shareAmount * exchangeRate) / PRECISION;

        // Update user's shares and total shares
        userShares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;

        // Transfer tokens to user
        bool success = myUSD.transfer(msg.sender, amount);
        if (!success) revert Staking__TransferFailed();

        emit Withdrawn(msg.sender, amount, shareAmount);
    }

    function getBalance(address user) external view returns (uint256) {
        if (userShares[user] == 0) return 0;

        // Calculate current exchange rate with accrued interest
        uint256 currentExchangeRate = exchangeRate;
        if (totalShares > 0) {
            uint256 timeElapsed = block.timestamp - lastUpdateTime;
            if (timeElapsed > 0) {
                uint256 totalValue = (totalShares * exchangeRate) / PRECISION;
                uint256 interest = (totalValue * interestRate * timeElapsed) / (SECONDS_PER_YEAR * 10000);
                if (interest > 0) {
                    currentExchangeRate += (interest * PRECISION) / totalShares;
                }
            }
        }

        return (userShares[user] * currentExchangeRate) / PRECISION;
    }
}
