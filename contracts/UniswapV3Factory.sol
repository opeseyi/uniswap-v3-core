// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './UniswapV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './UniswapV3Pool.sol';

/// @title Canonical Uniswap V3 factory
/// @notice Deploys Uniswap V3 pools and manages ownership and control over pool protocol fees
contract UniswapV3Factory is IUniswapV3Factory, UniswapV3PoolDeployer, NoDelegateCall {
    /// @inheritdoc IUniswapV3Factory
    // Return owner of the pool
    address public override owner;

    /// @inheritdoc IUniswapV3Factory
    // mapps the fee to the tick
    mapping(uint24 => int24) public override feeAmountTickSpacing;

    /// @inheritdoc IUniswapV3Factory
    // maps tokenA => tokenB => fee => created pool address
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // Note 500 indicate 0.05%
        feeAmountTickSpacing[500] = 10;
        emit FeeAmountEnabled(500, 10);
        // Note 3000 indicate 0.3%
        feeAmountTickSpacing[3000] = 60;
        emit FeeAmountEnabled(3000, 60);
        // Note 10000 indicate 1%
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    /// @notice Creates a pool for the given two tokens and fee
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param fee The desired fee for the pool
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. tickSpacing is retrieved
    /// from the fee. The call will revert if the pool already exists, the fee is invalid, or the token arguments
    /// are invalid.
    /// @return pool The address of the newly created pool
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        // Check that tokenA and tokenB is different
        require(tokenA != tokenB);
        // INdicate direction of swap
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // Checks that token0 is not the zerith address
        require(token0 != address(0));
        // This get the thickspacing depending on the fee
        int24 tickSpacing = feeAmountTickSpacing[fee];
        // Checks that the tickspacing is not zerp
        require(tickSpacing != 0);
        // This check that this pool has not been created
        require(getPool[token0][token1][fee] == address(0));
        // This deploy the pool with UniswapV3PoolDeployer function "deploy"
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        // this set the getPoll mapping to the pool address
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IUniswapV3Factory
    /// @notice Updates the owner of the factory
    /// @dev Must be called by the current owner
    /// @param _owner The new owner of the factory
    function setOwner(address _owner) external override {
        // require that the owner is msg.sender
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        // reassign the owner to _owner
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    /// @notice Enables a fee amount with the given tickSpacing
    /// @dev Fee amounts may never be removed once enabled
    /// @param fee The fee amount to enable, denominated in hundredths of a bip (i.e. 1e-6)
    /// @param tickSpacing The spacing between ticks to be enforced for all pools created with the given fee amount
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
