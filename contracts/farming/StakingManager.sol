//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract StakingManager is AccessControl {
    using SafeERC20 for IERC20;
    IERC20 public rewardToken;

    uint256 private rewardTokensPerBlock; // so token reward tren moi block, dung chung cho cac pool tao tu chung 1 farm
    uint256 private constant REWARDS_PRECISION = 1e12;
    uint256 public constant MAX_FEE = 100;

    bytes32 public constant POOLE_ROLE = keccak256("POOL_ROLE");

    struct UserStaker {
        uint256 amount; // so luong lp token user da supply
        uint256 rewards;
        uint256 expireTime; // thoi diem ma luong amount user stake vao 1 pool se bi expire
        uint256 rewardDebt; // so luong reward ma user da claim trong qua khu
    }

    struct PoolInfo {
        IERC20 stakeToken; // token dc dung de stake cho pool nay
        uint256 lastRewardedBlock;
        uint256 duration; // lock time cua moi pool, dc set khi create pool
        uint256 accumulatedRewardsPerShare; // ti le nhan reward tinh tren 1 don vi stake token da cung cap
        uint256 harvestFee; // fee ma user phai tra khi thuc hien harvest
    }

    PoolInfo[] public pools; // 1 farm se co 1 list pool, moi pool co the dinh nghia 1 stake token khac nhau
    mapping(uint256 => mapping(address => UserStaker)) public userInfo; // cac user stake dc phan biet voi nha bang addr cua ho

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount); // stake token vao pool
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount); // lay lai so token da stake
    event Cashout(address indexed user, uint256 amount);
    event HarvestRewards(address indexed user, uint256 indexed poolId, uint256 amount); // lay reward
    event PoolCreated(uint256 poolId); // tao pool

    modifier poolValidated(uint256 _poolId) { // function validate
        require(_poolId >= 0, "MasterChefV2: PoolId can't negative");
        require(_poolId <= pools.length, "MasterChefV2: Pool less max length");
        _;
    }

    // construct tao 1 farm
    constructor(address _rewardTokenAddress, uint256 _rewardTokensPerBlock) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(POOLE_ROLE, _msgSender());

        rewardToken = IERC20(_rewardTokenAddress);
        rewardTokensPerBlock = _rewardTokensPerBlock;
    }


    function createPool(IERC20 _stakeToken, uint256 _locktime, uint256 _fee) external {
//        require(hasRole(POOLE_ROLE, _msgSender()), "MasterChefV2: Access denied");
//        require(_fee >= 0 && _fee <= MAX_FEE, "MasterChefV2: Fee not validated");
        PoolInfo memory pool;
        pool.stakeToken = _stakeToken;
        pool.accumulatedRewardsPerShare = 0; // moi tao pool, chua stake gi nen ti le = 0
        pool.duration = _locktime;
        pool.harvestFee = _fee;
        pools.push(pool);
        uint256 poolId = pools.length - 1;
        updatePoolRewards(poolId);
        emit PoolCreated(poolId);
    }

    // he so nhan = khoang cach giua block cuoi cua 1 pool den block hien tai
    function getMultiplier(uint256 lastBlock) internal view returns (uint256){
        require(block.number >= lastBlock, "MasterChefV2: block reward revert");
        uint256 blockReward;
        unchecked {
            blockReward = block.number - lastBlock;
        }
        return blockReward;
    }

    function getBalance(uint256 _poolId) external poolValidated(_poolId) view returns (uint256) {
        PoolInfo storage pool = pools[_poolId];
        uint256 balance = pool.stakeToken.balanceOf(_msgSender());
        return balance;
    }

    // lay ra ti le nhan reward tren moi don vi stake token da dua vao contract
    function getAPR(uint256 _poolId) external poolValidated(_poolId) view returns (uint256) {
        PoolInfo storage pool = pools[_poolId];
        uint256 apr = pool.accumulatedRewardsPerShare;
        return apr;
    }

    // lay ra locktime cua user chu ko phai locktime cua pool
    function getLockTime(uint256 _poolId) external poolValidated(_poolId) view returns (uint256){
        UserStaker storage user = userInfo[_poolId][msg.sender]; // lay thong tin cua user bang pool id & address cua vi
        uint256 lockTime = user.expireTime;
        return lockTime;
    }

    // lay ra locktime cua pool
    function getDurationLockTime(uint256 _poolId) external poolValidated(_poolId) view returns (uint256){
        PoolInfo storage pool = pools[_poolId];
        uint256 lockTime = pool.duration;
        return lockTime;
    }

    // lay ra tat ca cac pool dc tao tu farm nay
    function getPoolLength() external view returns (uint256) {
        return pools.length;
    }

    // lay ra harvest fee cua 1 pool
    function getPoolHarvestFee(uint256 _poolId) external poolValidated(_poolId) view returns (uint256) {
        PoolInfo storage pool = pools[_poolId];
        uint256 fee = pool.harvestFee;
        return fee;
    }

    // thay doi harvest fee so voi fee da set khi create pool
    function updatePoolHarvestFee(uint256 _poolId, uint256 _fee) external poolValidated(_poolId) {
        require(hasRole(POOLE_ROLE, _msgSender()), "MasterChefV2: Access denied");
        PoolInfo storage pool = pools[_poolId];
        pool.harvestFee = _fee;
    }

    function calcRewardHarvestFee(uint256 _reward, uint256 _fee) internal pure returns (uint256) {
        uint256 rewardFee = _reward * _fee / MAX_FEE;
        uint256 rewardsToHarvest = _reward - rewardFee;
        return rewardsToHarvest;
    }

    // tinh ra so luong reward token hien tai cua user, sau moi buoc user deposit
    function pendingReward(uint256 _poolId) internal view returns (uint256) {
        PoolInfo storage pool = pools[_poolId];
        UserStaker storage user = userInfo[_poolId][msg.sender]; // lay ra thong tin cua user doi voi pool do
        uint256 rewardsToHarvest = user.amount * pool.accumulatedRewardsPerShare / REWARDS_PRECISION - user.rewardDebt;
        return rewardsToHarvest;
    }

    // tinh ra so reward ma user co the harvest dc
    function getRewardHarvest(uint256 _poolId, address _who) external poolValidated(_poolId) view returns (uint256){
        PoolInfo storage pool = pools[_poolId]; // lay ra thong tin cua pool
        UserStaker storage user = userInfo[_poolId][_who]; // lay ra thong tin cua user
        uint256 _exactAccumulatedRewardsPerShare = pool.accumulatedRewardsPerShare;
        uint256 lpSupply = pool.stakeToken.balanceOf(address(this)); // tong so luong lp token ma farm nay co
        // case 1: luc pool moi dc tao hoac la dau deposit vao pool --> trong pool von di chua co gi, nen chi cap nhat lai last reward block
        if (lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardedBlock); // tinh khoang cach giua last block cua pool den block hien tai trong chain
            uint256 rewards = multiplier * rewardTokensPerBlock;
            // gia su da co 10 block, moi block dc 10 reward --> tong so dc tao ra la 100
            _exactAccumulatedRewardsPerShare = _exactAccumulatedRewardsPerShare + (rewards * REWARDS_PRECISION / lpSupply); // cap nhat lai ti le reward ma user se nhan dc tren moi don vi stake token da cung cap
        }
        uint256 rewardsToHarvest = user.rewards + user.amount * _exactAccumulatedRewardsPerShare / REWARDS_PRECISION - user.rewardDebt;
        if (pool.harvestFee > 0 && rewardsToHarvest > 0) {
            rewardsToHarvest = calcRewardHarvestFee(rewardsToHarvest, pool.harvestFee); // so reward con lai sau khi da tru fee
        }
        return rewardsToHarvest;
    }

    function harvestRewards(uint256 _poolId) public poolValidated(_poolId) {
        updatePoolRewards(_poolId);
        PoolInfo storage pool = pools[_poolId];
        UserStaker storage user = userInfo[_poolId][msg.sender];
        uint256 rewardsToHarvest = pendingReward(_poolId) + user.rewards;

        if (rewardsToHarvest == 0) {
            return;
        }

        if (pool.harvestFee > 0) {
            rewardsToHarvest = calcRewardHarvestFee(rewardsToHarvest, pool.harvestFee);
        }

        user.rewards = 0;
        user.rewardDebt = user.amount * pool.accumulatedRewardsPerShare / REWARDS_PRECISION;
        emit HarvestRewards(_msgSender(), _poolId, rewardsToHarvest);
        rewardToken.transfer(_msgSender(), rewardsToHarvest);
    }

    function updatePoolRewards(uint256 _poolId) private {
        PoolInfo storage pool = pools[_poolId];
        uint256 lpSupply = pool.stakeToken.balanceOf(address(this)); // tong so luong lp token ma farm nay co
        // case 1: luc pool moi dc tao hoac la dau deposit vao pool --> trong pool von di chua co gi, nen chi cap nhat lai last reward block
        if (lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardedBlock); // tinh khoang cach giua last block cua pool den block hien tai trong chain
            uint256 rewards = multiplier * rewardTokensPerBlock;
            // gia su da co 10 block, moi block dc 10 reward --> tong so dc tao ra la 100
            pool.accumulatedRewardsPerShare = pool.accumulatedRewardsPerShare + (rewards * REWARDS_PRECISION / lpSupply); // cap nhat lai ti le reward ma user se nhan dc tren moi don vi stake token da cung cap
        }
        pool.lastRewardedBlock = block.number; // last reward block dc cap nhat lai thanh thoi diem update pool
    }

    function checkBalance(uint256 _poolId, uint _amount) external poolValidated(_poolId) view returns (uint256, uint256, uint256) {
        PoolInfo storage pool = pools[_poolId];
        if (pool.stakeToken.balanceOf(_msgSender()) >= _amount) return (1, pool.stakeToken.balanceOf(_msgSender()), _amount);
        else return (0, pool.stakeToken.balanceOf(_msgSender()), _amount);
    }
    // deposit vao 1 pool
    function deposit(uint256 _poolId, uint256 _amount) external poolValidated(_poolId){
        require(_amount > 0, "MasterChefV2: Deposit amount can't be zero");

        PoolInfo storage pool = pools[_poolId];
        UserStaker storage user = userInfo[_poolId][msg.sender];

        // kiem tra xem so luong token ma user co co > so luong muon deposit vao hay ko
        require(pool.stakeToken.balanceOf(msg.sender) >= _amount, "MasterChefV2: Insufficient Balance");

        updatePoolRewards(_poolId);

        if (user.amount > 0) {
            user.rewards = pendingReward(_poolId);
        }
        if (user.amount == 0 && pool.duration > 0) {
            user.expireTime = block.timestamp + pool.duration;
        }

        ///Bat buoc phai de token approve cho farm luong amount nay truoc khi goi ham transferFrom
        pool.stakeToken.safeTransferFrom(_msgSender(), address(this), _amount); // transfer stake token tu vi cua user sang farm
        user.amount = user.amount + _amount; // tang so luong stake token cua user len
        user.rewardDebt = user.amount * pool.accumulatedRewardsPerShare / REWARDS_PRECISION; /// tai sao lai co cau lenh  :))))

        emit Deposit(_msgSender(), _poolId, _amount);
    }

    function withdraw(uint256 _poolId) external poolValidated(_poolId) {
        PoolInfo storage pool = pools[_poolId];
        UserStaker storage user = userInfo[_poolId][msg.sender];

        // amount cua user se bi block 1 thoi gian, het thoi gian do thi moi co the withdraw ra dc
        require(block.timestamp > user.expireTime, "MasterChefV2: It is not time to withdraw");

        uint256 amount = user.amount;
        require(amount > 0, "MasterChefV2: Withdraw amount can't be zero");
        // amount stake token cua farm phai con du de user rut ra
        // theo le bth thi phai du, vi la do user da deposit vao tu truoc
        // nhung neu farm chuyen het amount di dau do roi thi user se ko the rut ra dc nua --> ngan hang pha san
        require(pool.stakeToken.balanceOf(address(this)) >= amount, "MasterChefV2: Insufficient Balance");

        updatePoolRewards(_poolId);

        user.amount = 0;
        user.rewardDebt = user.amount * pool.accumulatedRewardsPerShare / REWARDS_PRECISION;
        pool.stakeToken.safeTransfer(_msgSender(), amount);

        emit Withdraw(_msgSender(), _poolId, amount);
    }

    function cashout(address _wallet, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(rewardToken.balanceOf(address(this)) >= _amount, "MasterChefV2: Insufficient Balance");
        rewardToken.transfer(_wallet, _amount);
        emit Cashout(_wallet, _amount);
    }
}
