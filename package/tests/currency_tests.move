#[test_only]
module kraken::currency_tests {

    use sui::{
        coin,
        sui::SUI,
        test_scenario::receiving_ticket_by_id
    };

    use kraken::{
        currency,
        test_utils::start_world
    };

    const OWNER: address = @0xBABE;

    #[test]
    fun test_mint() {
        let mut world = start_world();

        let key = b"mint".to_string();

        let cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 

        let lock_id = world.lock_treasury_cap(cap);

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

        let coin_id = object::id(&sui_coin);

        transfer::public_transfer(sui_coin, world.multisig().addr());

        let lock_id = world.lock_treasury_cap(cap);

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
}