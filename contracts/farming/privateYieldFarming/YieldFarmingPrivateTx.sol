// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {MerkleTree} from "./MerkleTree.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// dung snarkjs de tu generate
interface IVerifier {
    function verifyProof(uint256[2] calldata _pA, uint256[2][2] calldata _pB, uint256[2] calldata _pC, uint256[3] calldata _pubSignals)
    external returns (bool);
}

contract PrivateYieldFarming is MerkleTree {
    IVerifier public immutable verifier = IVerifier(0xd36B8c67C355670D4dC8AC038De1635f5C60eE47); /// must enter address of this verifier;
    ///dung de verify commitment khi withdraw

    ///height = 32 // level 0->31
    mapping (uint256 => bool) public nullifierHashList;
    mapping (uint256 => bool) public commitmentList;

    IERC20 public stakeToken; // token dc dung de stake cho pool nay
    IERC20 public rewardToken; // reward cho pool nay

    uint256 public lastRewardedBlock;
    uint256 public accumulatedRewardsPerShare; // ti le nhan reward tinh tren 1 don vi stake token da cung cap
    uint256 private rewardTokensPerBlock; // so token reward tren moi block
    uint256 private constant REWARDS_PRECISION = 1e12;
    uint256 public denomination; // luong token nguoi dung duoc stake khi deposit vao contract

    struct UserStake {
        uint256 rewardDebt;
    }
    mapping (uint256 => UserStake) private userList;

    constructor (IERC20 _stakeToken, IERC20 _rewardTokenAddress, uint256 _denomination, uint256 _rewardTokensPerBlock)
    MerkleTree() {
        require(_denomination > 0, "denomination must be greater than 0");
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardTokenAddress);
        accumulatedRewardsPerShare = 0;
        rewardTokensPerBlock = _rewardTokensPerBlock;
        denomination = _denomination;

        updateRewards();
    }

    function updateRewards () private {
        uint256 totalStakeSupply = stakeToken.balanceOf(address(this)); //tong so luong staketoken da duoc supply vao smart contract nay;
        if (totalStakeSupply != 0) {
            uint256 multiplier = getMultiplier(lastRewardedBlock); // tinh khoang cach giua last block cua pool den block hien tai trong chain
            // gia su da co 10 block, moi block dc 10 reward --> tong so dc tao ra la 100
            uint256 rewards = multiplier * rewardTokensPerBlock;
            // cap nhat lai ti le reward ma user se nhan dc tren moi don vi stake token da cung cap
            accumulatedRewardsPerShare = accumulatedRewardsPerShare + (rewards * REWARDS_PRECISION / totalStakeSupply);
        }
        lastRewardedBlock = block.number; // last reward block dc cap nhat lai thanh thoi diem update pool
    }

    function getMultiplier(uint256 lastBlock) internal view returns (uint256){
        require(block.number >= lastBlock, "MasterChefV2: block reward revert");
        uint256 blockReward;
        blockReward = block.number - lastBlock;
        return blockReward;
    }

    event Deposit(uint256 commitment, uint256 nextIndex);
    function deposit(uint256 _commitment, uint256 _nullifierHash) external payable{
        require(!commitmentList[_commitment], 'please choice unique commitment correspond with your secret and nullifier');
        require(!nullifierHashList[_nullifierHash], 'this nullifierhash has been chosen');

        //insert commitment vao merkletree neu insert duoc thi den buoc tiep theo
        (uint256 nextIndex) = insert(_commitment);

        require(msg.value == 0, "ETH value is supposed to be 0 for ERC20 instance");
        require(stakeToken.balanceOf(msg.sender) >= denomination, "insufficient balance");

        updateRewards(); ///can update lai reward sau moi lan deposit de dam bao tinh cong bang cho cac user deposit truoc
        ///can thiet phai approve luong stake token nay truoc khi chuyen cho smart contract;
        stakeToken.transferFrom(msg.sender, address(this), denomination);
        userList[_nullifierHash].rewardDebt = denomination * accumulatedRewardsPerShare / REWARDS_PRECISION;

        commitmentList[_commitment] = true;
        emit Deposit(_commitment, nextIndex);
    }

    event Withdraw(address to, uint256 nullifierHash);
    function withdraw (
        uint256[2] calldata _pA, uint256[2][2] calldata _pB, uint256[2] calldata _pC,
        uint256 _root,
        uint256 _nullifierHash,
        address _recipient
    ) external payable{
        //kiem tra xem tien da duoc rut chua
        //neu duoc rut roi thi harvest se khong con duoc dung nua.
        require(!nullifierHashList[_nullifierHash], "the node has been already spent");

        /// Kiem tra xem _root cua user co phải valid khong
        /// can co doan verifier cai commitment va nullifier da roi moi rut duoc
        require(isRoot[_root], "cannot find your merkle root");
        require(
            verifier.verifyProof(
                _pA, _pB, _pC,
                [uint256(_root), uint256(_nullifierHash), uint256(uint160(_recipient))]
            ),
            "invalid withdraw proof"
        );

        nullifierHashList[_nullifierHash] = true;

        ///tra tien lai
        updateRewards();
        UserStake storage user = userList[_nullifierHash];
        uint256 rewardsToHarvest = denomination * accumulatedRewardsPerShare / REWARDS_PRECISION - user.rewardDebt;
        if (rewardsToHarvest != 0) {
            rewardToken.transfer(_recipient, rewardsToHarvest);
        }

        emit Withdraw(_recipient, _nullifierHash);
        ///tra tien goc
        stakeToken.transfer(_recipient, denomination);
    }
}
