// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20RewardsToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract AppUsageRewards {
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_CONTRIBUTORS_PER_APP = 20;

    struct AppContributor {
        address account;
        uint16 shareBps;
    }

    IERC20RewardsToken public immutable rewardToken;
    address public owner;
    uint256 public totalFunded;
    uint256 public totalPaid;
    uint256 private _entered = 1;

    mapping(address => bool) public usageReporters;
    mapping(address => address) public payoutWallets;
    mapping(bytes32 => AppContributor[]) private _appContributors;
    mapping(bytes32 => bool) public appRegistered;
    mapping(bytes32 => bool) public usageBatchProcessed;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event UsageReporterUpdated(address indexed reporter, bool authorized);
    event PayoutWalletUpdated(address indexed contributor, address indexed payoutWallet);
    event AppRegistered(bytes32 indexed appId, uint256 contributorCount);
    event FundsAdded(address indexed funder, uint256 amount);
    event UsageRewardPaid(
        bytes32 indexed appId,
        bytes32 indexed batchId,
        address indexed reporter,
        uint256 amount
    );
    event ContributorPaid(
        bytes32 indexed appId,
        bytes32 indexed batchId,
        address indexed contributor,
        address payoutWallet,
        uint256 amount
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(_entered == 1, "Reentrant call");
        _entered = 2;
        _;
        _entered = 1;
    }

    modifier onlyReporter() {
        require(usageReporters[msg.sender], "Not authorized reporter");
        _;
    }

    constructor(IERC20RewardsToken token) {
        require(address(token) != address(0), "Token required");
        rewardToken = token;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Owner required");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setUsageReporter(address reporter, bool authorized) external onlyOwner {
        require(reporter != address(0), "Reporter required");
        usageReporters[reporter] = authorized;
        emit UsageReporterUpdated(reporter, authorized);
    }

    function setPayoutWallet(address payoutWallet) external {
        require(payoutWallet != address(0), "Payout wallet required");
        require(payoutWallet != address(this), "Cannot pay contract");
        payoutWallets[msg.sender] = payoutWallet;
        emit PayoutWalletUpdated(msg.sender, payoutWallet);
    }

    function registerApp(
        bytes32 appId,
        address[] calldata contributors,
        uint16[] calldata sharesBps
    ) external onlyOwner {
        require(appId != bytes32(0), "App ID required");
        require(!appRegistered[appId], "App already registered");
        require(contributors.length > 0, "Contributors required");
        require(contributors.length <= MAX_CONTRIBUTORS_PER_APP, "Too many contributors");
        require(contributors.length == sharesBps.length, "Length mismatch");

        uint256 totalShares;
        for (uint256 i = 0; i < contributors.length; i++) {
            require(contributors[i] != address(0), "Contributor required");
            require(sharesBps[i] > 0, "Share required");
            for (uint256 j = 0; j < i; j++) {
                require(contributors[j] != contributors[i], "Duplicate contributor");
            }
            totalShares += sharesBps[i];
            _appContributors[appId].push(
                AppContributor({account: contributors[i], shareBps: sharesBps[i]})
            );
        }

        require(totalShares == BASIS_POINTS, "Shares must total 10000");
        appRegistered[appId] = true;
        emit AppRegistered(appId, contributors.length);
    }

    function getAppContributors(bytes32 appId)
        external
        view
        returns (AppContributor[] memory)
    {
        return _appContributors[appId];
    }

    function fund(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount required");
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        _safeTransferFrom(msg.sender, amount);
        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        require(balanceAfter - balanceBefore == amount, "Unsupported transfer amount");

        totalFunded += amount;
        emit FundsAdded(msg.sender, amount);
    }

    function reportUsage(bytes32 appId, bytes32 batchId, uint256 rewardAmount)
        external
        onlyReporter
        nonReentrant
    {
        require(appRegistered[appId], "App not registered");
        require(batchId != bytes32(0), "Batch ID required");
        require(!usageBatchProcessed[batchId], "Batch already processed");
        require(rewardAmount > 0, "Reward required");
        require(rewardAmount <= totalFunded - totalPaid, "Insufficient funded rewards");

        usageBatchProcessed[batchId] = true;
        totalPaid += rewardAmount;

        AppContributor[] storage contributors = _appContributors[appId];
        uint256 remaining = rewardAmount;
        for (uint256 i = 0; i < contributors.length; i++) {
            AppContributor storage contributor = contributors[i];
            uint256 amount = i == contributors.length - 1
                ? remaining
                : _shareOf(rewardAmount, contributor.shareBps);
            remaining -= amount;

            if (amount > 0) {
                address payoutWallet = payoutWallets[contributor.account];
                if (payoutWallet == address(0)) payoutWallet = contributor.account;
                _safeTransfer(payoutWallet, amount);
                emit ContributorPaid(
                    appId,
                    batchId,
                    contributor.account,
                    payoutWallet,
                    amount
                );
            }
        }

        emit UsageRewardPaid(appId, batchId, msg.sender, rewardAmount);
    }

    function _shareOf(uint256 amount, uint16 shareBps) private pure returns (uint256) {
        return (amount / BASIS_POINTS) * shareBps
            + ((amount % BASIS_POINTS) * shareBps) / BASIS_POINTS;
    }

    function _safeTransfer(address recipient, uint256 amount) private {
        (bool success, bytes memory result) = address(rewardToken).call(
            abi.encodeCall(IERC20RewardsToken.transfer, (recipient, amount))
        );
        require(success && (result.length == 0 || abi.decode(result, (bool))), "Token transfer failed");
    }

    function _safeTransferFrom(address sender, uint256 amount) private {
        (bool success, bytes memory result) = address(rewardToken).call(
            abi.encodeCall(IERC20RewardsToken.transferFrom, (sender, address(this), amount))
        );
        require(success && (result.length == 0 || abi.decode(result, (bool))), "Token transfer failed");
    }
}
