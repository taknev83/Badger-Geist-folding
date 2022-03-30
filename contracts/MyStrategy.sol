// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import {BaseStrategy} from "../interfaces/badger/IBaseStrategy.sol";
import {ILendingPool} from "../interfaces/geist/ILendingPool.sol";
import {IRewardsContract} from "../interfaces/geist/IRewardsContract.sol";
import {IChefIncentivesController} from "../interfaces/geist/IChefIncentivesController.sol";
import {IRouter} from "../interfaces/spooky/IRouter.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    event Debug(string name, uint256 value);
    // address public want; // Inherited from BaseStrategy
    // address public lpComponent; // Token that represents ownership in a pool, not always used
    // address public reward; // Token we farm

    address constant public REWARD = 0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d;    // Geist token

    // Representing balance of deposits
    address constant public gToken = 0xc664Fc7b8487a3E10824Cda768c1d239F2403bBe;    // Geist MIM

    // Representing balance of borrowing
    address constant public variableDebtgMIM = 0xe6f5b2d4DE014d8fa4c45b744921fFDf13f15D4a;  // Geist variable debt token

    // Spooky Router
    IRouter constant public ROUTER = IRouter(0xF491e7B69E4244ad4002BC14e878a34207E38c29);

    ILendingPool constant public LENDING_POOL = ILendingPool(0x9FAD24f572045c7869117160A571B2e50b10d068);
    IRewardsContract constant public REWARDS_CONTRACT = IRewardsContract(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);   //Geist staking contract
    IChefIncentivesController constant Incentive_Controller = IChefIncentivesController(0x297FddC5c33Ef988dd03bd13e162aE084ea1fE57);

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address[1] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);
        /// @dev Add config here
        want = _wantConfig[0];
        
        // Approve want for earning interest
        IERC20Upgradeable(want).safeApprove(address(LENDING_POOL), type(uint256).max);
        IERC20Upgradeable(REWARD).safeApprove(address(REWARDS_CONTRACT), type(uint256).max);

        // Approve Reward so we can sell it
        IERC20Upgradeable(REWARD).safeApprove(address(ROUTER), type(uint256).max);
        IERC20Upgradeable(want).safeApprove(address(ROUTER), type(uint256).max);
    }
    
    /// Number of loops
    uint256 n = 2;

    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "Geist-MIM-Levered";
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](4);
        protectedTokens[0] = want;
        protectedTokens[1] = gToken;
        protectedTokens[2] = REWARD;
        protectedTokens[3] = variableDebtgMIM;
        return protectedTokens;
    }

    /// @dev Deposit `_amount` of want, investing it to earn yield
    /// @notice 
    function _deposit(uint256 _amount) internal override {
        uint256 depositAmount = _amount * 100 / 100;
        LENDING_POOL.deposit(want, depositAmount, address(this), 0);
        emit Debug("First Deposit", depositAmount);
        require(IERC20Upgradeable(gToken).balanceOf(address(this)) > 0, "gToken 0 balance");
        for(uint i = 0; i < n; i++) {
            depositAmount = _borrowAndSupply(depositAmount);
        }
    }

    /// @dev Borrow & deposit function
    function _borrowAndSupply(uint256 depositAmount) internal returns (uint256) {
        uint256 toBorrow = 70;  // 70% of the deposit amount
        uint256 total = 100;
        uint256 borrowAmount = depositAmount * toBorrow / total;
        emit Debug("Borrow Amount", borrowAmount);
        LENDING_POOL.borrow(want, borrowAmount, 2, 0, address(this));  
        emit Debug("Borrow {i}", borrowAmount);         
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        LENDING_POOL.deposit(want, wantBalance, address(this), 0);  
        emit Debug("Deposit {i + 1}", wantBalance);
        return wantBalance;     
    }
    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        uint256 toWithdraw = IERC20Upgradeable(gToken).balanceOf(address(this)); // Cache to save gas on worst case
        if(toWithdraw == 0){
            // AAVE reverts if trying to withdraw 0
            return;
        }
        uint256 borrowToken = IERC20Upgradeable(variableDebtgMIM).balanceOf(address(this));
        do {
            uint256 safeWithdrawBalance = _getSafeWithdrawBalance();
            LENDING_POOL.withdraw(want, safeWithdrawBalance, address(this));
            uint256 withdrawnBalance = IERC20Upgradeable(want).balanceOf(address(this));
            LENDING_POOL.repay(want, withdrawnBalance, 2, address(this));
            borrowToken = IERC20Upgradeable(variableDebtgMIM).balanceOf(address(this));
        } while (borrowToken > 0);

        uint256 withdrawableBalance = IERC20Upgradeable(gToken).balanceOf(address(this)); // Cache to save gas on worst case
        // Withdraw leftovers!!
        LENDING_POOL.withdraw(want, withdrawableBalance, address(this));
    }

    /// @dev uitility function to get safe withdraw balance
    function _getSafeWithdrawBalance() internal returns (uint256) {
        uint256 borrowBalance = IERC20Upgradeable(variableDebtgMIM).balanceOf(address(this));
        uint256 depositBalance = IERC20Upgradeable(gToken).balanceOf(address(this));
        uint256 withdrawBalance = depositBalance - borrowBalance;
        uint256 safeWithdrawBalance = withdrawBalance * 60 / 100;   // withdrawing 60% 
        return safeWithdrawBalance;
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        // Add code here to unlock / withdraw `_amount` of tokens to the withdrawer
        // If there's a loss, make sure to have the withdrawer pay the loss to avoid exploits
        // Socializing loss is always a bad idea

        uint256 balBefore = balanceOfWant();
        _withdrawAll();
        uint256 postwithdraw = IERC20Upgradeable(want).balanceOf(address(this));
        uint256 toDeposit = postwithdraw - _amount;
        emit Debug("Post Withdraw Amount", postwithdraw);
        emit Debug("Withdraw requested amount", _amount);
        emit Debug("Deposit Amount after withdrawAll", toDeposit);
        if (toDeposit > 0) {
            _deposit(toDeposit);        
        }
        uint256 balAfter = balanceOfWant();
        // Handle case of slippage
        return balAfter.sub(balBefore);
    }

    /// @dev Does this function require `tend` to be called?
    function _isTendable() internal override pure returns (bool) {
        return true; // Change to true if the strategy should be tended
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        address[] memory token = new address[](1);
        token[0] = gToken;

        uint256 beforeWant = IERC20Upgradeable(want).balanceOf(address(this));

        // Claim all rewards
        Incentive_Controller.claim(address(this), token);
        REWARDS_CONTRACT.exit();

        uint256 allRewards = IERC20Upgradeable(REWARD).balanceOf(address(this));
        require(allRewards > 0, '0 Geist');

        // Sell for more want
        harvested = new TokenAmount[](1);
        harvested[0] = TokenAmount(REWARD, 0);
        
        if (allRewards > 0) {
            harvested[0] = TokenAmount(REWARD, allRewards);

            address[] memory path = new address[](2);
            path[0] = REWARD;
            path[1] = want;

            IRouter(ROUTER).swapExactTokensForTokens(allRewards, 0, path, address(this), block.timestamp);

        } else {
            harvested[0] = TokenAmount(REWARD, 0);
        }

        uint256 wantHarvested = IERC20Upgradeable(want).balanceOf(address(this)).sub(beforeWant);

        // Report profit for the want increase (NOTE: We are not getting perf fee on AAVE APY with this code)
        _reportToVault(wantHarvested);
        emit Debug('WantHarvested', wantHarvested);

    }

    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended){
        uint256 balanceToTend = balanceOfWant();
        tended = new TokenAmount[](1);
        if(balanceToTend > 0) {
            _deposit(balanceToTend);
            tended[0] = TokenAmount(want, balanceToTend);
        } else {
            tended[0] = TokenAmount(want, 0);
        }
        return tended;
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        // Change this to return the amount of want invested in another protocol
        uint256 borrowBalance = IERC20Upgradeable(variableDebtgMIM).balanceOf(address(this));
        uint256 depositBalance = IERC20Upgradeable(gToken).balanceOf(address(this));
        uint256 withdrawBalance = depositBalance - borrowBalance;
        return withdrawBalance;
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        address[] memory tokens = new address[](1);
        tokens[0] = gToken;

        (uint256 accruedRewards, ) = REWARDS_CONTRACT.withdrawableBalance(address(this));
        rewards = new TokenAmount[](1);
        rewards[0] = TokenAmount(REWARD, accruedRewards); 
        return rewards;

    }
}
