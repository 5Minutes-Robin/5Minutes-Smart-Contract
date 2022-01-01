    //SPDX-License-Identifier: Apache-2.0
    pragma solidity ^0.7.6;
    pragma abicoder v2;

    import "./Libraries.sol";
    import "./ERC20.sol";
    import "./Uniswap.sol";

    contract Events {
        event stakeStarted(
            bytes16 indexed stakeID,
            address indexed stakerAddr,
            uint256 stakeAmt,
            uint256 stakeShares,
            uint32 startDay,
            uint32 stakeLength
            );

        event stakeEnded(
            bytes16 indexed stakeID,
            address indexed stakerAddr,
            uint256 stakeAmt,
            uint256 stakeShares,
            uint256 penaltyAmt,
            uint32 endDay
            );
    
        event interestScraped(
            bytes16 indexed stakeID,
            address indexed stakerAddr,
            uint256 scrapeAmt,
            uint32 scrapeDay,
            uint256 stakerPenalty,
            uint32 fiveMinutesDay
            );
        
        event tokensClaimed(
            address indexed claimerAddr,
            uint256 claimAmt,
            uint32 fiveMinutesDay
            );
    
        event newGlobals(
            uint256 totalShares,
            uint256 totalStakers,
            uint256 totalStaked,
            uint256 totalClaimed,
            uint256 shareRate,
            uint32 fiveMinutesDay
            );
            
        event newSharePrice(
            uint256 currentSharePrice,
            uint256 oldSharePrice,
            uint32 fiveMinutesDay
            );
            
        event diomandHandsRewardClaimed(
            address diomandHandAddr,
            uint256 rewardAmt,
            uint256 fiveMinutesDay
            );
            
        event dividendsProfitWithdrawn(address sender, uint256 amount);
        event dividendsPofitDistributed(uint256 amount);
    }
    
    abstract contract Global is Events, Ownable, IERC20, IERC20Metadata {
    
        using SafeMath for uint256;
    
        struct Globals {
            uint256 totalStakedAmt;
            uint256 totalStakers;
            uint256 totalShares;
            uint256 totalClaimed;
            uint256 sharePrice;
            uint32 fiveMinutesDay;
        }
        
        Globals public DCDStats;
        
        constructor() {
            DCDStats.sharePrice = 1E7; //= 0.01 ETH
        }
    
        function _increaseClaimedAmt(uint256 _claimedTokens) internal {
            DCDStats.totalClaimed = DCDStats.totalClaimed.add(_claimedTokens);
        }
    
        function _increaseGlobals(uint256 _staked, uint256 _shares) internal {
            DCDStats.totalStakedAmt = DCDStats.totalStakedAmt.add(_staked);
            DCDStats.totalShares = DCDStats.totalShares.add(_shares);
            _emitStakeStats();
        }
    
        function _decreaseGlobals(uint256 _staked, uint256 _shares) internal {
            DCDStats.totalStakedAmt = 
            DCDStats.totalStakedAmt > _staked ? 
            DCDStats.totalStakedAmt - _staked : 0;
            
            DCDStats.totalShares =
            DCDStats.totalShares > _shares ?
            DCDStats.totalShares - _shares : 0;
            
            _emitStakeStats();
        }    
        
        function _emitStakeStats() private {
            emit newGlobals (
                DCDStats.totalShares,
                DCDStats.totalStakers,
                DCDStats.totalStakedAmt,
                DCDStats.totalClaimed,
                DCDStats.sharePrice,
                DCDStats.fiveMinutesDay
            );
        }
    }
    
    abstract contract Declaration is Global {
        uint256 constant secsInDay = 86400 seconds;
        uint256 constant secsInHour = 3600 seconds;
        uint256 constant bonusPrecision = 1E5;
        uint256 constant sharesPrecision = 1E6;
        uint256 constant rewardPrecision = 1E10;
        uint256 constant minutesPer5Minute = 1E9;
        uint256 constant precisionRate = 1E9;
        uint256 constant distributionMultiplier = 2**64;
        uint256 initialSharePrice = 1E7;
    
        uint256 launchTime;
        uint256 buyTimeStamp;
    
        uint32 constant inflationRate = 105000;
        uint32 constant inflationDivisor = 10000;
        uint32 constant minStakingDays = 1;
        uint32 constant maxStakingDays = 1825; //= 5 years
        uint32 constant minStakingAmt = 100000; //= 0.0001 5Minutes tokens
    
        constructor () {
            launchTime = 1632967200;
            buyTimeStamp = launchTime + 3295;
            developmentWallet = msg.sender;
        }
    
        struct Stake {
            uint256 stakeShares;
            uint256 stakedAmt;
            uint256 rewardAmt;
            uint256 penaltyAmt;
            uint32 startDay;
            uint32 stakingDays;
            uint32 finalDay;
            uint32 closeDay;
            uint32 scrapeDay;
            bool isActive;
            string details;
        }
    
        mapping(address => uint256) public stakeCount;
        mapping(address => uint256) public total5MinutesActiveStakes;
        mapping(address => mapping(bytes16 => Stake)) public stakes;
        mapping(address => mapping(bytes16 => uint256)) public scrapes;
        mapping(address => mapping(bytes16 => uint8)) public scrapesCount;
        mapping(address => uint256) public walletBuyTimeStamp;
        mapping(address => uint256) public walletBuyAmt;
        mapping(address => uint256) public walletTaxedAmt;
        mapping(address => uint32) public monthlyRewardClaimDay;
        mapping(address => uint256) public rewardedTokensToHolder;
        mapping(address => uint8) public rewardClaimCount;
        mapping(uint32 => uint256) public scheduledToEnd;
        mapping(uint32 => uint256) public totalPenalties;
        mapping(address => uint256) public dividendPayouts;
        mapping(address => uint256) public totalDividendsWithdrawn;
    
        mapping(address => uint256) internal _balances;
        mapping (address => bool) internal _excludedAddrs;
        mapping(address => mapping(address => uint256)) internal _allowances;
        mapping (address => uint256) public sellRecord;
        mapping(uint32 => Snapshot) public snapshots;
    
        address public uniswapPair;
        address payable public developmentWallet;
        address public immutable burnAddress =
        0x000000000000000000000000000000000000dEaD;
    
        uint8 public sellTaxPercent = 12;
        uint8 public buyTaxPercent = 8;
        uint8 public transferTaxPercent = 5;
        uint256 public minSwapAmt = 500*10**9;
        uint256 public pumperETHBalance;
    
        uint256 public burntTokens;
        uint256 public burntETH;
    
        uint256 public profitPerDividendShare;
        uint256 public totalDistributions;
        uint256 internal emptyDividendTokens;
        uint256 public dividendsETHBalance;
        uint256 public totalDividendsPaid;
    
        uint256 public rewardedTokens;
    
        bool public stopSharkDumps;
        bool public stopWhaleDumps;
        bool public disableSell;
        bool public swapAndLiquifyEnabled;
    
        struct Snapshot {
            uint256 totalShares;
            uint256 inflationAmt;
            uint256 scheduledToEnd;
        }
    }
    
    abstract contract fiveMinutesTiming is Declaration {
    
        function currrent5MinutesDay() public view returns (uint32) {
            return block.timestamp >= launchTime ? _current5MinutesDay() : 0;
        }
    
        function current5MinutesHour() public view returns (uint32) {
            return block.timestamp >= launchTime ? _current5MinutesHour() : 0;
        }
    
        function walletBuyHour(address buyer) public view returns (uint32) {
            return walletBuyTimeStamp[buyer] > 0 
            ? uint32((walletBuyTimeStamp[buyer] - launchTime) / secsInHour) : 0;
        }
    
        function _current5MinutesDay() internal view returns (uint32) {
            return _5MinutesDayTimeStamp(block.timestamp);
        }
    
        function _current5MinutesHour() internal view returns (uint32) {
            return _5MinutesHourTimeStamp(block.timestamp);
        }
    
        function _next5MinutesDay() internal view returns (uint32) {
            return _current5MinutesDay() + 1;
        }
    
        function _previous5MinutesDay() internal view returns (uint32) {
            return _current5MinutesDay() - 1;
        }
        
        function _5MinutesDayTimeStamp(uint256 _timestamp) internal view returns (uint32) {
            return uint32((_timestamp - launchTime) / secsInDay);
        }
        
        function _5MinutesHourTimeStamp(uint256 timestamp_) internal view returns (uint32) {
            return uint32((timestamp_ - launchTime) / secsInHour);
        }
    }
    
    abstract contract ERC20 is fiveMinutesTiming {
        
        string internal _name = "5Minutes";
        string internal _symbol = "5Min";
        
        uint8 internal _decimals = 9;
        uint256 internal _totalSupply = (5*10**9) * 10 ** _decimals;
        
        IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address public uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        
        function name() public view virtual override returns (string memory) {
            return _name;
        }
    
        function symbol() public view virtual override returns (string memory) {
            return _symbol;
        }
    
        function decimals() public view virtual override returns (uint8) {
            return _decimals;
        }
    
        function totalSupply() public view virtual override returns (uint256) {
            return _totalSupply;
        }
    
        function balanceOf(address account) public view virtual override returns (uint256) {
            return _balances[account];
        }
        
        function updateFiveMinutesTiming() public returns (bool) {
            uint256 _currentTime = block.timestamp;
            uint256 _multiplier = _current5MinutesHour();
            uint256 buyTime = buyTimeStamp + (_multiplier * secsInHour);
            uint256 hourTimeStamp = launchTime + (_multiplier * secsInHour);
            
            if(_currentTime <= buyTime && _currentTime > hourTimeStamp) {
                disableSell = true;
            } else {
                disableSell = false;
            }
    
            return disableSell;
        }

        function isDiamondHand(address holder) public view returns (bool) {
            return walletBuyTimeStamp[holder] > 0 ?
            (_current5MinutesHour() - walletBuyHour(holder)) >= 1440 : false;
        }

        //returns the amount of ETH dividends accumulated for a staker 
        function dividendsOfStaker(address staker) public view returns (uint256) {
            uint256 divPayout = profitPerDividendShare * total5MinutesActiveStakes[staker];
            require(divPayout >= dividendPayouts[staker], "5Minutes: dividend calculation overflow.");
    
            return (divPayout - dividendPayouts[staker]) / distributionMultiplier;
        }
        
        //returns the amount of ETH sent to the contract from an external address
        function lockedETHBalance() public view returns(uint256) {
            return address(this).balance - pumperETHBalance - dividendsETHBalance;
        }
    
        function _mint(address account, uint256 amount) internal virtual {
            require(account != address(0), "ERC20: mint to the zero address");
    
            _beforeTokenTransfer(address(0), account, amount);
    
            _totalSupply += amount;
            _balances[account] += amount;
            emit Transfer(address(0), account, amount);
    
            _afterTokenTransfer(address(0), account, amount);
        }
    
        function _burn(address account, uint256 amount) internal virtual {
            require(account != address(0), "ERC20: burn from the zero address");
    
            _beforeTokenTransfer(account, address(0), amount);
    
            uint256 accountBalance = _balances[account];
            require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
            _balances[account] -= amount;
            _totalSupply -= amount;
    
            emit Transfer(account, address(0), amount);
    
            _afterTokenTransfer(account, address(0), amount);
        }

        function _approve(
            address owner,
            address spender,
            uint256 amount
        ) internal virtual {
            require(owner != address(0), "ERC20: approve from the zero address");
            require(spender != address(0), "ERC20: approve to the zero address");
    
            _allowances[owner][spender] = amount;
            emit Approval(owner, spender, amount);
        }

        function _beforeTokenTransfer(
            address from,
            address to,
            uint256 amount
        ) internal virtual {}

        function _afterTokenTransfer(
            address from,
            address to,
            uint256 amount
        ) internal virtual {}

        function _transfer(
            address sender,
            address recipient,
            uint256 amount
        ) internal virtual {
            uint256 _currentTime = block.timestamp;
            uint256 senderBalance = _balances[sender];
            uint256 sharkLimit = totalSupply() / (10**3);
            uint256 whaleLimit = (totalSupply() * 5) / (10**3);
            disableSell = updateFiveMinutesTiming();
    
            require(sender != address(0), "ERC20: transfer from the zero address");
            require(recipient != address(0), "ERC20: transfer to the zero address");
            require(amount > 0, "Transfer amount must be greater than zero.");
            
            //This allows selling only in the last 5 minutes of each UTC hour
            if (disableSell) {
                require(recipient != uniswapPair, "5Minutes: it's pump time. Buy more!");
            }
            //Records the timestamp at which a wallet first buys
            if(_current5MinutesDay() <= 365 && sender == address(uniswapV2Pair)) {
                walletBuyTimeStamp[recipient] =  walletBuyTimeStamp[recipient] > 0 ?
                    walletBuyTimeStamp[recipient] :
                    _currentTime;
                walletBuyAmt[recipient] += amount;
            }
            //Resets the timestamp to default value if a wallet sells
            if(_current5MinutesDay() <= 365 && recipient == address(uniswapV2Pair)) {
                walletBuyTimeStamp[sender] = 0;
                walletBuyAmt[sender] -= amount;
            }
            //Keeps record of sell transactions 
            if(recipient == address(uniswapV2Pair)) {
                sellRecord[sender] = _currentTime;
            }

            _beforeTokenTransfer(sender, recipient, amount);

            //This stops large holders from dumping the price at once!
            if((stopSharkDumps || stopWhaleDumps) && !(sender == address(this))) {
    
                if(recipient == address(uniswapV2Pair)) {

                    if (stopSharkDumps && senderBalance >= sharkLimit && senderBalance < whaleLimit) {
                        require(amount <= senderBalance / (3), "5Minutes: max sell for a shark is 33% per 24 hours");
                        require(_currentTime - sellRecord[sender] > 1 days, "5Minutes: you need to wait for 24 hours before selling again");
                    }
     
                    else if (stopWhaleDumps && senderBalance >= whaleLimit) {
                        require(amount <= senderBalance / (5), "5Minutes: max sell for a whale is 20% per 24 hours");
                        require(_currentTime - sellRecord[sender] > 1 days, "5Minutes: you have to wait for 24 hours before selling again");
                    }
                }
            }
            if (_excludedAddrs[sender])
                {
                    _taxlessTransfer(sender, recipient, amount);
                }
            else {
                    _taxedTransfer(sender, recipient, amount);
            }
            emit Transfer(sender, recipient, amount);
    
            _afterTokenTransfer(sender, recipient, amount);
        }
    
        function _taxedTransfer(address sender, address recipient, uint256 amount) private {
            _swap(sender, recipient);
            uint256 sellTax = (amount * sellTaxPercent) / 100;
            uint256 buyTax = (amount * buyTaxPercent) / 100;
            uint256 transferTax = (amount * transferTaxPercent) / 100;
            //8% fee if the wallet is buying
            if (sender == address(uniswapV2Pair)) {
                _balances[address(this)] += buyTax;
                _balances[sender] -= amount;
                _balances[recipient] += amount - buyTax;

                walletTaxedAmt[recipient] += amount;
            }
            //12% fee if the wallet is selling
            else if (recipient == address(uniswapV2Pair)) {
                _balances[address(this)] += sellTax;
                _balances[sender] -= amount;
                _balances[recipient] += amount - sellTax;

                walletTaxedAmt[recipient] -= amount;
            }
            //5% fee for all other transfers
            else {
                _balances[address(this)] += transferTax;
                _balances[sender] -= amount;
                _balances[recipient] += amount - transferTax;
            }
        }
    
        function _taxlessTransfer(address sender, address recipient, uint256 amount) private {
            _balances[sender] -= amount;
            _balances[recipient] += amount;
        }
    
        function _swap(address sender, address recipient) private {
            uint256 contractBalance = _balances[address(this)];
    
            bool distributeTax = contractBalance >= minSwapAmt;
            
            /** 20% total tax for a complete buy and sell transactions per address (8% => buy, 12% => sell, 5% => all other transfers)
             * 10% liquidated and added to pumping burner balance for manual buyback and burn
             * 6% liquidated and distributed among CD stakers
             * 4% liquidated and trasnferred to development wallet
            */
            if (
                swapAndLiquifyEnabled &&
                distributeTax &&
                !(sender == address(uniswapV2Pair)) &&
                !(sender == address(this) && recipient == address(uniswapV2Pair))
                )
                {
                    uint256 pumperShare =  (5 * contractBalance) / 10;
                    uint256 dividendsShare = (3 * contractBalance) / 10;
                    uint256 developmentShare = (2 * contractBalance) / 10;

                    uint256 swappedTax = dividendsShare + developmentShare + pumperShare;

                    burntTokens += pumperShare;
    
                    _swapTokensForETH(swappedTax);
                    
                    uint256 ETHBalance = address(this).balance - (pumperETHBalance + dividendsETHBalance);

                    uint256 dividendsETHShare = (ETHBalance*3333) / 10000;
                    uint256 developmentETHShare = (ETHBalance*2222) / 10000;
                    uint256 pumperETHShare = (ETHBalance*4445) / 10000;

                    pumperETHBalance += pumperETHShare;
                    dividendsETHBalance += dividendsETHShare;

                    developmentWallet.transfer(developmentETHShare);
                   _distributeDividends(dividendsETHShare);

                    emit Swap(contractBalance, ETHBalance);
                }
        }
    
        function _addLiquidity(uint256 tokenAmt, uint256 ETHAmt) private {
            _approve(address(this), address(uniswapV2Router), tokenAmt);
            
            uniswapV2Router.addLiquidityETH{value: ETHAmt}(
                address(this),
                tokenAmt,
                0,
                0,
                address(this),
                block.timestamp
            );
        }
    
        function _swapTokensForETH(uint256 tokenAmt) private {
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = uniswapV2Router.WETH();
            
            _approve(address(this), address(uniswapV2Router), tokenAmt);
            
            uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmt,
                0, //unlimited slippage
                path,
                address(this),
                block.timestamp
            );
        }
    
        function _swapETHForTokens(uint256 ETHAmt, address recipient) internal {
            address[] memory path = new address[] (2);
            path[0] = uniswapV2Router.WETH();
            path[1] = address(this);
    
            uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ETHAmt} (
                0, //unlimited slippage
                path,
                recipient,
                block.timestamp
            );
        }
    
        function _claimMonthlyDiomandHandsReward(address holder) internal returns(uint256 rewardAmt) {
            require(isDiamondHand(holder), "5Minutes: oops! not a diomand hand.");
            require(walletBuyTimeStamp[holder] > 0, "5Minutes: you should buy 5Min tokens first.");
            require(_current5MinutesDay() <= 365, "5Minutes: diomand hands claim phase has ended!");
            require((_current5MinutesDay() - monthlyRewardClaimDay[holder]) >= 30, "5Minutes: you should wait for a month before claiming again!");

            //the reward amount applies only to the tokens bought from exchange + reward given each month
            rewardAmt = walletBuyAmt[holder] >= (_balances[holder] + total5MinutesActiveStakes[holder]) ?
                ((_balances[holder] + total5MinutesActiveStakes[holder]) / 5) :
                (walletBuyAmt[holder] / 5);
            rewardClaimCount[holder] += 1;
            _mint(holder, rewardAmt);
            walletBuyAmt[holder] += rewardAmt;
            
            rewardedTokensToHolder[holder] += rewardAmt;
            monthlyRewardClaimDay[holder] = _current5MinutesDay();
        }
    
        function _addDividendStake(address staker, uint256 amount) internal {
            uint256 payout = profitPerDividendShare * amount;
            dividendPayouts[staker] = dividendPayouts[staker] + payout;
        }
    
        function _increaseProfitPerDividendShare(uint256 amount) internal {
            if (DCDStats.totalStakedAmt != 0) {
                if (emptyDividendTokens != 0) {
                    amount += emptyDividendTokens;
                    emptyDividendTokens = 0;
                }
                profitPerDividendShare += ((amount * distributionMultiplier) / DCDStats.totalStakedAmt);
            } else {
                emptyDividendTokens += amount;
            }
        }
    
        function _distributeDividends(uint256 amount) internal {
            if (amount > 0) {
                totalDistributions += amount;
                _increaseProfitPerDividendShare(amount);
                emit dividendsPofitDistributed(amount);
            }
        }
    
        function _withdrawDividends(address payable staker, uint256 amount) internal {
            require(dividendsOfStaker(staker) >= amount, "5Minutes: cannot withdraw more dividends than you have earned.");  
    
            dividendPayouts[staker] =
                dividendPayouts[staker] +
                (amount * distributionMultiplier);
    
            staker.transfer(amount);
            dividendsETHBalance -= amount;
            totalDividendsWithdrawn[staker] += amount;
            totalDividendsPaid += amount;
    
            emit dividendsProfitWithdrawn(staker, amount);
        }
    
        function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
            _transfer(_msgSender(), recipient, amount);
            return true;
        }
    
        function allowance(address owner, address spender) public view virtual override returns (uint256) {
            return _allowances[owner][spender];
        }
    
        function approve(address spender, uint256 amount) public virtual override returns (bool) {
            _approve(_msgSender(), spender, amount);
            return true;
        }
    
        function transferFrom(
            address sender,
            address recipient,
            uint256 amount
        ) public virtual override returns (bool) {
            _transfer(sender, recipient, amount);
    
            uint256 currentAllowance = _allowances[sender][_msgSender()];
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            _approve(sender, _msgSender(), currentAllowance - amount);
    
            return true;
        }
    
        function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
            _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
            return true;
        }
    
        function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
            uint256 currentAllowance = _allowances[_msgSender()][spender];
            require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
    
            return true;
        }
    }
    
    abstract contract Additions is ERC20 {
        
        using SafeMath for uint256;
        using SafeMath32 for uint32;
        
        function _toBytes16(uint256 _num) internal pure returns (bytes16) {
            return bytes16(bytes32(_num));
        } 
    
        function _generateStakeID(address _staker) internal view returns (bytes16 stakeID) {
            return generateStakeID(_staker, stakeCount[_staker]);
        }
    
        function generateStakeID(address staker, uint256 count) public pure returns (bytes16) {
            return (_toBytes16(uint256(keccak256(abi.encodePacked(staker, count, "0x01")))));
        }
    
        function stakesPagination(address _staker, uint256 _offset, uint256 _length) internal view returns (bytes16 [] memory _stakes) {
            uint256 start = _offset > 0 && stakeCount[_staker] > _offset ?
                stakeCount[_staker] - _offset : stakeCount[_staker];
                
            uint256 finish = _length > 0 && start > _length ?
                start - _length : 0;
                
            uint256 i;
            
            _stakes = new bytes16[] (start - finish);
        
            for (uint256 _stakeIndex = start; _stakeIndex > finish; _stakeIndex--) {
                bytes16 _stakeID = generateStakeID(_staker, _stakeIndex - 1);
                if (stakes[_staker][_stakeID].stakedAmt > 0) {
                    _stakes[i] = _stakeID;
                    i++;
                }
            }
        }
    
        function lastStakeID(address _staker) public view returns (bytes16) {
            return stakeCount[_staker] == 0 ?
                bytes16(0) : generateStakeID(_staker, stakeCount[_staker].sub(1));
        }
    
        function _increaseStakeCount(address _staker) internal {
            stakeCount[_staker] += 1;
        }
    
        function _isMatureStake(Stake memory _stake) internal view returns (bool) {
            return _stake.closeDay > 0 ?
                _stake.finalDay <= _stake.closeDay :
                _stake.finalDay <= _current5MinutesDay();
        }
    
        function _stakeNotStarted(Stake memory _stake) internal view returns (bool) {
            return _stake.closeDay > 0 ?
                _stake.startDay > _stake.closeDay :
                _stake.startDay > _current5MinutesDay();
        }
    
        function _stakeEnded(Stake memory _stake) internal view returns (bool) {
            return _stake.isActive == false || _isMatureStake(_stake);
        }
    
        function _daysDiff(uint32 _start, uint32 _end) internal pure returns (uint32) {
            return _end > _start ? _end.sub(_start) : 0;
        }
        
        function _daysLeft(Stake memory _stake) internal view returns (uint32) {
            return _stake.isActive == false
            ? _daysDiff(_stake.closeDay, _stake.finalDay) :
            _daysDiff(_current5MinutesDay(), _stake.finalDay);
        }
        
        function _dayCalculation(Stake memory _stake) internal view returns (uint32) {
            return _stake.finalDay > DCDStats.fiveMinutesDay 
                ? DCDStats.fiveMinutesDay : _stake.finalDay;
        }
        
        function _startDay(Stake memory _stake) internal pure returns (uint32) {
            return _stake.scrapeDay == 0 ? _stake.startDay : _stake.scrapeDay;
        }
    
        function _notPast(uint32 _day) internal view returns (bool) {
            return _day >= _current5MinutesDay();
        }
        
        function _notFuture(uint32 _day) internal view returns (bool) {
            return _day <= _current5MinutesDay();
        }
    
        function _getStakingDays(Stake memory _stake) internal pure returns (uint32) {
            return _stake.stakingDays > 1 ? _stake.stakingDays - 1 : 1;
        }
      
        function getTokensStaked(address _staker) public view returns (uint256) {
            return total5MinutesActiveStakes[_staker];
        }
    }
    
    abstract contract DCD is Additions {
    
        using SafeMath for uint256;
        using SafeMath32 for uint32;
    
        function manualDailySnapshot()
            public
        {
            _dailySnapshotPoint(_current5MinutesDay());
        }
    
        function manualDailySnapshotPoint(
            uint32 _updateDay
        )
            public
        {
            require(
                _updateDay > 0 &&
                _updateDay < _current5MinutesDay(),
                '5Minutes: day has not reached yet.'
            );

            require(
                _updateDay > DCDStats.fiveMinutesDay,
                '5Minutes: snapshot already taken for that day'
            );
    
            _dailySnapshotPoint(_updateDay);
        }

        function _createDCDStake(
            address _staker,
            uint256 _stakeAmt,
            uint32 _stakeLength,
            string memory _description)
            internal
            returns (
            Stake memory _newStake,
            bytes16 _stakeID,
            uint32 _startDay
        )
        {
            _burn(_staker, _stakeAmt);
            if (total5MinutesActiveStakes[_staker] == 0) {
                DCDStats.totalStakers += 1;
            }
            total5MinutesActiveStakes[_staker] = total5MinutesActiveStakes[_staker].add(_stakeAmt);
            _addDividendStake(_staker, _stakeAmt);

            _startDay = _next5MinutesDay();
            _stakeID = _generateStakeID(_staker);
            _newStake.stakingDays = _stakeLength;
            _newStake.startDay = _startDay;
            _newStake.finalDay = _startDay + _stakeLength;
            _newStake.details = _description;
            _newStake.stakedAmt = _stakeAmt;
            _newStake.isActive = true;
            _newStake.stakeShares = _stakeShares(_stakeAmt, _stakeLength, DCDStats.sharePrice);
    
            return (_newStake, _stakeID, _startDay);
        }

        function _endDCDStake(address _staker, bytes16 _stakeID) internal returns (Stake storage _stake, uint256 penaltyAmt, uint32 stakeLength){
            require(stakes[_staker][_stakeID].isActive, '5Minutes: not an active stake'); 

            _stake = stakes[_staker][_stakeID];
            _stake.closeDay = _current5MinutesDay();
            _stake.rewardAmt = _calcRewardAmt(_stake);
            stakeLength = _stake.stakingDays;
            penaltyAmt = _calcPenaltyAmt(_stake);
            _stake.penaltyAmt = penaltyAmt;
            taxReturnAmt = walletTaxedAmt[_staker] > _stake.stakedAmt ?
                        _staker.stakedAmt:
                        walletTaxedAmt[_staker];
            walletTaxedAmt[_staker] = walletTaxedAmt[_staker] > _stake.stakedAmt ?
                                    walletTaxedAmt[_staker] - _stake.stakedAmt :
                                    0;
            _stake.isActive = false;

            total5MinutesActiveStakes[_staker] = 
                total5MinutesActiveStakes[_staker] >= _stake.stakedAmt ?
                total5MinutesActiveStakes[_staker].sub(_stake.stakedAmt) : 0;
            dividendPayouts[_staker] = profitPerDividendShare * total5MinutesActiveStakes[_staker];
   
            if (total5MinutesActiveStakes[_staker] == 0) {
                DCDStats.totalStakers -= 1;
            }

            _withdrawDividends(payable(_staker), dividendsOfStaker(_staker));

            _mint(
                _staker, 
                _stake.stakedAmt > penaltyAmt ?
                _stake.stakedAmt - penaltyAmt : 0);

            _mint(_staker, _stake.rewardAmt);

            if (penaltyAmt == 0 && _current5MinutesDay() > 365){
                if (stakeLength >= 60 && stakeLength < 120) {
                    _mint(
                        _staker,
                        (taxReturnAmt * 2) / 10
                    )
                }
                else if (stakeLength >= 120 && stakeLength < 180) {
                    _mint(
                        _staker,
                        taxReturnAmt / 10
                    )
                }
                else{
                    _mint(
                        _staker,
                        taxReturnAmt / 5
                    )
                }
            } 
        }
    
        function _dailySnapshotPoint(
            uint32 _updateDay
        )
            internal
        {
            uint256 totalStakedToday = DCDStats.totalStakedAmt;
            uint256 scheduledToEndToday;
    
            for (uint32 _day = DCDStats.fiveMinutesDay; _day < _updateDay; _day++) {
    
                scheduledToEndToday = scheduledToEnd[_day] + snapshots[_day - 1].scheduledToEnd;
                Snapshot memory snapshot = snapshots[_day];
                snapshot.scheduledToEnd = scheduledToEndToday;
    
                snapshot.totalShares =
                    DCDStats.totalShares > scheduledToEndToday ?
                    DCDStats.totalShares - scheduledToEndToday : 0;
                
                snapshot.inflationAmt = snapshot.totalShares
                    .mul(precisionRate)
                    .div(
                        _inflationAmt(
                            totalStakedToday,
                            totalSupply(),
                            totalPenalties[_day]
                            )
                        );
    
                snapshots[_day] = snapshot;
    
                DCDStats.fiveMinutesDay++;
    
            }
        }
    
        function _inflationAmt(uint256 _staked, uint256 _supply, uint256 _penalties) internal pure returns (uint256) {
            return (_staked + _supply) * inflationDivisor / inflationRate + _penalties;
        }
        
        modifier snapshotTrigger() {
            _dailySnapshotPoint(_current5MinutesDay());
            _;
        }
        
        function _removeShares(uint32 _finalDay, uint256 _shares) internal {
            if (_notPast(_finalDay)) {
                scheduledToEnd[_finalDay] = scheduledToEnd[_finalDay] > _shares ?
                scheduledToEnd[_finalDay] - _shares : 0;
            }
            
            else {
                uint32 _lastDay = _previous5MinutesDay();
                snapshots[_lastDay].scheduledToEnd = 
                snapshots[_lastDay].scheduledToEnd > _shares ?
                snapshots[_lastDay].scheduledToEnd - _shares : 0;
            }
        }
        
        function _loopRewardAmt(
            uint256 _stakesShares,
            uint32 _startDay,
            uint32 _finalDay
        )
            internal
            view
            returns (uint256 _rewardAmt)
        {
            for (uint32 _day = _startDay; _day < _finalDay; _day++) {
                _rewardAmt += _stakesShares * precisionRate / snapshots[_day].inflationAmt;
            }
                
            if (_current5MinutesDay() > (_finalDay + uint32(14)) && _rewardAmt > 0) {
                uint256 _reductionPercent = ((uint256(_current5MinutesDay()) - uint256(_finalDay) - uint256(14)) / uint256(7)) + uint256(1);
                if (_reductionPercent > 100) {_reductionPercent = 100; }
                _rewardAmt = _rewardAmt
                    .mul(uint256(100).sub(_reductionPercent))
                    .div(100);
            }
                
            if (_current5MinutesDay() < _finalDay && _rewardAmt > 0) {
                if (_finalDay != _startDay) {
                    _rewardAmt = _rewardAmt * rewardPrecision * (uint256(_current5MinutesDay()) - uint256(_startDay)) / (uint256(_finalDay) - uint256(_startDay)) / rewardPrecision;
                }
            }
        }
        
        function _calcRewardAmt(
            Stake memory _stake
        )
            internal
            view
            returns (uint256)
        {
            return _loopRewardAmt(
                _stake.stakeShares,
                _startDay(_stake),
                _dayCalculation(_stake)
            );
        }
        
        function _detectReward(Stake memory _stake) internal view returns (uint256) {
            return _stakeNotStarted(_stake) ? 0 : _calcRewardAmt(_stake);
        }
            
        function _calcPenaltyAmt(
            Stake memory _stake
        )
            internal
            view
            returns (uint256)
        {
            return _stakeNotStarted(_stake) || _isMatureStake(_stake) ? 0 : _getPenalty(_stake);
        }
            
        function _getPenalty(Stake memory _stake) internal view returns (uint256) {
            return (_stake.stakingDays - _daysLeft(_stake)) >= (_stake.stakingDays / 2) 
                ? 0
                : ( _stake.stakedAmt - ((_stake.stakedAmt * (_stake.stakingDays - _daysLeft(_stake))) / (_stake.stakingDays / 2)));
        }
        
        function _checkRewardAmtbyID(address _staker, bytes16 _stakeID) internal view returns (uint256 rewardAmt) {
            Stake memory stake = stakes[_staker][_stakeID];
            return stake.isActive ? _detectReward(stake) : stake.rewardAmt;
        }
            
        function _checkPenaltyAmtbyID(address _staker, bytes16 _stakeID) internal view returns (uint256 penaltyAmt) {
            Stake memory stake = stakes[_staker][_stakeID];
            return  stake.isActive ? _calcPenaltyAmt(stake) : stake.penaltyAmt;
        }
        
        function _stakeShares(
            uint256 _stakedAmt,
            uint32 _stakingDays,
            uint256 _sharePrice)
            internal
            pure
            returns (uint256)
        {
            return _sharesAmt(_stakedAmt, _stakingDays, _sharePrice);
        }
            
        function _sharesAmt(
            uint256 _stakedAmt,
            uint32 _stakingDays,
            uint256 _sharePrice)
            internal
            pure 
            returns (uint256)
        {
            return _baseAmt(_stakedAmt, _sharePrice)
                .mul(sharesPrecision + _getBonus(_stakingDays))
                .div(sharesPrecision);
        }
            
        function _getBonus(uint32 _stakingLength) internal pure returns (uint256) {
            return _stakingLength.div(365) == 0 ?
                _stakingLength :
                _getHigherDays(_stakingLength);
        }
            
        function _getHigherDays(uint32 _stakingLength) internal pure returns (uint256 _days) {
            for (uint32 i = 0; i < _stakingLength.div(365); i++) {
                _days += _stakingLength - (i * 365);
            }
            _days += _stakingLength - (_stakingLength.div(365) * 365);
            return uint256(_days);
        }
            
        function _addShares(uint32 _finalDay, uint256 _shares) internal {
            scheduledToEnd[_finalDay] = scheduledToEnd[_finalDay].add(_shares);
        }
            
        function _sharesPriceUpdate(
            uint256 _stakedAmt,
            uint256 _rewardAmt,
            uint32 _stakingDays,
            uint256 _stakesShares
            )
            internal
        {
            if (_stakesShares > 0 && _current5MinutesDay() > 1) {
    
                uint256 _newSharePrice = _getNewSharePrice(
                    _stakedAmt,
                    _rewardAmt,
                    _stakesShares,                    
                    _stakingDays
                    );
                        
                if (_newSharePrice > DCDStats.sharePrice) {
                        
                    _newSharePrice = _newSharePrice < DCDStats.sharePrice.mul(230).div(100) ?
                    _newSharePrice : DCDStats.sharePrice.mul(230).div(100);
                        
                    emit newSharePrice(
                        _newSharePrice,
                        DCDStats.sharePrice,
                        _current5MinutesDay()
                    );
                    
                    DCDStats.sharePrice = _newSharePrice;
                }
            }
        }
    
        function _getNewSharePrice(
            uint256 _stakedAmt,
            uint256 _rewardAmt,
            uint256 _stakesShares,
            uint32 _stakingDays)
            internal
            pure 
            returns (uint256) {
                    
                uint256  _bonusAmt = _getBonus(_stakingDays);
                    
                return
                    _stakedAmt
                        .add(_rewardAmt)
                        .mul(_bonusAmt)
                        .mul(bonusPrecision)
                        .div(_stakesShares);
        }
           
        function _baseAmt(
            uint256 _stakedAmt,
            uint256 _sharePrice
        )
            internal
            pure
            returns (uint256)
        {
            return
                _stakedAmt
                    .mul(precisionRate)
                    .div(_sharePrice);
        }
    }
