module owlswap_amm::events {

    use sui::event;
    use sui::object::{ID};
    use std::string::String;
    use sui::event::emit;
    friend owlswap_amm::pool;

    struct PoolCreated has drop, copy {
        pool_id: ID,
        x_token: String,
        y_token: String,
    }

    public fun emit_pool_created(pool_id: ID, x_token: String, y_token: String) {
        event::emit(PoolCreated{
            pool_id,
            x_token,
            y_token
        });
    }

    struct LiquidityAdded has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        lp_amount: u64,
        index: u64
    }

    public fun emit_liqudity_added(pool_id: ID, x_amount: u64, y_amount: u64, lp_amount: u64, index: u64) {
        event::emit(LiquidityAdded{
            pool_id,
            x_amount,
            y_amount,
            lp_amount,
            index,
        })
    }

    struct LiquidityRemoved has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        lp_amount: u64,
        index: u64
    }

    public fun emit_liqudity_removed(pool_id: ID, x_amount: u64, y_amount: u64, lp_amount: u64, index: u64) {
        event::emit(LiquidityRemoved{
            pool_id,
            x_amount,
            y_amount,
            lp_amount,
            index
        })
    }

    struct Swapped has drop, copy {
        pool_id: ID,
        sender: address,
        x_in: u64,
        x_out: u64,
        y_in: u64,
        y_out: u64,
        index: u64
    }

    public fun emit_swap(pool_id: ID, sender: address, x_in: u64, x_out: u64, y_in: u64, y_out: u64, index: u64) {
        emit(Swapped{
            pool_id,
            sender,
            x_in,
            x_out,
            y_in,
            y_out,
            index
        })
    }

    struct TransactionFeeWithdrawal has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        recipient: address
    }

    public fun emit_transaction_fee_withdraw(pool_id: ID, x_amount: u64, y_amount: u64, recipient: address) {
        event::emit(TransactionFeeWithdrawal{
            pool_id,
            x_amount,
            y_amount,
            recipient
        });
    }

    struct PoolFeeWithdraw has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        recipient: address
    }
    public fun emit_pool_fee_withdraw(pool_id: ID, x_amount: u64, y_amount: u64, recipient: address) {
        event::emit(PoolFeeWithdraw{
            pool_id,
            x_amount,
            y_amount,
            recipient,
        });
    }

    struct PoolFeeConfigUpdated has drop, copy {
        pool_id: ID,
        old_x_fee: u32,
        old_y_fee: u32,
        new_x_fee: u32,
        new_y_fee: u32,
        time: u64
    }
    public fun emit_pool_fee_config_updated(pool_id: ID, old_x_fee: u32,old_y_fee: u32, new_x_fee: u32, new_y_fee: u32, time: u64) {
        event::emit(PoolFeeConfigUpdated{
            pool_id,
            old_x_fee,
            old_y_fee,
            new_x_fee,
            new_y_fee,
            time
        });
    }

    struct PoolOwnerUpdated has drop, copy {
        pool_id: ID,
        old_owner: address,
        new_owner: address
    }
    public fun emit_pool_owner_updated(pool_id: ID, old_owner: address, new_owner: address) {
        event::emit(PoolOwnerUpdated{
            pool_id,
            old_owner,
            new_owner
        });
    }

    struct PoolTradingTimeChange has drop, copy {
        pool_id: ID,
        new_time: u64,
    }

    public fun emit_pool_tradingtime_change(pool_id: ID, new_time: u64) {
        event::emit(PoolTradingTimeChange{
            pool_id,
            new_time
        });
    }

    struct PoolWhiteListSet has drop, copy {
        pool_id: ID,
        action: u8,
        target:address
    }

    public fun emit_pool_whitelist_set(pool_id: ID, action: u8, target:address) {
        event::emit(PoolWhiteListSet{
            pool_id,
            action,
            target
        });
    }

    struct PoolBlackListSet has drop, copy {
        pool_id: ID,
        action: u8,
        target:address
    }

    public fun emit_pool_blacklist_set(pool_id: ID, action: u8, target:address) {
        event::emit(PoolBlackListSet{
            pool_id,
            action,
            target
        });
    }

    struct Test has drop, copy{
        time:u64
    }
    public fun test(time: u64) {
        event::emit(Test{time})
    }
}