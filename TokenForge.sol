// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title  ForgedToken
/// @notice ERC-20 token deployed by the TokenForge factory.
///         Supports optional Mintable, Burnable, and Pausable features.
///         The deploying wallet is set as owner and receives the full supply.
contract ForgedToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable {

    bool    public mintable;
    bool    public burnable;
    bool    public pausable;
    uint8   private _decimals;

    constructor(
        string  memory name_,
        string  memory symbol_,
        uint256 initialSupply,
        uint8   decimals_,
        bool    mintable_,
        bool    burnable_,
        bool    pausable_,
        address owner_
    )
        ERC20(name_, symbol_)
        Ownable(owner_)
    {
        _decimals = decimals_;
        mintable  = mintable_;
        burnable  = burnable_;
        pausable  = pausable_;

        // Mint total supply to the owner
        _mint(owner_, initialSupply * (10 ** uint256(decimals_)));
    }

    // ─── Overrides ─────────────────────────────────────────────────────────

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }

    // ─── Owner actions ─────────────────────────────────────────────────────

    /// @notice Mint additional tokens. Only available if mintable is true.
    function mint(address to, uint256 amount) external onlyOwner {
        require(mintable, "TokenForge: not mintable");
        _mint(to, amount);
    }

    /// @notice Pause all token transfers. Only available if pausable is true.
    function pause() external onlyOwner {
        require(pausable, "TokenForge: not pausable");
        _pause();
    }

    /// @notice Unpause token transfers.
    function unpause() external onlyOwner {
        require(pausable, "TokenForge: not pausable");
        _unpause();
    }

    // ─── Burnable override ─────────────────────────────────────────────────

    /// @notice Burn tokens from caller's balance. Only available if burnable is true.
    function burn(uint256 amount) public override {
        require(burnable, "TokenForge: not burnable");
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override {
        require(burnable, "TokenForge: not burnable");
        super.burnFrom(account, amount);
    }
}

// ══════════════════════════════════════════════════════════════════════════════

/// @title  TokenForge
/// @notice Permissionless ERC-20 factory deployed on Botchain.
///         Anyone calls createToken() to deploy their own ForgedToken.
///         The factory keeps a public registry of all deployed tokens.
contract TokenForge {

    // ─── Structs ───────────────────────────────────────────────────────────

    struct TokenInfo {
        address tokenAddress;
        address owner;
        string  name;
        string  symbol;
        uint256 initialSupply;
        uint8   decimals;
        bool    mintable;
        bool    burnable;
        bool    pausable;
        uint256 createdAt;
    }

    // ─── Storage ───────────────────────────────────────────────────────────

    /// All tokens ever deployed through this factory
    TokenInfo[] public allTokens;

    /// owner address => list of token addresses they deployed
    mapping(address => address[]) public ownerTokens;

    /// token address => index in allTokens (1-based; 0 means not found)
    mapping(address => uint256) private _tokenIndex;

    // ─── Events ────────────────────────────────────────────────────────────

    event TokenCreated(
        address indexed tokenAddress,
        address indexed owner,
        string  name,
        string  symbol,
        uint256 initialSupply,
        uint8   decimals,
        bool    mintable,
        bool    burnable,
        bool    pausable,
        uint256 timestamp
    );

    // ─── Factory function ──────────────────────────────────────────────────

    /// @notice Deploy a new ERC-20 token. Caller becomes the token owner
    ///         and receives the full initial supply.
    /// @param  name          Token name, e.g. "My Token".
    /// @param  symbol        Token ticker, e.g. "MTK".
    /// @param  initialSupply Supply before applying decimals (human-readable amount).
    /// @param  decimals_     Token decimals (0–18). Standard is 18.
    /// @param  mintable      Owner can mint new tokens after deploy.
    /// @param  burnable      Holders can burn their own tokens.
    /// @param  pausable      Owner can pause all transfers.
    /// @return tokenAddress  Address of the newly deployed token contract.
    function createToken(
        string  calldata name,
        string  calldata symbol,
        uint256 initialSupply,
        uint8   decimals_,
        bool    mintable,
        bool    burnable,
        bool    pausable
    ) external returns (address tokenAddress) {
        require(bytes(name).length > 0,   "TokenForge: name required");
        require(bytes(symbol).length > 0, "TokenForge: symbol required");
        require(initialSupply > 0,        "TokenForge: supply must be > 0");
        require(decimals_ <= 18,          "TokenForge: decimals max 18");

        ForgedToken token = new ForgedToken(
            name,
            symbol,
            initialSupply,
            decimals_,
            mintable,
            burnable,
            pausable,
            msg.sender
        );

        tokenAddress = address(token);

        allTokens.push(TokenInfo({
            tokenAddress: tokenAddress,
            owner:        msg.sender,
            name:         name,
            symbol:       symbol,
            initialSupply: initialSupply,
            decimals:     decimals_,
            mintable:     mintable,
            burnable:     burnable,
            pausable:     pausable,
            createdAt:    block.timestamp
        }));

        _tokenIndex[tokenAddress] = allTokens.length; // 1-based
        ownerTokens[msg.sender].push(tokenAddress);

        emit TokenCreated(
            tokenAddress, msg.sender, name, symbol,
            initialSupply, decimals_, mintable, burnable, pausable,
            block.timestamp
        );
    }

    // ─── Views ─────────────────────────────────────────────────────────────

    /// @notice Total number of tokens deployed through this factory.
    function getTokenCount() external view returns (uint256) {
        return allTokens.length;
    }

    /// @notice All token addresses deployed by a specific owner.
    function getOwnerTokens(address owner)
        external
        view
        returns (address[] memory)
    {
        return ownerTokens[owner];
    }

    /// @notice Full metadata for a token deployed through this factory.
    function getTokenInfo(address tokenAddress)
        external
        view
        returns (TokenInfo memory)
    {
        uint256 idx = _tokenIndex[tokenAddress];
        require(idx > 0, "TokenForge: token not found");
        return allTokens[idx - 1];
    }

    /// @notice Paginated list of all deployed tokens.
    function getTokensPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (TokenInfo[] memory page)
    {
        uint256 end = offset + limit > allTokens.length
            ? allTokens.length
            : offset + limit;
        if (offset >= allTokens.length) return page;
        page = new TokenInfo[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = allTokens[i];
        }
    }
}
