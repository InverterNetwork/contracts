// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

//Internal Interface
import {
    IERC20,
    IRebasingERC20,
    IERC20Metadata
} from "src/modules/fundingManager/rebasing/interfaces/IRebasingERC20.sol";

/**
 * @title The Elastic Receipt Token
 *
 * @dev The Elastic Receipt Token is a rebase token that "continuously"
 *      syncs the token supply with a supply target.
 *
 *      A downstream contract, inheriting from this contract, needs to
 *      implement the `_supplyTarget()` function returning the current
 *      supply target for the Elastic Receipt Token supply.
 *
 *      The downstream contract can mint and burn tokens to addresses with
 *      the assumption that the supply target changes precisely by the amount
 *      of tokens minted/burned.
 *
 *      # Example Use-Case
 *
 *      Using the Elastic Receipt Token with a treasury as downstream contract
 *      holding assets worth 10,000 USD, and returning that amount in the
 *      `_supplyTarget()` function, leads to a token supply of 10,000.
 *
 *      If a user wants to deposit assets worth 1,000 USD into the treasury,
 *      the treasury fetches the assets from the user and mints 1,000 Elastic
 *      Receipt Tokens to the user.
 *
 *      If the treasury's valuation contracts to 5,000 USD, the token balance
 *      of each user, and the total token supply, is decreased by 50%.
 *      In case of an expansion of the treasury's valuation, the user balances
 *      and the total token supply is increased by the respective percentage
 *      change.
 *
 *      Note that the expansion/contraction of the treasury needs to be send
 *      upstream through the `_supplyTarget()` function!
 *
 *      # Glossary
 *
 *      As any elastic supply token, the Elastic Receipt Token defines an
 *      internal (fixed) user balance and an external (elastic) user balance.
 *      The internal balance is called `bits`, the external `tokens`.
 *
 *      -> Internal account balance             `_accountBits[account]`
 *      -> Internal bits-token conversion rate  `_bitsPerToken`
 *      -> Public account balance               `_accountBits[account] / _bitsPerToken`
 *      -> Public total token supply            `_totalTokenSupply`
 *
 * @author Buttonwood Foundation
 * @author merkleplant
 */
