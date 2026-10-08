// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../AppUsageRewards.sol";

contract MockRewardsToken is IERC20RewardsToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool)
    {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Insufficient allowance");
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract AppUsageRewardsTest {
    function testFundAndPayUsageRewardsToLinkedWallets() external {
        MockRewardsToken token = new MockRewardsToken();
        AppUsageRewards rewards = new AppUsageRewards(token);
        ContributorWalletCaller firstContributor = new ContributorWalletCaller();
        address secondContributor = address(0xB0B);
        address firstPayout = address(0xCAFE);
        address reporter = address(this);
        bytes32 appId = keccak256("app");
        bytes32 batchId = keccak256("usage-batch");

        token.mint(address(this), 1001);
        token.approve(address(rewards), 1001);
        rewards.fund(1001);

        address[] memory contributors = new address[](2);
        contributors[0] = address(firstContributor);
        contributors[1] = secondContributor;
        uint16[] memory shares = new uint16[](2);
        shares[0] = 6000;
        shares[1] = 4000;
        rewards.registerApp(appId, contributors, shares);
        rewards.setUsageReporter(reporter, true);

        firstContributor.setWallet(rewards, firstPayout);
        rewards.reportUsage(appId, batchId, 1001);

        require(token.balanceOf(firstPayout) == 600, "Incorrect linked-wallet payout");
        require(token.balanceOf(secondContributor) == 401, "Incorrect remainder payout");
        require(rewards.totalFunded() == 1001, "Incorrect funded total");
        require(rewards.totalPaid() == 1001, "Incorrect paid total");
        require(rewards.usageBatchProcessed(batchId), "Batch was not recorded");
    }

    function testUnauthorizedReporterCannotPay() external {
        MockRewardsToken token = new MockRewardsToken();
        AppUsageRewards rewards = new AppUsageRewards(token);
        bytes32 appId = keccak256("app");
        address[] memory contributors = new address[](1);
        contributors[0] = address(this);
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10_000;
        rewards.registerApp(appId, contributors, shares);

        (bool success,) = address(rewards).call(
            abi.encodeCall(
                AppUsageRewards.reportUsage,
                (appId, keccak256("batch"), 1)
            )
        );
        require(!success, "Unauthorized reporter paid rewards");
    }

    function testCannotProcessUsageBatchTwice() external {
        MockRewardsToken token = new MockRewardsToken();
        AppUsageRewards rewards = new AppUsageRewards(token);
        bytes32 appId = keccak256("app");
        bytes32 batchId = keccak256("batch");
        address[] memory contributors = new address[](1);
        contributors[0] = address(this);
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10_000;
        rewards.registerApp(appId, contributors, shares);
        rewards.setUsageReporter(address(this), true);
        token.mint(address(this), 2);
        token.approve(address(rewards), 2);
        rewards.fund(2);
        rewards.reportUsage(appId, batchId, 1);

        (bool success,) = address(rewards).call(
            abi.encodeCall(
                AppUsageRewards.reportUsage,
                (appId, batchId, 1)
            )
        );
        require(!success, "Duplicate usage batch was paid");
        require(rewards.totalPaid() == 1, "Duplicate changed paid total");
    }

}

contract ContributorWalletCaller {
    function setWallet(AppUsageRewards rewards, address payoutWallet) external {
        rewards.setPayoutWallet(payoutWallet);
    }
}
