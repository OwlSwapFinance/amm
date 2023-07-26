module owlswap_amm::pool {

    use sui::tx_context::{TxContext, sender};
    use sui::object::{ID, UID};
    use sui::object;
    use sui::transfer;
    use sui::coin::{Coin};
    use sui::balance::{Balance, Supply};
    use sui::balance;
    use sui::coin;
    use owlswap_amm::maths;
    use sui::clock::{Clock, timestamp_ms};
    use owlswap_amm::tools;
    use sui::table::Table;
    use sui::table;

    const U64_MAX: u64 = 18446744073709551615;
    /// Minimal liquidity.
    const MINIMAL_LIQUIDITY: u64 = 1000;
    /// Current fee is 0.2%
    const FEE_TRANSACTION: u32 = 20;
    /// The integer scaling setting for fees calculation.
    const FEE_SCALE: u32 = 10000;
    /// The max value that can be held in one of the Balances of
    /// a Pool. U64 MAX / FEE_SCALE
    const MAX_POOL_VALUE: u64 = {
        18446744073709551615 / 10000
    };


    const E_NOT_AUTHORIZED: u64 = 99;

    const E_DIVIDE_BY_ZERO: u64 = 500;
    const E_U64_OVERFLOW: u64 = 501;


    const E_LIQUID_NOT_ENOUGH: u64 = 505;
    const E_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 506;
    const E_POOL_FULL: u64 = 507;
    const E_REMOVE_OUT_ERROR: u64 = 508;
    const E_RESERVES_EMPTY: u64 = 509;
    const E_MIN_OUT_LIMIT: u64 = 510;
    const E_WITHDRAW_FEE_INSUFFICIENT: u64 = 511;
    const E_POOL_FEE_RATE_ERROR: u64 = 512;
    const E_TRADING_NOT_START: u64 = 513;
    const E_TRADING_TIME_ALREADY_SET: u64 = 520;

    const E_DONT_CHANGE_POOL_FEE: u64 = 530;
    const E_YOU_ARE_BLACKLIST: u64 = 531;
    const E_CANT_SET_WHITELIST: u64 = 532;
    const E_CANT_SET_BLACKLIST: u64 = 533;

    struct LP<phantom X, phantom Y> has drop {}

    struct Pool<phantom X, phantom Y> has key {
        id: UID,
        owner: address,

        x_reserve: Balance<X>,
        x_coin_scale: u64,
        x_pool_rate: u32,
        x_pool_fee: Balance<X>,
        x_transaction_fee: Balance<X>,

        y_reserve: Balance<Y>,
        y_coin_scale: u64,
        y_pool_rate: u32,
        y_pool_fee: Balance<Y>,
        y_transaction_fee: Balance<Y>,

        lp_supply: Supply<LP<X, Y>>,
        min_liquidity: Balance<LP<X, Y>>,

        tx_count: u64,

        create_time: u64,
        trading_time: u64,

        can_change_fee: bool,
        can_whitelist: bool,
        whitelist:Table<address,bool>,
        can_blacklist: bool,
        blacklist:Table<address,bool>,
    }

    public fun create_pool<X, Y>(
        clock: &Clock,
        x_coin_scale: u64,
        x_pool_rate: u32,
        y_coin_scale: u64,
        y_pool_rate: u32,
        trading_time: u64,
        can_change_fee: bool,
        can_whitelist: bool,
        can_blacklist: bool,
        ctx: &mut TxContext): ID {
        let pool = Pool<X, Y> {
            id: object::new(ctx),
            owner: sender(ctx),
            x_reserve: balance::zero<X>(),
            x_coin_scale,
            x_pool_rate,
            x_pool_fee: balance::zero<X>(),
            x_transaction_fee: balance::zero<X>(),
            y_reserve: balance::zero<Y>(),
            y_coin_scale,
            y_pool_rate,
            y_pool_fee: balance::zero<Y>(),
            y_transaction_fee: balance::zero<Y>(),
            lp_supply: balance::create_supply(LP<X, Y> {}),
            min_liquidity: balance::zero<LP<X, Y>>(),
            tx_count: 0,
            create_time: timestamp_ms(clock),
            trading_time,
            can_change_fee,
            can_whitelist,
            whitelist: table::new(ctx),
            can_blacklist,
            blacklist: table::new(ctx),
        };

        let pool_id = object::id(&pool);
        transfer::share_object(pool);
        pool_id
    }

    public fun add_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        x_coin: Coin<X>,
        x_min: u64,
        y_coin: Coin<Y>,
        y_min: u64,
        ctx: &mut TxContext): (Coin<LP<X, Y>>, u64, u64, u64) {
        let (x_reserve_value, y_reserve_value, lp_supply_value) = get_reserves_size(pool);

        let x_balance = coin::into_balance(x_coin);
        let x_deposit_value = balance::value(&x_balance);

        let y_balance = coin::into_balance(y_coin);
        let y_deposit_value = balance::value(&y_balance);

        let (x_optimal_value, y_optimal_value) = tools::calc_optimal_values(
            x_deposit_value,
            y_deposit_value,
            x_min,
            y_min,
            x_reserve_value,
            y_reserve_value
        );

        let provide_liq = if (lp_supply_value == 0) {
            let initial_liq = maths::sqrt(maths::mul_to_u128(x_optimal_value, y_optimal_value));
            assert!(initial_liq > MINIMAL_LIQUIDITY, E_LIQUID_NOT_ENOUGH);
            let min_liquidity = balance::increase_supply(&mut pool.lp_supply, MINIMAL_LIQUIDITY);
            balance::join(&mut pool.min_liquidity, min_liquidity);

            initial_liq - MINIMAL_LIQUIDITY
        } else {
            let x_liquidity = (lp_supply_value as u128) * (x_optimal_value as u128) / (x_reserve_value as u128);
            let y_liquidity = (lp_supply_value as u128) * (y_optimal_value as u128) / (y_reserve_value as u128);
            if (x_liquidity < y_liquidity) {
                assert!(x_liquidity < (U64_MAX as u128), E_U64_OVERFLOW);
                (x_liquidity as u64)
            } else {
                assert!(y_liquidity < (U64_MAX as u128), E_U64_OVERFLOW);
                (y_liquidity as u64)
            }
        };

        assert!(provide_liq > 0, E_INSUFFICIENT_LIQUIDITY_MINTED);

        if (x_optimal_value < x_deposit_value) {
            let coin_amount = coin::from_balance(
                balance::split(&mut x_balance, x_deposit_value - x_optimal_value),
                ctx
            );
            transfer::public_transfer(coin_amount, sender(ctx));
        };
        if (y_optimal_value < y_deposit_value) {
            let coin_amount = coin::from_balance(
                balance::split(&mut y_balance, y_deposit_value - y_optimal_value),
                ctx
            );
            transfer::public_transfer(coin_amount, sender(ctx));
        };

        let x_new_reserve = balance::join(&mut pool.x_reserve, x_balance);
        let y_new_reserve = balance::join(&mut pool.y_reserve, y_balance);

        assert!(x_new_reserve < MAX_POOL_VALUE, E_POOL_FULL);
        assert!(y_new_reserve < MAX_POOL_VALUE, E_POOL_FULL);

        let lp_balance = balance::increase_supply(&mut pool.lp_supply, provide_liq);

        pool.tx_count = pool.tx_count + 1;

        (coin::from_balance(lp_balance, ctx), x_optimal_value, y_optimal_value, pool.tx_count)
    }

    public fun remove_liqudity<X, Y>(
        pool: &mut Pool<X, Y>,
        lp_coin: Coin<LP<X, Y>>,
        ctx: &mut TxContext
    ): (u64, Coin<X>, Coin<Y>, u64) {
        let lp_value = coin::value(&lp_coin);

        let (x_reserve, y_reserve, lp_supply) = get_reserves_size(pool);

        let x_out_value = maths::mul_div(x_reserve, lp_value, lp_supply);
        let y_out_value = maths::mul_div(y_reserve, lp_value, lp_supply);

        assert!(x_out_value > 0 && y_out_value > 0, E_REMOVE_OUT_ERROR);

        let burned_amount = balance::decrease_supply(&mut pool.lp_supply, coin::into_balance(lp_coin));

        (burned_amount, coin::take(&mut pool.x_reserve, x_out_value, ctx), coin::take(
            &mut pool.y_reserve,
            y_out_value,
            ctx
        ), pool.tx_count)
    }

    public fun swap_x_to_y<X, Y>(
        pool: &mut Pool<X, Y>,
        clock_target: &Clock,
        x_coin: Coin<X>,
        y_min_out: u64,
        ctx: &mut TxContext
    ): (Coin<Y>, u64) {
        if (pool.trading_time > 0) {
            assert!(pool.trading_time <= timestamp_ms(clock_target), E_TRADING_NOT_START);
        };
        if (pool.can_blacklist) {
            assert!(!table::contains(&pool.blacklist, sender(ctx)), E_YOU_ARE_BLACKLIST);
        };

        let (x_reserve, y_reserve, _) = get_reserves_size(pool);

        assert!(x_reserve > 0 && y_reserve > 0, E_RESERVES_EMPTY);

        let x_in_value = coin::value(&x_coin);

        let x_transaction_fee = tools::get_fee(x_in_value, FEE_TRANSACTION, FEE_SCALE);

        let x_pool_fee = if (pool.x_pool_rate > 0) {
            tools::get_fee(x_in_value, pool.x_pool_rate, FEE_SCALE)
        } else {
            0
        };
        if (x_pool_fee > 0 && pool.can_whitelist) {
            if(table::contains(&pool.whitelist, sender(ctx))) {
                x_pool_fee = 0;
            }
        };

        let x_in_real_value = x_in_value - x_transaction_fee - x_pool_fee;
        let y_out_value = tools::calculate_amount_out(x_reserve, y_reserve, x_in_real_value);
        assert!(y_out_value >= y_min_out, E_MIN_OUT_LIMIT);

        let x_balance = coin::into_balance(x_coin);
        if (x_transaction_fee > 0) {
            balance::join(&mut pool.x_transaction_fee, balance::split(&mut x_balance, x_transaction_fee));
        };
        if (x_pool_fee > 0) {
            balance::join(&mut pool.x_pool_fee, balance::split(&mut x_balance, x_pool_fee));
        };

        balance::join(&mut pool.x_reserve, x_balance);

        let y_out_coin = coin::take(&mut pool.y_reserve, y_out_value, ctx);
        let (x_new_reserve, y_new_reserve, _lp) = get_reserves_size(pool);
        tools::check_reserve_is_increased(x_reserve, y_reserve, x_new_reserve, y_new_reserve);


        if (pool.trading_time == 0) {
            pool.trading_time = timestamp_ms(clock_target);
        };

        pool.tx_count = pool.tx_count + 1;

        (y_out_coin, pool.tx_count)
    }

    public fun swap_y_to_x<X, Y>(
        pool: &mut Pool<X, Y>,
        clock_target: &Clock,
        y_coin: Coin<Y>,
        x_min_out: u64,
        ctx: &mut TxContext
    ): (Coin<X>, u64) {
        if (pool.trading_time > 0) {
            assert!(pool.trading_time <= timestamp_ms(clock_target), E_TRADING_NOT_START);
        };
        if (pool.can_blacklist) {
            assert!(!table::contains(&pool.blacklist, sender(ctx)), E_YOU_ARE_BLACKLIST);
        };


        let (x_reserve, y_reserve, _) = get_reserves_size(pool);

        assert!(x_reserve > 0 && y_reserve > 0, E_RESERVES_EMPTY);

        let y_in_value = coin::value(&y_coin);

        let y_transaction_fee = tools::get_fee(y_in_value, FEE_TRANSACTION, FEE_SCALE);
        let y_pool_fee = if (pool.y_pool_rate > 0) {
            tools::get_fee(y_in_value, pool.x_pool_rate, FEE_SCALE)
        } else {
            0
        };
        if (y_pool_fee > 0 && pool.can_whitelist) {
            if(table::contains(&pool.whitelist, sender(ctx))) {
                y_pool_fee = 0;
            }
        };

        let y_in_real_value = y_in_value - y_transaction_fee - y_pool_fee;

        let x_out_value = tools::calculate_amount_out(y_reserve, x_reserve, y_in_real_value);

        assert!(x_out_value >= x_min_out, E_MIN_OUT_LIMIT);

        let y_balance = coin::into_balance(y_coin);
        if (y_transaction_fee > 0) {
            balance::join(&mut pool.y_transaction_fee, balance::split(&mut y_balance, y_transaction_fee));
        };
        if (y_pool_fee > 0) {
            balance::join(&mut pool.y_pool_fee, balance::split(&mut y_balance, y_pool_fee));
        };

        balance::join(&mut pool.y_reserve, y_balance);

        let x_out_coin = coin::take(&mut pool.x_reserve, x_out_value, ctx);

        let (x_new_reserve, y_new_reserve, _lp) = get_reserves_size(pool);
        tools::check_reserve_is_increased(x_reserve, y_reserve, x_new_reserve, y_new_reserve);

        if (pool.trading_time == 0) {
            pool.trading_time = timestamp_ms(clock_target);
        };

        pool.tx_count = pool.tx_count + 1;

        (x_out_coin, pool.tx_count)
    }

    //==============Pool Management Method==========================

    public fun update_pool_fee<X, Y>(
        pool: &mut Pool<X, Y>,
        x_fee_rate: u32,
        y_fee_rate: u32,
        ctx: &mut TxContext): (u32, u32, u32, u32) {
        check_owner(pool, ctx);

        assert!(pool.can_change_fee, E_DONT_CHANGE_POOL_FEE);

        assert!(x_fee_rate < 1000, E_POOL_FEE_RATE_ERROR);
        assert!(y_fee_rate < 1000, E_POOL_FEE_RATE_ERROR);

        let old_x_pool_rate = pool.x_pool_rate;
        let old_y_pool_rate = pool.y_pool_rate;
        pool.x_pool_rate = x_fee_rate;
        pool.y_pool_rate = y_fee_rate;

        (old_x_pool_rate, old_y_pool_rate, x_fee_rate, y_fee_rate)
    }

    public fun update_owner<X, Y>(pool: &mut Pool<X, Y>, new_owner: address, ctx: &mut TxContext): address {
        check_owner(pool, ctx);
        let old_owner = pool.owner;
        pool.owner = new_owner;
        return old_owner
    }

    public fun withdraw_pool_fee<X, Y>(pool: &mut Pool<X, Y>, ctx: &mut TxContext): (Coin<X>, Coin<Y>) {
        check_owner(pool, ctx);

        let x_value = balance::value(&pool.x_pool_fee);
        let y_value = balance::value(&pool.y_pool_fee);

        assert!(x_value > 0 && y_value > 0, E_WITHDRAW_FEE_INSUFFICIENT);

        let x_fee = balance::split(&mut pool.x_pool_fee, x_value);
        let y_fee = balance::split(&mut pool.y_pool_fee, y_value);

        (coin::from_balance(x_fee, ctx), coin::from_balance(y_fee, ctx))
    }

    public fun withdraw_transaction_fee<X, Y>(pool: &mut Pool<X, Y>, ctx: &mut TxContext): (Coin<X>, Coin<Y>) {
        let x_value = balance::value(&pool.x_transaction_fee);
        let y_value = balance::value(&pool.y_transaction_fee);

        assert!(x_value > 0 && y_value > 0, E_WITHDRAW_FEE_INSUFFICIENT);

        let x_fee = balance::split(&mut pool.x_transaction_fee, x_value);
        let y_fee = balance::split(&mut pool.y_transaction_fee, y_value);

        (coin::from_balance(x_fee, ctx), coin::from_balance(y_fee, ctx))
    }

    public fun set_trading_time<X, Y>(pool: &mut Pool<X, Y>, clock_target: &Clock, trading_time: u64, ctx:&mut TxContext) {
        check_owner(pool, ctx);
        assert!(
            (pool.trading_time == 0) || (pool.trading_time > timestamp_ms(clock_target)),
            E_TRADING_TIME_ALREADY_SET
        );
        pool.trading_time = trading_time;
    }

    public fun set_blacklist<X, Y>(pool: &mut Pool<X, Y>, action: u8, target: address, ctx:&mut TxContext) {
        check_owner(pool, ctx);
        assert!(pool.can_blacklist, E_CANT_SET_BLACKLIST);
        set_table_list(&mut pool.blacklist, action, target);
    }
    public fun set_whilelist<X, Y>(pool: &mut Pool<X, Y>, action: u8, target: address, ctx:&mut TxContext) {
        check_owner(pool, ctx);
        assert!(pool.can_whitelist, E_CANT_SET_WHITELIST);
        set_table_list(&mut pool.whitelist, action, target);
    }

    //==============Private Method==========================


    fun check_owner<X, Y>(pool: &mut Pool<X, Y>, ctx: &mut TxContext) {
        assert!(pool.owner == sender(ctx), E_NOT_AUTHORIZED);
    }

    fun set_table_list(list: &mut Table<address, bool>, action: u8, target:address) {
        let is_found = table::contains(list, target);
        if(action == 1) {
            if(!is_found) {
                table::add(list, target, true);
            }
        } else if(action == 2) {
            if(is_found) {
                table::remove(list, target);
            }
        };
    }

    fun get_reserves_size<X, Y>(pool: &mut Pool<X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.x_reserve),
            balance::value(&pool.y_reserve),
            balance::supply_value(&pool.lp_supply)
        )
    }
}