abstract contract ElasticReceiptTokenBase is IRebasingERC20, ERC165 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IRebasingERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // !!!        PLEASE READ BEFORE CHANGING ANY ACCOUNTING OR MATH         !!!
    //
    // We make the following guarantees:
    // - If address A transfers x tokens to address B, A's resulting external
    //   balance will be decreased by "precisely" x tokens and B's external
    //   balance will be increased by "precisely" x tokens.
    // - If address A mints x tokens, A's resulting external balance will
    //   increase by "precisely" x tokens.
    // - If address A burns x tokens, A's resulting external balance will
    //   decrease by "precisely" x tokens.
    //
    // We do NOT guarantee that the sum of all balances equals the total token
    // supply. This is because, for any conversion function `f()` that has
    // non-zero rounding error, `f(x0) + f(x1) + ... f(xn)` is not equal to
    // `f(x0 + x1 + ... xn)`.
    //--------------------------------------------------------------------------

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Invalid token recipient.
    error InvalidRecipient();

    /// @notice Invalid token amount.
    error InvalidAmount();

    /// @notice Maximum supply reached.
    error MaxSupplyReached();

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev Modifier to guarantee token recipient is valid.
    modifier validRecipient(address to) {
        if (to == address(0) || to == address(this)) {
            revert InvalidRecipient();
        }
        _;
    }

    /// @dev Modifier to guarantee token amount is valid.
    modifier validAmount(uint amount) {
        if (amount == 0) {
            revert InvalidAmount();
        }
        _;
    }

    /// @dev Modifier to guarantee a rebase operation is executed before any
    ///      state is mutated.
    modifier onAfterRebase() {
        _rebase();
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Math constant.
    uint private constant MAX_UINT = type(uint).max;

    /// @dev The max supply target allowed.
    /// @dev Note that this constant is internal in order for downstream
    ////     contracts to enforce this constraint directly.
    uint internal constant MAX_SUPPLY = 1_000_000_000e18;

    /// @dev The total amount of bits is a multiple of MAX_SUPPLY so that
    ///      BITS_PER_UNDERLYING is an integer.
    ///      Use the highest value that fits in a uint for max granularity.
    uint internal constant TOTAL_BITS = MAX_UINT - (MAX_UINT % MAX_SUPPLY);

    /// @dev Initial conversion rate of bits per unit of denomination.
    uint internal constant BITS_PER_UNDERLYING = TOTAL_BITS / MAX_SUPPLY;

    //--------------------------------------------------------------------------
    // Internal Storage

    /// @dev The rebase counter, i.e. the number of rebases executed since
    ///      inception.
    uint internal _epoch;

    /// @dev The amount of bits one token is composed of, i.e. the bits-token
    ///      conversion rate.
    uint internal _bitsPerToken;

    /// @dev The total supply of tokens. In each token balance mutating
    ///      function the token supply is synced with the supply target
    ///      given by the downstream implemented _supplyTarget function.
    uint internal _totalTokenSupply;

    /// @dev The user balances, denominated in bits.
    mapping(address => uint) internal _accountBits;

    /// @dev The user allowances, denominated in tokens.
    mapping(address => mapping(address => uint)) internal _tokenAllowances;

    //--------------------------------------------------------------------------
    // ERC20 Storage

    /// @inheritdoc IERC20Metadata
    string public override name;

    /// @inheritdoc IERC20Metadata
    string public override symbol;

    /// @inheritdoc IERC20Metadata
    uint8 public override decimals;

    //--------------------------------------------------------------------------
    // EIP-2616 Storage

    /// @notice The EIP-712 version.
    string public constant EIP712_REVISION = "1";

    /// @notice The EIP-712 domain hash.
    bytes32 public immutable EIP712_DOMAIN = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    /// @notice The EIP-2612 permit hash.
    bytes32 public immutable PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    /// @dev Number of EIP-2612 permits per address.
    mapping(address => uint) internal _nonces;

    //--------------------------------------------------------------------------
    // Abstract Functions

    /// @dev Returns the current supply target with number of decimals precision
    ///      being equal to the number of decimals given in the constructor.
    /// @dev The supply target MUST never be zero or higher than MAX_SUPPLY,
    ///      otherwise no supply adjustment can be executed.
    /// @dev Has to be implemented in downstream contract.
    function _supplyTarget() internal virtual returns (uint);

    //--------------------------------------------------------------------------
    // Public ERC20-like Mutating Functions

    /// @inheritdoc IERC20
    function transfer(address to, uint tokens)
        public
        override(IERC20)
        validRecipient(to)
        validAmount(tokens)
        onAfterRebase
        returns (bool)
    {
        uint bits = _tokensToBits(tokens);

        _transfer(msg.sender, to, tokens, bits);

        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint tokens)
        public
        override(IERC20)
        validRecipient(from)
        validRecipient(to)
        validAmount(tokens)
        onAfterRebase
        returns (bool)
    {
        uint bits = _tokensToBits(tokens);

        _useAllowance(from, msg.sender, tokens);
        _transfer(from, to, tokens, bits);

        return true;
    }

    /// @inheritdoc IRebasingERC20
    function transferAll(address to)
        public
        override(IRebasingERC20)
        validRecipient(to)
        onAfterRebase
        returns (bool)
    {
        uint bits = _accountBits[msg.sender];
        uint tokens = _bitsToTokens(bits);

        _transfer(msg.sender, to, tokens, bits);

        return true;
    }

    /// @inheritdoc IRebasingERC20
    function transferAllFrom(address from, address to)
        public
        override(IRebasingERC20)
        validRecipient(from)
        validRecipient(to)
        onAfterRebase
        returns (bool)
    {
        uint bits = _accountBits[from];
        uint tokens = _bitsToTokens(bits);

        // Note that a transfer of zero tokens is valid to handle dust.
        if (tokens == 0) {
            // Decrease allowance by one. This is a conservative security
            // compromise as the dust could otherwise be stolen.
            // Note that allowances could be off by one because of this.
            _useAllowance(from, msg.sender, 1);
        } else {
            _useAllowance(from, msg.sender, tokens);
        }

        _transfer(from, to, tokens, bits);

        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint tokens)
        public
        override(IERC20)
        validRecipient(spender)
        returns (bool)
    {
        _tokenAllowances[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    /// @notice Increases the amount of tokens that msg.sender has allowed
    ///         to spender.
    /// @param spender The address of the spender.
    /// @param tokens The amount of tokens to increase allowance by.
    /// @return True if successful.
    function increaseAllowance(address spender, uint tokens)
        public
        returns (bool)
    {
        _tokenAllowances[msg.sender][spender] += tokens;

        emit Approval(
            msg.sender, spender, _tokenAllowances[msg.sender][spender]
        );
        return true;
    }

    /// @notice Decreases the amount of tokens that msg.sender has allowed
    ///         to spender.
    /// @param spender The address of the spender.
    /// @param tokens The amount of tokens to decrease allowance by.
    /// @return True if successful.
    function decreaseAllowance(address spender, uint tokens)
        public
        returns (bool)
    {
        if (tokens >= _tokenAllowances[msg.sender][spender]) {
            delete _tokenAllowances[msg.sender][spender];
        } else {
            _tokenAllowances[msg.sender][spender] -= tokens;
        }

        emit Approval(
            msg.sender, spender, _tokenAllowances[msg.sender][spender]
        );
        return true;
    }

    //--------------------------------------------------------------------------
    // Public IRebasingERC20 Mutating Functions

    /// @inheritdoc IRebasingERC20
    function rebase() public override(IRebasingERC20) onAfterRebase {
        // NO-OP because modifier executes rebase.
        return;
    }

    //--------------------------------------------------------------------------
    // Public EIP-2616 Mutating Functions

    /// @notice Sets the amount of tokens that owner has allowed to spender.
    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= deadline);

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                PERMIT_TYPEHASH,
                                owner,
                                spender,
                                value,
                                _nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner);

            _tokenAllowances[owner][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IERC20
    function allowance(address owner_, address spender)
        public
        view
        returns (uint)
    {
        return _tokenAllowances[owner_][spender];
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint) {
        return _totalTokenSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address who) public view returns (uint) {
        return _accountBits[who] / _bitsPerToken;
    }

    /// @inheritdoc IRebasingERC20
    function scaledTotalSupply() public view returns (uint) {
        return _activeBits();
    }

    /// @inheritdoc IRebasingERC20
    function scaledBalanceOf(address who) public view returns (uint) {
        return _accountBits[who];
    }

    /// @notice Returns the number of successful permits for an address.
    /// @param who The address to check the number of permits for.
    /// @return The number of successful permits.
    function nonces(address who) public view returns (uint) {
        return _nonces[who];
    }

    /// @notice Returns the EIP-712 domain separator hash.
    /// @return The EIP-712 domain separator hash.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN,
                keccak256(bytes(name)),
                keccak256(bytes(EIP712_REVISION)),
                block.chainid,
                address(this)
            )
        );
    }

    //--------------------------------------------------------------------------
    // Internal View Functions

    /// @dev Convert tokens (elastic amount) to bits (fixed amount).
    function _tokensToBits(uint tokens) internal view returns (uint) {
        return _bitsPerToken == 0
            ? tokens * BITS_PER_UNDERLYING
            : tokens * _bitsPerToken;
    }

    /// @dev Convert bits (fixed amount) to tokens (elastic amount).
    function _bitsToTokens(uint bits) internal view returns (uint) {
        return bits / _bitsPerToken;
    }

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    /// @dev Mints an amount of tokens to some address.
    /// @dev It's assumed that the downstream contract increases its supply
    ///      target by precisely the token amount minted!
    function _mint(address to, uint tokens)
        internal
        validRecipient(to)
        validAmount(tokens)
        onAfterRebase
    {
        // Do not mint more than allowed.
        if (_totalTokenSupply + tokens > MAX_SUPPLY) {
            revert MaxSupplyReached();
        }

        // Get amount of bits to mint and new total amount of active bits.
        uint bitsNeeded = _tokensToBits(tokens);
        uint newActiveBits = _activeBits() + bitsNeeded;

        // Increase total token supply and adjust conversion rate only if no
        // conversion rate defined yet. Otherwise the conversion rate should
        // not change as the downstream contract is assumed to increase the
        // supply target by precisely the amount of tokens minted.
        _totalTokenSupply += tokens;
        if (_bitsPerToken == 0) {
            _bitsPerToken = newActiveBits / _totalTokenSupply;
        }

        // Notify about new rebase.
        _epoch++;
        emit Rebase(_epoch, _totalTokenSupply);

        // Transfer newly minted bits from zero address.
        _transfer(address(0), to, tokens, bitsNeeded);
    }

    /// @dev Burns an amount of tokens from some address and returns the
    ///      amount of tokens burned.
    ///      Note that due to rebasing the requested token amount to burn and
    ///      the actual amount burned may differ.
    /// @dev It's assumed that the downstream contract decreases its supply
    ///      target by precisely the token amount burned!
    /// @dev It's not possible to burn all tokens.
    function _burn(address from, uint tokens)
        internal
        validRecipient(from)
        validAmount(tokens)
        returns (uint)
    {
        // Note to first cache the bit amount of tokens before executing a
        // rebase.
        uint bits = _tokensToBits(tokens);
        _rebase();

        // Re-calculate the token amount and transfer them to zero address.
        tokens = _bitsToTokens(bits);
        _transfer(from, address(0), tokens, bits);

        // Adjust total token supply and conversion rate.
        // Note that it's not possible to withdraw all tokens as this would lead
        // to a division by 0.
        _totalTokenSupply -= tokens;
        _bitsPerToken = _activeBits() / _totalTokenSupply;

        // Notify about new rebase.
        _epoch++;
        emit Rebase(_epoch, _totalTokenSupply);

        // Return updated token amount.
        return tokens;
    }

    //--------------------------------------------------------------------------
    // Private Functions

    /// @dev Internal function to execute a rebase operation.
    ///      Fetches the current supply target from the downstream contract and
    ///      updates the bit-tokens conversion rate and the total token supply.
    function _rebase() private {
        uint supplyTarget = _supplyTarget();

        // Do not adjust supply if target is outside of valid supply range.
        // Note to not revert as this would make transfer's impossible.
        if (supplyTarget == 0 || supplyTarget > MAX_SUPPLY) {
            return;
        }

        // Adjust conversion rate and total token supply.
        _bitsPerToken = _activeBits() / supplyTarget;
        _totalTokenSupply = supplyTarget;

        // Notify about new rebase.
        _epoch++;
        emit Rebase(_epoch, supplyTarget);
    }

    /// @dev Internal function returning the total amount of active bits,
    ///      i.e. all bits not held by zero address.
    function _activeBits() private view returns (uint) {
        return TOTAL_BITS - _accountBits[address(0)];
    }

    /// @dev Internal function to transfer bits.
    ///      Note that the bits and tokens are expected to be pre-calculated.
    function _transfer(address from, address to, uint tokens, uint bits)
        private
    {
        _accountBits[from] -= bits;
        _accountBits[to] += bits;

        if (_accountBits[from] == 0) {
            delete _accountBits[from];
        }

        emit Transfer(from, to, tokens);
    }

    /// @dev Internal function to decrease ERC20 allowance.
    ///      Note that the allowance denomination is in tokens.
    function _useAllowance(address owner_, address spender, uint tokens)
        private
    {
        // Note that an allowance of max uint is interpreted as infinite.
        if (_tokenAllowances[owner_][spender] != type(uint).max) {
            _tokenAllowances[owner_][spender] -= tokens;
        }
    }
}
