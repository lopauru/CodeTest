// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./openzeppelin/contracts/utils/EnumerableSet.sol";
import "./openzeppelin/contracts/math/SafeMath.sol";
import "./openzeppelin/contracts/access/Ownable.sol";
import "./GhostToken.sol";
import "./GhostTalons.sol";

contract GhostFarmContract is Ownable {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Ghost
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (userInfo.amount * pool.accGhostPerShare) - userInfo.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accGhostPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of token or LP contract
        uint256 allocPoint; // How many allocation points assigned to this pool. Ghost to distribute per block.
        uint256 lastRewardBlock; // Last block number that Ghost distribution occurs.
        uint256 accGhostPerShare; // Accumulated Ghost per share, times 1e12. See below.
    }

    // Ghost tokens created first block.
    uint256 public GhostStartBlock;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Ghost mining starts. - Mainnet: Block - 2,866,144
    uint256 public startBlock;
    // Block number when bonus Ghost period ends.
    uint256 public bonusEndBlock;
    // how many block size will change the common difference before bonus end.
    uint256 public bonusBeforeBulkBlockSize;
    // how many block size will change the common difference after bonus end.
    uint256 public bonusEndBulkBlockSize;
    // Ghost tokens created at bonus end block.
    uint256 public GhostBonusEndBlock;
    // max reward block
    uint256 public maxRewardBlockNumber;
    // bonus before the common difference
    uint256 public bonusBeforeCommonDifference;
    // bonus after the common difference
    uint256 public bonusEndCommonDifference;
    // Accumulated Ghost per share, times 1e12.
    uint256 public accGhostPerShareMultiple = 1E12;
    // Ghost Token
    GhostToken public Ghost;
    // GhostTalons
    GhostTalons public talons;
    // Devs address.
    address public devAddr;
    // Info on each pool added
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        GhostToken _Ghost,
        GhostTalons _talons,
        address _devAddr,
        uint256 _GhostStartBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _bonusEndBulkBlockSize,
        uint256 _bonusBeforeBulkBlockSize,
        uint256 _bonusBeforeCommonDifference,
        uint256 _bonusEndCommonDifference,
        uint256 _GhostBonusEndBlock,
        uint256 _maxRewardBlockNumber
    ) public {
        Ghost = _Ghost;
        talons = _talons;
        devAddr = _devAddr;
        GhostStartBlock = _GhostStartBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        bonusBeforeBulkBlockSize = _bonusBeforeBulkBlockSize;
        bonusBeforeCommonDifference = _bonusBeforeCommonDifference;
        bonusEndCommonDifference = _bonusEndCommonDifference;
        bonusEndBulkBlockSize = _bonusEndBulkBlockSize;
        GhostBonusEndBlock = _GhostBonusEndBlock;
        maxRewardBlockNumber = _maxRewardBlockNumber;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _Ghost,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accGhostPerShare: 0
        }));

        totalAllocPoint = 1000;
    }

    // Pool Length
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Detects whether the given pool already exists
    function checkIsExistingPool(IERC20 _lpToken) public {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: existing pool");
        }
    }

    // Add a new token or LP to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _token, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        checkIsExistingPool(_token);
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
          lpToken: _token,
          allocPoint: _allocPoint,
          lastRewardBlock: lastRewardBlock,
          accGhostPerShare: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's Ghost allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(4);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    function checkGhostRewardPerBlockByBlock(uint256 _blockToCheck) public view returns (uint256 currentBlockGhost) {
      uint256 _blockNumber = _blockToCheck;
      if (_blockNumber <= startBlock || maxRewardBlockNumber <= _blockNumber) {
          return 0;
      }

      uint256 _GhostStartBlock = GhostStartBlock;
      uint256 _bulkBlockSize = bonusBeforeBulkBlockSize;
      uint256 _commonDifference = bonusBeforeCommonDifference;

      if (_blockNumber >= bonusEndBlock) {
        _GhostStartBlock = GhostBonusEndBlock;
        _bulkBlockSize = bonusEndBulkBlockSize;
        _commonDifference = bonusEndCommonDifference;
      }
      uint256 fromBulkNumber = _blockNumber.sub(startBlock).div(_bulkBlockSize);

      currentBlockGhost = _getBulkBlockRewardNumber(_GhostStartBlock, fromBulkNumber, _commonDifference);
    }

    function _getBulkBlockRewardNumber(
      uint256 _GhostInitBlock,
      uint256 _bulkNumber,
      uint256 _reductionDifference
    ) internal pure returns (uint256 GhostCurBlock) {
        GhostCurBlock = _GhostInitBlock;
        for (uint256 i = 0; _bulkNumber > 0 && i < _bulkNumber; i ++) {
            uint256 diff = GhostCurBlock.mul(_reductionDifference).div(1000);
            GhostCurBlock = GhostCurBlock.sub(diff);
        }
    }

    function getCurrentGhostRewardPerBlock() public view returns (uint256 currentBlockGhost) {
      uint256 _blockNumber = block.number;
      if (_blockNumber <= startBlock || maxRewardBlockNumber <= _blockNumber) {
          return 0;
      }

      uint256 _GhostStartBlock = GhostStartBlock;
      uint256 _bulkBlockSize = bonusBeforeBulkBlockSize;
      uint256 _commonDifference = bonusBeforeCommonDifference;

      if (_blockNumber >= bonusEndBlock) {
        _GhostStartBlock = GhostBonusEndBlock;
        _bulkBlockSize = bonusEndBulkBlockSize;
        _commonDifference = bonusEndCommonDifference;
      }
      uint256 fromBulkNumber = _blockNumber.sub(startBlock).div(_bulkBlockSize);

      currentBlockGhost = _getBulkBlockRewardNumber(_GhostStartBlock, fromBulkNumber, _commonDifference);
    }

    // (_from,_to]
    function getTotalRewardInfoInSameCommonDifference(
        uint256 _from,
        uint256 _to,
        uint256 _GhostInitBlock,
        uint256 _bulkBlockSize,
        uint256 _commonDifference
    ) public view returns (uint256 totalReward) {
        if (_to <= startBlock || maxRewardBlockNumber <= _from) {
            return 0;
        }
        if (_from < startBlock) {
            _from = startBlock;
        }
        if (maxRewardBlockNumber < _to) {
            _to = maxRewardBlockNumber;
        }
        uint256 currentBulkNumber = _to.sub(startBlock).div(_bulkBlockSize).add(
            _to.sub(startBlock).mod(_bulkBlockSize) > 0 ? 1 : 0
        );
        if (currentBulkNumber < 1) {
            currentBulkNumber = 1;
        }
        uint256 fromBulkNumber = _from.sub(startBlock).div(_bulkBlockSize).add(
            _from.sub(startBlock).mod(_bulkBlockSize) > 0 ? 1 : 0
        );
        if (fromBulkNumber < 1) {
            fromBulkNumber = 1;
        }
        if (fromBulkNumber == currentBulkNumber) {
            uint256 bulkBlockReward = _getBulkBlockRewardNumber(_GhostInitBlock, currentBulkNumber, _commonDifference);
            return _to.sub(_from).mul(bulkBlockReward);
        }
        uint256 lastRewardBulkLastBlock = startBlock.add(_bulkBlockSize.mul(fromBulkNumber));
        uint256 currentPreviousBulkLastBlock = startBlock.add(_bulkBlockSize.mul(currentBulkNumber.sub(1)));
        {
            uint256 tempFrom = _from;
            uint256 tempTo = _to;
            uint256 tempBulkReward = _getBulkBlockRewardNumber(_GhostInitBlock, currentBulkNumber, _commonDifference);
            totalReward = tempTo
            .sub(tempFrom > currentPreviousBulkLastBlock ? tempFrom : currentPreviousBulkLastBlock)
            .mul(tempBulkReward);
            if (lastRewardBulkLastBlock > tempFrom && lastRewardBulkLastBlock <= tempTo) {
                uint256 tempFromBulkReward = _getBulkBlockRewardNumber(_GhostInitBlock, fromBulkNumber > 0 ? fromBulkNumber : 0, _commonDifference);
                totalReward = totalReward.add(
                    lastRewardBulkLastBlock.sub(tempFrom).mul(tempFromBulkReward)
                );
            }
        }
        {
            // avoids stack too deep errors
            uint256 tempGhostInitBlock = _GhostInitBlock;
            uint256 tempBulkBlockSize = _bulkBlockSize;
            uint256 tempCommonDifference = _commonDifference;
            if (currentPreviousBulkLastBlock > lastRewardBulkLastBlock) {
                uint256 tempCurrentPreviousBulkLastBlock = currentPreviousBulkLastBlock;
                // sum( [fromBulkNumber+1, currentBulkNumber] )
                // 1/2 * N *( a1 + aN)
                uint256 N = tempCurrentPreviousBulkLastBlock.sub(lastRewardBulkLastBlock).div(tempBulkBlockSize);
                if (N > 1) {
                    uint256 lastBulkBlockReward = _getBulkBlockRewardNumber(
                      tempGhostInitBlock,
                      lastRewardBulkLastBlock.sub(startBlock).div(tempBulkBlockSize),
                      tempCommonDifference
                    );
                    uint256 a1 = tempBulkBlockSize.mul(lastBulkBlockReward);
                    uint256 tempCurrentPreviousBulkBlockReward = _getBulkBlockRewardNumber(
                      tempGhostInitBlock,
                      tempCurrentPreviousBulkLastBlock.sub(startBlock).div(tempBulkBlockSize).sub(1),
                      tempCommonDifference
                    );
                    uint256 aN = tempBulkBlockSize.mul(tempCurrentPreviousBulkBlockReward);
                    totalReward = totalReward.add(N.mul(a1.add(aN)).div(2));
                } else {
                    uint256 currentBulkBlockReward = _getBulkBlockRewardNumber(
                      tempGhostInitBlock,
                      currentBulkNumber.sub(2),
                      tempCommonDifference
                    );
                    totalReward = totalReward.add(
                        tempBulkBlockSize.mul(currentBulkBlockReward)
                    );
                }
            }
        }
    }

    // Return total reward over the given _from to _to block.
    function getTotalRewardInfo(uint256 _from, uint256 _to) public view returns (uint256 totalReward) {
        if (_to <= bonusEndBlock) {
            totalReward = getTotalRewardInfoInSameCommonDifference(
                _from,
                _to,
                GhostStartBlock,
                bonusBeforeBulkBlockSize,
                bonusBeforeCommonDifference
            );
        } else if (_from >= bonusEndBlock) {
            totalReward = getTotalRewardInfoInSameCommonDifference(
                _from,
                _to,
                GhostBonusEndBlock,
                bonusEndBulkBlockSize,
                bonusEndCommonDifference
            );
        } else {
            totalReward = getTotalRewardInfoInSameCommonDifference(
                _from,
                bonusEndBlock,
                GhostStartBlock,
                bonusBeforeBulkBlockSize,
                bonusBeforeCommonDifference
            )
            .add(
                getTotalRewardInfoInSameCommonDifference(
                    bonusEndBlock,
                    _to,
                    GhostBonusEndBlock,
                    bonusEndBulkBlockSize,
                    bonusEndCommonDifference
                )
            );
        }
    }

    // View function to see pending Ghost on frontend.
    function pendingGhost(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accGhostPerShare = pool.accGhostPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0 && pool.lastRewardBlock < maxRewardBlockNumber) {
            uint256 totalReward = getTotalRewardInfo(pool.lastRewardBlock, block.number);
            uint256 GhostReward = totalReward.mul(pool.allocPoint).div(totalAllocPoint);
            accGhostPerShare = accGhostPerShare.add(GhostReward.mul(accGhostPerShareMultiple).div(lpSupply));
        }
        return user.amount.mul(accGhostPerShare).div(accGhostPerShareMultiple).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (pool.lastRewardBlock >= maxRewardBlockNumber) {
            return;
        }
        uint256 totalReward = getTotalRewardInfo(pool.lastRewardBlock, block.number);
        uint256 GhostReward = totalReward.mul(pool.allocPoint).div(totalAllocPoint);
        Ghost.mint(devAddr, GhostReward.div(12)); // 8.3% Ghost devs fund (100/12 = 8.333)
        Ghost.mint(address(talons), GhostReward);
        pool.accGhostPerShare = pool.accGhostPerShare.add(GhostReward.mul(accGhostPerShareMultiple).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens for Ghost allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require (_pid != 0, 'Please deposit Ghost by staking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple).sub(user.rewardDebt);
            if (pending > 0) {
                safeGhostTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens
    function withdraw(uint256 _pid, uint256 _amount) public {
        require (_pid != 0, 'Please withdraw Ghost by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, 'withdraw: not good');
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple).sub(user.rewardDebt);
        if (pending > 0) {
            safeGhostTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        require (_pid != 0, 'Please use leaveStaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Stake Ghost tokens to FarmContract
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple).sub(user.rewardDebt);
            if(pending > 0) {
                safeGhostTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount); //transfer Ghost to staking
            uint256 rateAmount = 1; //burn 1% 18.00-06.00 UTC time
            uint256 getHour = (block.timestamp / 60 / 60) % 24; //get hour in utc time
            if(getHour >= 6 && getHour < 18){ //burn 3% 06.00-18.00 UTC time
                rateAmount = 3;
            }
            uint256 burnAmount = _amount.mul(rateAmount).div(100); // every transfer burnt
            uint256 sendAmount = _amount.sub(burnAmount); // transfer sent to recipient
            require(_amount == sendAmount + burnAmount, "value invalid");
            user.amount = user.amount.add(sendAmount); //add user amount 99% or 97% Ghost to staking
            talons.mint(msg.sender, sendAmount); //mint talons to user
        }
        user.rewardDebt = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw Ghost tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple).sub(user.rewardDebt);
        if(pending > 0) {
            safeGhostTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accGhostPerShare).div(accGhostPerShareMultiple);

        talons.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Safe Ghost transfer function, just in case if rounding error causes pool to not have enough $Ghost
    function safeGhostTransfer(address _to, uint256 _amount) internal {
        talons.safeGhostTransfer(_to, _amount);
    }

    // Update dev address by the previous dev.
    function dev(address _devAddr) public {
        require(msg.sender == devAddr, 'you no dev: wut?');
        devAddr = _devAddr;
    }
}