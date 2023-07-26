module owlswap_amm::control {

    use sui::object::{UID, ID, id};
    use sui::table::Table;
    use std::string::String;
    use sui::tx_context::{TxContext, sender};
    use sui::object;
    use sui::table;
    use sui::transfer;
    use std::type_name::{get, into_string};
    use std::ascii::{into_bytes};
    use std::string;
    use owlswap_amm::pool::{Self, Pool};
    use owlswap_amm::events;
    use sui::coin;
    use std::vector;

    friend owlswap_amm::router;

    const VERSION: u32 = 1;

    const E_NOT_AUTHORIZED: u64 = 201;
    const E_VERSION: u64 = 202;
    const E_WRONG_VERSION: u64 = 203;

    struct Store has key {
        id: UID,
        version: u32,
        master: address,
        pools: Table<String, ID>,
        owners: Table<address, vector<ID>>,
        count: u64,
    }

    fun init(ctx: &mut TxContext) {
        let store = Store {
            id: object::new(ctx),
            master: sender(ctx),
            version: VERSION,
            pools: table::new<String, ID>(ctx),
            owners: table::new<address, vector<ID>>(ctx),
            count: 0,
        };
        transfer::share_object(store);
    }

    entry fun transfer_authority(store: &mut Store, new_master: address, ctx: &mut TxContext) {
        check_master(store, ctx);
        store.master = new_master;
    }

    public(friend) fun add<X, Y>(store: &mut Store, pool_id: ID, owner: address) {
        let lp_name = get_name_x_y<X, Y>();
        table::add(&mut store.pools, lp_name, pool_id);
        store.count = store.count + 1;
        set_pool_owner(store, owner, pool_id);
    }

    fun set_pool_owner(store: &mut Store, owner: address, pool_id: ID) {
        if (!table::contains(&store.owners, owner)) {
            let target = vector::empty<ID>();
            vector::push_back(&mut target, pool_id);
            table::add(&mut store.owners, owner, target);
        } else {
            let target = table::borrow_mut(&mut store.owners, owner);
            vector::push_back(target, pool_id);
        };
    }

    public(friend) fun exist<X, Y>(store: &mut Store): bool {
        table::contains(&mut store.pools, get_name_x_y<X, Y>())
    }

    public fun owner_change(store: &mut Store, pool_id: ID, old_owner: address, new_owner: address) {
        if (table::contains(&mut store.owners, old_owner)) {
            let target = table::borrow_mut(&mut store.owners, old_owner);
            if (vector::contains(target, &pool_id)) {
                let (result, index) = vector::index_of(target, &pool_id);
                if (result) {
                    vector::remove(target, index);
                }
            }
        };
        set_pool_owner(store, new_owner, pool_id);
    }


    public fun get_name_x_y<X, Y>(): String {
        let name_x = get_name<X>();
        let name_y = get_name<Y>();
        string::append_utf8(&mut name_x, b"-");
        string::append(&mut name_x, name_y);
        name_x
    }

    public fun get_name<Coin>(): String {
        let name = get<Coin>();
        let str = string::utf8(b"");
        string::append_utf8(&mut str, into_bytes(into_string(name)));
        str
    }

    fun check_master(store: &mut Store, ctx: &mut TxContext) {
        assert!(store.master == sender(ctx), E_NOT_AUTHORIZED);
    }
    public fun check_version(store: &mut Store) {
        assert!(store.version == VERSION, E_WRONG_VERSION);
    }

    entry fun withdraw<X, Y>(store: &mut Store, pool: &mut Pool<X, Y>, recipient: address, ctx: &mut TxContext) {
        check_version(store);
        check_master(store, ctx);

        let (x_coin, y_coin) = pool::withdraw_transaction_fee(pool, ctx);

        let x_value = coin::value(&x_coin);
        let y_value = coin::value(&y_coin);

        transfer::public_transfer(x_coin, recipient);
        transfer::public_transfer(y_coin, recipient);

        events::emit_transaction_fee_withdraw(id(pool), x_value, y_value, recipient);
    }


    //Merge Upgrade
    entry fun migrate(store: &mut Store, ctx:&mut TxContext) {
        check_master(store, ctx);
        assert!(store.version < VERSION, E_VERSION);
        store.version = VERSION;
    }
}