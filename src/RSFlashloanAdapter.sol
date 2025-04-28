// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/*───────────────────────────────────────────────────────────────────────────*\
│  AAVE V3 interfaces                                                        │
\*───────────────────────────────────────────────────────────────────────────*/
import {IFlashLoanSimpleReceiver} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";

interface IRS   {
    /* the two overloaded `fill` functions on the Rhinestone SpokePool     */
    function fill(
        bytes calldata payload,
        address exclusiveRelayer,
        address[] calldata repaymentAddresses,
        uint256[] calldata repaymentChainIds
    ) external;

    function fill(
        bytes calldata payload,
        address exclusiveRelayer,
        address[] calldata repaymentAddresses,
        uint256[] calldata repaymentChainIds,
        address account,
        bytes calldata initCode
    ) external;
}

/* minimal IERC20 for approvals */
interface IERC20 {
    function approve(address spender, uint256 value) external returns (bool);
}

/*───────────────────────────────────────────────────────────────────────────*\
│   RSFlashLoanAdapter                                                       │
│   - Owned by the relayer key.                                             │
│   - Pulls temporary liquidity from Aave, executes an RS fill, repays.     │
\*───────────────────────────────────────────────────────────────────────────*/
contract RSFlashLoanAdapter is IFlashLoanSimpleReceiver {
    /* --------------------------------------------------------------------- */
    address public immutable owner;         // relayer EOA / hot key
    IPool   public immutable POOL;          // Aave pool on this chain
    IRS     public immutable SPOKE_POOL;    // Rhinestone SpokePool
    IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;

    error NotOwner();
    error InvalidCaller();
    error InvalidInitiator();

    modifier onlyOwner() { 
        if (msg.sender != owner) revert NotOwner();
        _; 
    }

    constructor(IPoolAddressesProvider provider, IRS spokePool) {
        owner       = msg.sender;
        POOL        = IPool(provider.getPool());
        SPOKE_POOL  = spokePool;
        ADDRESSES_PROVIDER = provider;
    }

    /* --------------------------------------------------------------------- */
    /// @notice Entry point called from the RS relayer (solver).
    /// @param  asset      token to borrow for settlement (segment tokenOut)
    /// @param  amount     quantity to borrow
    /// @param  rsCalldata ABI-encoded call to *either* SpokePool.fill variant
    function flashFill(address asset, uint256 amount, bytes calldata rsCalldata)
        external
        onlyOwner
    {
        /* params forwarded into `executeOperation` */
        bytes memory params = abi.encode(rsCalldata);

        /* 0 == no debt, classic flash-loan mode                                 */
        POOL.flashLoanSimple(address(this), asset, amount, params, 0);
    }

    /* --------------------------------------------------------------------- */
    /// @dev Aave callback. Executes intent fill then repays (+premium).
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external
        override
        returns (bool)
    {
        if (msg.sender != address(POOL)) revert InvalidCaller();
        if (initiator != address(this)) revert InvalidInitiator();

        /* ------------------------------------------------------------------ */
        /* 1. Approve the SpokePool to pull the borrowed token for settlement */
        IERC20(asset).approve(address(SPOKE_POOL), type(uint256).max);

        /* 2. Perform the actual intent fill                                  */
        bytes memory rsCall = abi.decode(params, (bytes));

        (bool ok, bytes memory reason) = address(SPOKE_POOL).call(rsCall);
        if (!ok) {
            assembly {
                revert(add(reason, 32), mload(reason))
            }
        }

        /* ------------------------------------------------------------------ */
        /* 3. Repay Aave (amount + fee).  Fee is paid from relayer revenue.   */
        uint256 repayment = amount + premium;
        IERC20(asset).approve(address(POOL), repayment);

        return true;    // signals success to Aave
    }
}
