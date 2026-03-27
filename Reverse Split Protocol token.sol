// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 *
 * @notice Innovative contract featuring the Reverse Split Protocol (RSP)
 * @dev This contract implements an ERC-20 token with a built-in supply reduction mechanism.
 *
 * Core Innovation - Reverse Split Protocol (RSP):
 * - Total of 84 supply reductions (reverse splits)
 * - Each rebase reduces total supply by 20%
 * - Rebases occur every 4 hours
 * - Full cycle lasts 14 days
 * - After 84 rebases, supply is permanently set to 777,777,777 tokens
 * - Taxes drop to 0% and all limits are removed automatically
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface InterfaceLP {
    function sync() external;
}

abstract contract ERC20Detailed is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public view returns (uint8) { return _decimals; }
}

interface IDEXRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract Ownable {
    address private _owner;
    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(_owner);
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract <<TOKEN_NAME>> is ERC20Detailed, Ownable {
    // =========================================================================
    // Reverse Split Protocol (RSP) Parameters
    // =========================================================================

    /// @notice Frequency of rebases (every 4 hours)
    uint256 public rebaseFrequency = 4 hours;

    /// @notice Timestamp when the next rebase can occur
    uint256 public nextRebase;

    /// @notice Timestamp of the final rebase (end of 14-day cycle)
    uint256 public finalRebase;

    /// @notice Whether automatic rebases are enabled
    bool public autoRebase = true;

    /// @notice Whether the rebase cycle has been started
    bool public rebaseStarted = false;

    uint256 public rebasesThisCycle;
    uint256 public lastRebaseThisCycle;

    // =========================================================================
    // Trading & Anti-Whale Settings
    // =========================================================================

    uint256 public maxTxnAmount;
    uint256 public maxWallet;

    /// @notice Wallet that receives all taxes
    address public taxWallet;

    uint256 public taxPercentBuy = 20;
    uint256 public taxPercentSell = 80;

    

    mapping(address => bool) public isWhitelisted;

    uint8 private constant DECIMALS = 9;

    /// @dev Initial supply before any rebases (~18.236 billion tokens)
    uint256 private constant INITIAL_TOKENS_SUPPLY = 18_236_939_125_700_000 * 10 ** DECIMALS;

    uint256 private constant TOTAL_PARTS = type(uint256).max - (type(uint256).max % INITIAL_TOKENS_SUPPLY);

    // Events
    event Rebase(uint256 indexed time, uint256 totalSupply);
    event RemovedLimits();

    // DEX Interfaces
    IWETH public immutable weth;
    IDEXRouter public immutable router;
    address public immutable pair;

    bool public limitsInEffect = true;
    bool public tradingIsLive = false;

    uint256 private _totalSupply;
    uint256 private _partsPerToken;
    uint256 private partsSwapThreshold = TOTAL_PARTS / 100000 * 25; // 0.025% of parts

    mapping(address => uint256) private _partBalances;
    mapping(address => mapping(address => uint256)) private _allowedTokens;

    mapping(address => bool) private _bots;

    modifier validRecipient(address to) {
        require(to != address(0), "ERC20: transfer to the zero address");
        _;
    }

    bool private inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() ERC20Detailed("<<TOKEN_NAME>>", "<<TOKEN_SYMBOL>>", DECIMALS) {
        address dexAddress;
        if (block.chainid == 1) {
            dexAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Ethereum
        } else if (block.chainid == 5) {
            dexAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Goerli
        } else if (block.chainid == 97) {
            dexAddress = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // Pancake Testnet
        } else if (block.chainid == 56) {
            dexAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PancakeSwap BSC
        } else {
            revert("Chain not configured");
        }

        taxWallet = msg.sender;

        router = IDEXRouter(dexAddress);
        weth = IWETH(router.WETH());

        _totalSupply = INITIAL_TOKENS_SUPPLY;
        _partBalances[msg.sender] = TOTAL_PARTS;
        _partsPerToken = TOTAL_PARTS / _totalSupply;

        isWhitelisted[address(this)] = true;
        isWhitelisted[address(router)] = true;
        isWhitelisted[msg.sender] = true;

        maxTxnAmount = _totalSupply * 2 / 100;
        maxWallet = _totalSupply * 2 / 100;

        pair = IDEXFactory(router.factory()).createPair(address(this), router.WETH());

        _allowedTokens[address(this)][address(router)] = type(uint256).max;
        _allowedTokens[address(this)][address(this)] = type(uint256).max;
        _allowedTokens[msg.sender][address(router)] = type(uint256).max;

        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    // =========================================================================
    // ERC20 Standard Functions
    // =========================================================================

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _partBalances[account] / _partsPerToken;
    }

    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowedTokens[owner_][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowedTokens[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external override validRecipient(recipient) returns (bool) {
        _transferFrom(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override validRecipient(recipient) returns (bool) {
        if (_allowedTokens[sender][msg.sender] != type(uint256).max) {
            require(_allowedTokens[sender][msg.sender] >= amount, "ERC20: insufficient allowance");
            _allowedTokens[sender][msg.sender] -= amount;
        }
        _transferFrom(sender, recipient, amount);
        return true;
    }

    // =========================================================================
    // Reverse Split Protocol (RSP) Logic
    // =========================================================================

    function shouldRebase() public view returns (bool) {
        return nextRebase <= block.timestamp ||
               (autoRebase && rebaseStarted && rebasesThisCycle < 10 && lastRebaseThisCycle + 60 <= block.timestamp);
    }

    /**
     * @notice Executes a rebase, reducing total supply by 20%
     * @dev Called automatically on sell or manually via manualRebase()
     */
    function rebase() internal returns (uint256) {
        uint256 time = block.timestamp;
        uint256 supplyDelta = _totalSupply * 2 / 100; // 20% reduction

        if (nextRebase < block.timestamp) {
            rebasesThisCycle = 1;
            nextRebase += rebaseFrequency;
        } else {
            rebasesThisCycle += 1;
            lastRebaseThisCycle = block.timestamp;
        }

        if (supplyDelta == 0) {
            emit Rebase(time, _totalSupply);
            return _totalSupply;
        }

        _totalSupply -= supplyDelta;

        // Final rebase - end of RSP cycle
        if (nextRebase >= finalRebase) {
            nextRebase = type(uint256).max;
            autoRebase = false;
            _totalSupply = 777_777_777 * (10 ** decimals());

            if (limitsInEffect) {
                limitsInEffect = false;
                emit RemovedLimits();
            }

            if (balanceOf(address(this)) > 0) {
                try this.swapBack() {} catch {}
            }

            taxPercentBuy = 0;
            taxPercentSell = 0;
        }

        _partsPerToken = TOTAL_PARTS / _totalSupply;
        lpSync();

        emit Rebase(time, _totalSupply);
        return _totalSupply;
    }

    function manualRebase() external {
        require(shouldRebase(), "Rebase is not available yet");
        rebase();
    }

    function startRebaseCycles() external onlyOwner {
        require(!rebaseStarted, "Rebase cycle has already started");
        nextRebase = block.timestamp + rebaseFrequency;
        finalRebase = block.timestamp + 14 days;
        rebaseStarted = true;
    }

    function lpSync() internal {
        InterfaceLP(pair).sync();
    }

    // =========================================================================
    // Internal Transfer Logic with Tax & Rebase
    // =========================================================================

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(!_bots[sender] && !_bots[recipient] && !_bots[msg.sender], "Address is blacklisted");

        address pairAddress = pair;
        uint256 partAmount = amount * _partsPerToken;

        if (autoRebase && !inSwap && !isWhitelisted[sender] && !isWhitelisted[recipient]) {
            require(tradingIsLive, "Trading is not live yet");

            if (limitsInEffect) {
                if (sender == pairAddress || recipient == pairAddress) {
                    require(amount <= maxTxnAmount, "Exceeds maximum transaction amount");
                }
                if (recipient != pairAddress) {
                    require(balanceOf(recipient) + amount <= maxWallet, "Exceeds maximum wallet limit");
                }
            }

            // Auto swap taxes on sell
            if (recipient == pairAddress) {
                if (balanceOf(address(this)) >= partsSwapThreshold / _partsPerToken) {
                    try this.swapBack() {} catch {}
                }
                if (shouldRebase()) {
                    rebase();
                }
            }

            // Apply tax
            uint256 taxPartAmount = 0;
            if (sender == pairAddress) {
                taxPartAmount = partAmount * taxPercentBuy / 100;
            } else if (recipient == pairAddress) {
                taxPartAmount = partAmount * taxPercentSell / 100;
            }

            if (taxPartAmount > 0) {
                _partBalances[sender] -= taxPartAmount;
                _partBalances[address(this)] += taxPartAmount;
                emit Transfer(sender, address(this), taxPartAmount / _partsPerToken);
                partAmount -= taxPartAmount;
            }
        }

        _partBalances[sender] -= partAmount;
        _partBalances[recipient] += partAmount;

        emit Transfer(sender, recipient, partAmount / _partsPerToken);
        return true;
    }

    // =========================================================================
    // Owner / Admin Functions
    // =========================================================================

    function enableTrading() external onlyOwner {
        require(!tradingIsLive, "Trading is already enabled");
        tradingIsLive = true;
    }

    function removeLimits() external onlyOwner {
        require(limitsInEffect, "Limits have already been removed");
        limitsInEffect = false;
        emit RemovedLimits();
    }

    function whitelistWallet(address account, bool value) external onlyOwner {
        isWhitelisted[account] = value;
    }

    function updateTaxWallet(address newTaxWallet) external onlyOwner {
        require(newTaxWallet != address(0), "Cannot set zero address");
        taxWallet = newTaxWallet;
    }

    function updateTaxPercent(uint256 newBuyTax, uint256 newSellTax) external onlyOwner {
        require(newBuyTax <= 10 && newSellTax <= 10, "Tax cannot exceed 10%");
        taxPercentBuy = newBuyTax;
        taxPercentSell = newSellTax;
    }

    function manageBots(address[] memory accounts, bool isBot) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _bots[accounts[i]] = isBot;
        }
    }

    // =========================================================================
    // Tax Swap Functions
    // =========================================================================

    function swapBack() public swapping {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0) return;

        if (contractBalance > (partsSwapThreshold / _partsPerToken) * 20) {
            contractBalance = (partsSwapThreshold / _partsPerToken) * 20;
        }

        swapTokensForETH(contractBalance);
    }

    function swapTokensForETH(uint256 tokenAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(weth);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            taxWallet,
            block.timestamp
        );
    }

    function refreshBalances(address[] memory wallets) external {
        for (uint256 i = 0; i < wallets.length; i++) {
            emit Transfer(wallets[i], wallets[i], 0);
        }
    }

    receive() external payable {}
}

interface IWETH {
    function deposit() external payable;
}