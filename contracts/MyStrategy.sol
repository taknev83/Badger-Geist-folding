// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";
import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";
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

    address public constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83; // for swap


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
        IERC20Upgradeable(want).safeApprove(
            address(LENDING_POOL),
            type(uint256).max
        );
        IERC20Upgradeable(REWARD).safeApprove(
            address(REWARDS_CONTRACT),
            type(uint256).max
        );

        // Aprove Reward so we can sell it
        IERC20Upgradeable(REWARD).safeApprove(
            address(ROUTER),
            type(uint256).max
        );
        IERC20Upgradeable(want).safeApprove(
            address(ROUTER),
            type(uint256).max
        );
        IERC20Upgradeable(WFTM).safeApprove(
            address(ROUTER),
            type(uint256).max
        );

    }
    
    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "Geist-MIM-Levered";
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = gToken;
        protectedTokens[2] = REWARD;
        return protectedTokens;
    }

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        LENDING_POOL.deposit(want, _amount, address(this), 0);
        emit Debug("_amount", _amount);
        require(IERC20Upgradeable(gToken).balanceOf(address(this)) > 0, "gToken 0 balance");
        // require(IERC20Upgradeable(gToken).balanceOf(address(this)) == _amount, 'gToken not matching');
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        uint256 toWithdraw = IERC20Upgradeable(gToken).balanceOf(address(this)); // Cache to save gas on worst case
        if(toWithdraw == 0){
            // AAVE reverts if trying to withdraw 0
            return;
        }
        // require(toWithdraw > 0, 'zero gtoken to withdraw');
        // Withdraw everything!!
        LENDING_POOL.withdraw(want, toWithdraw, address(this));
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        // Add code here to unlock / withdraw `_amount` of tokens to the withdrawer
        // If there's a loss, make sure to have the withdrawer pay the loss to avoid exploits
        // Socializing loss is always a bad idea
        uint256 maxAmount = IERC20Upgradeable(gToken).balanceOf(address(this)); // Cache to save gas on worst case
        if(_amount > maxAmount){
            _amount = maxAmount; // saves gas here
        }

        uint256 balBefore = balanceOfWant();
        LENDING_POOL.withdraw(want, _amount, address(this));
        uint256 balAfter = balanceOfWant();

        // Handle case of slippage
        return balAfter.sub(balBefore);
        // return _amount;

    }


    /// @dev Does this function require `tend` to be called?
    function _isTendable() internal override pure returns (bool) {
        return true; // Change to true if the strategy should be tended
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        address[] memory token = new address[](1);
        token[0] = gToken;

        uint256 beforeWant = IERC20Upgradeable(want).balanceOf(address(this));

        // require(IERC20Upgradeable(gToken).balanceOf(address(this)) > 0, "gToken 0 balance");
        // require(IERC20Upgradeable(gToken).balanceOf(address(this)) > 0, "gToken 0 balance");

        // Claim all rewards
        Incentive_Controller.claim(address(this), token);
        REWARDS_CONTRACT.exit();
        // (uint256 withdrawAmount, ) = REWARDS_CONTRACT.withdrawableBalance(address(this));
        // REWARDS_CONTRACT.withdraw(withdrawAmount);

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
            // uint256 afterWant = IERC20Upgradeable(want).balanceOf(address(this));

        } else {
            harvested[0] = TokenAmount(REWARD, 0);
        }

        uint256 wantHarvested = IERC20Upgradeable(want).balanceOf(address(this)).sub(beforeWant);

        // Report profit for the want increase (NOTE: We are not getting perf fee on AAVE APY with this code)
        _reportToVault(wantHarvested);

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
        return IERC20Upgradeable(gToken).balanceOf(address(this));
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
