#[test_only]
module kraken::currency_tests {

    use sui::{
        url,
        sui::SUI,
        coin::{Self, Coin},
        test_utils::{destroy, assert_eq},
        test_scenario::receiving_ticket_by_id
    };

    use kraken::{
        owned,
        currency,
        test_utils::start_world
    };

    const OWNER: address = @0xBABE;

    public struct CURRENCY_TESTS has drop {}

    public struct Witness has drop, copy {}

    #[test]
    fun test_mint() {
        let mut world = start_world();

        let key = b"mint".to_string();

        let cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 

        world.lock_treasury_cap(cap);

        let effects = world.scenario().next_tx(OWNER);

        // We created one new object
        let lock_id = effects.created()[0];

        world.propose_mint<SUI>(
            key, 
            10, 
            1, 
            b"description".to_string(), 
            100
        );

        world.scenario().next_tx(OWNER);

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);

        world.clock().set_for_testing(11);

        let mut treasury_lock = world.borrow_treasury_cap<SUI>(receiving_ticket_by_id(lock_id));

        let executable = world.execute_proposal(key);

        currency::execute_mint(executable, &mut treasury_lock, world.scenario().ctx());

        currency::put_back_cap(treasury_lock);

        world.end();
    }

    #[test]
    fun test_burn() {
        let mut world = start_world();

        let key = b"burn".to_string();

        let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 

        let sui_coin =  cap.mint<SUI>(100, world.scenario().ctx());

        world.lock_treasury_cap(cap);

        let coin_id = object::id(&sui_coin);

        transfer::public_transfer(sui_coin, world.multisig().addr());

        let effects = world.scenario().next_tx(OWNER);

        // We created one new object
        let lock_id = effects.created()[0];

        world.propose_burn<SUI>(
            key, 
            7, 
            1, 
            b"description".to_string(), 
            coin_id, 
            100
        );

        world.scenario().next_tx(OWNER);

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);

        world.clock().set_for_testing(8);

        let mut treasury_lock = world.borrow_treasury_cap<SUI>(receiving_ticket_by_id(lock_id));

        let executable = world.execute_proposal(key);

        currency::execute_burn(executable, world.multisig(), receiving_ticket_by_id(coin_id), &mut treasury_lock);

        currency::put_back_cap(treasury_lock);

        world.end();
    }

    #[test]
    fun test_update() {
        let mut world = start_world();

        let key = b"update".to_string();

        let (treasury_cap, mut coin_metadata) = coin::create_currency(
            CURRENCY_TESTS {}, 
            9, 
            b"symbol", 
            b"name", 
            b"description", 
            option::none(), 
            world.scenario().ctx()
        );

        world.lock_treasury_cap(treasury_cap);

        let effects = world.scenario().next_tx(OWNER);

        // We created one new object
        let lock_id = effects.created()[0];

        world.propose_update(
            key, 
            8, 
            2, 
            b"update the metadata".to_string(), 
            option::some(b"test name".to_string()), 
            option::some(b"test symbol".to_string()), 
            option::some(b"test description".to_string()), 
            option::some(b"https://something.png".to_string()), 
        );

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(8);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let treasury_lock = world.borrow_treasury_cap<CURRENCY_TESTS>(receiving_ticket_by_id(lock_id));

        currency::execute_update(&mut executable,&treasury_lock, &mut coin_metadata);
    
        currency::put_back_cap(treasury_lock);

        currency::complete_update(executable);

        assert_eq(coin_metadata.get_name(), b"test name".to_string());
        assert_eq(coin_metadata.get_description(), b"test description".to_string());
        assert_eq(coin_metadata.get_symbol(), b"test symbol".to_ascii_string());
        assert_eq(coin_metadata.get_icon_url(), option::some(url::new_unsafe_from_bytes(b"https://something.png")));

        destroy(coin_metadata);
        world.end();
    }

    #[test]
    #[expected_failure(abort_code = currency::ENoChange)]
    fun test_update_error_no_change() {
        let mut world = start_world();

        let key = b"update".to_string();

        let (treasury_cap, mut coin_metadata) = coin::create_currency(
            CURRENCY_TESTS {}, 
            9, 
            b"symbol", 
            b"name", 
            b"description", 
            option::none(), 
            world.scenario().ctx()
        );

        world.lock_treasury_cap(treasury_cap);

        let effects = world.scenario().next_tx(OWNER);

        // We created one new object
        let lock_id = effects.created()[0];

        world.propose_update(
            key, 
            8, 
            2, 
            b"update the metadata".to_string(), 
            option::none(), 
            option::none(), 
            option::none(), 
            option::none(), 
        );

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(8);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let treasury_lock = world.borrow_treasury_cap<CURRENCY_TESTS>(receiving_ticket_by_id(lock_id));

        currency::execute_update(&mut executable,&treasury_lock, &mut coin_metadata);
    
        currency::put_back_cap(treasury_lock);

        currency::complete_update(executable);

        destroy(coin_metadata);
        world.end();
    }

    #[test]
    #[expected_failure(abort_code = currency::EWrongValue)]
    fun test_burn_error_wrong_value() {
        let mut world = start_world();

        let key = b"burn".to_string();

        let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 

        // wrong burn value
        let sui_coin =  cap.mint<SUI>(101, world.scenario().ctx());

        let coin_id = object::id(&sui_coin);

        transfer::public_transfer(sui_coin, world.multisig().addr());

        world.lock_treasury_cap(cap);

        let effects = world.scenario().next_tx(OWNER);

        let lock_id = effects.created()[1];

        world.propose_burn<SUI>(
            key, 
            7, 
            1, 
            b"description".to_string(), 
            coin_id, 
            100
        );

        world.scenario().next_tx(OWNER);

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);

        world.clock().set_for_testing(8);

        let mut treasury_lock = world.borrow_treasury_cap<SUI>(receiving_ticket_by_id(lock_id));

        let executable = world.execute_proposal(key);

        currency::execute_burn(executable, world.multisig(), receiving_ticket_by_id(coin_id), &mut treasury_lock);

        currency::put_back_cap(treasury_lock);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = currency::EMintNotExecuted)]
    fun test_destroy_mint_error_mint_not_executed() {
        let mut world = start_world();

        let key = b"mint".to_string();

        let cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 

        world.lock_treasury_cap(cap);

        let effects = world.scenario().next_tx(OWNER);

        // We created one new object
        let lock_id = effects.created()[0];

        let proposal = world.create_proposal(
            Witness {},
            key, 
            10, 
            1, 
            b"description".to_string(), 
        );

        currency::new_mint<SUI>(proposal, 100);

        world.scenario().next_tx(OWNER);

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);

        world.clock().set_for_testing(11);

        let treasury_lock = world.borrow_treasury_cap<SUI>(receiving_ticket_by_id(lock_id));

        let mut executable = world.execute_proposal(key);

        currency::destroy_mint<SUI, Witness>(&mut executable, Witness {});

        currency::put_back_cap(treasury_lock);

        destroy(executable);
        world.end();    
    }

    #[test]
    #[expected_failure(abort_code = currency::EBurnNotExecuted)]
    fun test_destroy_burn_error_burn_not_executed() {
        let mut world = start_world();

        let key = b"burn".to_string();

        let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 

        let sui_coin =  cap.mint<SUI>(100, world.scenario().ctx());

        let coin_id = object::id(&sui_coin);

        transfer::public_transfer(sui_coin, world.multisig().addr());

        world.lock_treasury_cap(cap);

        let proposal = world.create_proposal(
            Witness {},
            key, 
            10, 
            1, 
            b"description".to_string(), 
        );

        owned::new_withdraw(proposal, vector[coin_id]);

        currency::new_burn<SUI>(proposal, 100);

        world.scenario().next_tx(OWNER);

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);

        world.clock().set_for_testing(11);

        let mut executable = world.execute_proposal(key);

        let coin = owned::withdraw<Coin<SUI>, Witness>(
            &mut executable, 
            world.multisig(), 
            receiving_ticket_by_id(coin_id), 
            Witness {}, 
            0
        );

        owned::destroy_withdraw(&mut executable, Witness {});

        currency::destroy_burn<SUI, Witness>(&mut executable, Witness {});

        destroy(coin);
        destroy(executable);
        world.end();    
    }
}