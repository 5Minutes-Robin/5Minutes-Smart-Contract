//SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;
pragma abicoder v2;

import "./DCD.sol";

contract fiveMinutes is DCD {

    using SafeMath for uint256;
    using SafeMath32 for uint32;

    constructor() {
        _balances[msg.sender] = _totalSupply;

        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    receive() external payable {}

    //stake begins by calling the function
    //length, amount and description has to be provided
    function startDCDStake(
        uint256 _stakeAmt, 
        uint32 _stakeLength, 
        string calldata _description) 
        snapshotTrigger 
        external 
        returns (bytes16, uint32)
    {
        require(_stakeLength >= minStakingDays && _stakeLength <= maxStakingDays, "5Minutes: stake duration not in allowed range.");
        require(_stakeAmt >= minStakingAmt, "5Minutes: stake amount too small!");
        
        (Stake memory newStake,
        bytes16 _stakeID,
        uint32 _startDay) = _createDCDStake(msg.sender, _stakeAmt, _stakeLength, _description);

        stakes[msg.sender][_stakeID] = newStake;
        _increaseStakeCount(msg.sender);
        _increaseGlobals(newStake.stakedAmt, newStake.stakeShares);
        _addShares(newStake.finalDay, newStake.stakeShares);

        emit stakeStarted(
            _stakeID,
            msg.sender,
            newStake.stakedAmt,
            newStake.stakeShares,
            newStake.startDay,
            newStake.stakingDays
        );

        return (_stakeID, _startDay);
    }

    //ends stake and calculates the penalty based on the length and day number
    function endDCDStake(bytes16 _stakeID) snapshotTrigger external returns (uint256) {
        (Stake memory endedStake, uint256 penaltyAmt) = _endDCDStake(msg.sender, _stakeID);
        _decreaseGlobals(endedStake.stakedAmt, endedStake.stakeShares);
        _removeShares(endedStake.finalDay, endedStake.stakeShares);
        if (penaltyAmt > 0) {
            totalPenalties[endedStake.closeDay] = totalPenalties[endedStake.closeDay].add(penaltyAmt);
        }
        _sharesPriceUpdate(
            endedStake.stakedAmt > penaltyAmt ? 
            endedStake.stakedAmt - penaltyAmt : 0,
            endedStake.rewardAmt + scrapes[msg.sender][_stakeID],
            endedStake.stakingDays,
            endedStake.stakeShares);

        emit stakeEnded(
            _stakeID,
            msg.sender,
            endedStake.stakedAmt,
            endedStake.stakeShares,
            endedStake.rewardAmt,
            endedStake.closeDay
            );
            
        return endedStake.rewardAmt;
    }

    //allows staker to scrape interest off of stake for 5 times in the lifetime of stake
    function scrapeInterest(
        bytes16 _stakeID, 
        uint32 _scrapeDay)
         snapshotTrigger
    external 
    returns(
            uint32 scrapeDay,
            uint256 scrapeAmt,
            uint32 remDays,
            uint256 stakerPenalty)
    {
        require(stakes[msg.sender][_stakeID].isActive, "5Minutes: not an active stake");
        require(stakes[msg.sender][_stakeID].finalDay > _current5MinutesDay(), "5Minutes: stake is mature.");
        require(stakes[msg.sender][_stakeID].stakingDays >= 5, "5Minutes: stake too short.");
        require(scrapesCount[msg.sender][_stakeID] <= 5, "5Minutes: you can only scrape interest 5 times in the lifetime of a stake.");

        Stake memory _stake = stakes[msg.sender][_stakeID];

        scrapeDay = _scrapeDay > 0 ?
            _startDay(_stake).add(_scrapeDay) :
            _dayCalculation(_stake);

        scrapeDay = scrapeDay > _current5MinutesDay() ?
            _dayCalculation(_stake) :
            scrapeDay;

        require(scrapeDay.sub(_startDay(_stake)) % 5 == 0, "5Minutes: you can scrape interest every 5 days since your stake began.");

        scrapeAmt = _loopRewardAmt(
            _stake.stakeShares,
            _startDay(_stake),
            scrapeDay);
                    
        remDays = _daysLeft(_stake);

        stakerPenalty = _stakeShares(scrapeAmt, remDays, DCDStats.sharePrice);
            
        uint256 _sharesTemp = _stake.stakeShares;
                
        _stake.stakeShares = _stake.stakeShares > stakerPenalty ?
            _stake.stakeShares.sub(stakerPenalty) : 0;
                    
        _removeShares(
            _stake.finalDay,
            _sharesTemp > stakerPenalty ? stakerPenalty : _sharesTemp);
                    
        _decreaseGlobals(0, _sharesTemp > stakerPenalty ? stakerPenalty : _sharesTemp);
                
        _sharesPriceUpdate(
            _stake.stakedAmt,
            scrapeAmt,
            _stake.stakingDays,
            _stake.stakeShares);
                    
        scrapes[msg.sender][_stakeID] = scrapes[msg.sender][_stakeID].add(scrapeAmt);
        scrapesCount[msg.sender][_stakeID] += 1;
                
        _stake.scrapeDay = scrapeDay;
        stakes[msg.sender][_stakeID] = _stake;
                
        _mint(msg.sender, scrapeAmt);
                
        emit interestScraped(
            _stakeID,
            msg.sender,
            scrapeAmt,
            scrapeDay,
            stakerPenalty,
            _current5MinutesDay()
        );
    }

    //allows staker to withdraw dividends earned every day
    function withdrawDividendsProfit(uint256 amount) external {
        _withdrawDividends(payable(msg.sender), amount);
    }

    //calling the function will qualify the address and deposits the diomand hands reward
    function claimDiomandHandsReward() external {
        uint256 rewardAmt = _claimMonthlyDiomandHandsReward(msg.sender);
        string memory claimCount = new string(rewardClaimCount[msg.sender]);
        _createDCDStake(msg.sender, rewardAmt, 30, string(abi.encodePacked("Diamond Hands Reward #", claimCount)));
        
        rewardedTokens += rewardAmt;
        emit diomandHandsRewardClaimed(msg.sender, rewardAmt, _current5MinutesDay());
        emit Transfer(address(0), msg.sender, rewardAmt);
    }
    
    //allows dev to transfer any ETH sent to the contract to an external address
    function withdrawLockedETH(address payable recipient, uint256 amount) external onlyOwner() {
        require(amount <= (address(this).balance - pumperETHBalance - dividendsETHBalance),
        "5Minutes: amount should not exceed the contract balance with dividends and pumper ETH shares subtracted.");

        recipient.transfer(amount);
    }

    //allows dev to swap accumulated ETH for buyback and burn.
    //ETH dedeicated to pumper cannot be withdrawn by any functions
    function swap5MinutesPumperETHAndBurn(uint256 amount) external onlyOwner() {
        require(amount <= pumperETHBalance, "5Minutes: cannot swap more than pumper ETH balance.");

        _swapETHForTokens(amount, burnAddress);

        burntETH += amount;
        pumperETHBalance -= amount;

        emit BurntFiveMinutes(amount);
    }

    //sets the router address to apply the five minutes feature
    function setNewRouterAddrs(address _router) external onlyOwner() {
        uniswapPair = _router;
        emit newRouterAddress(uniswapPair);
    }

    function enableSwapAndLiquify(bool enable) external onlyOwner() {
        swapAndLiquifyEnabled = enable;
    }

    function manualSwap() external onlyOwner() {
        _swap(address(this), address(this));
    }

    function sharksDumpStop(bool enable) external onlyOwner() {
        stopSharkDumps = enable;
    }

    function whalesDumpStop(bool enable) external onlyOwner() {
        stopWhaleDumps = enable;
    }

    //blocks addresses listing 5minutes on centralized exchanges disrespecting the smart contract features
    function blockAddress(address outLaw, bool blocked) external onlyOwner() {
        _blockedAddrs[outLaw] = blocked;
    }

    //excludes address from tax 
    function excludeAddr(address addr, bool isExempt) external onlyOwner() {
        _excludedAddrs[addr] = isExempt;
        
        emit Excluded (addr, isExempt);
    }

    function setDevelopmentWallet(address payable addr) external onlyOwner() {
        developmentWallet = addr;
    }
}
