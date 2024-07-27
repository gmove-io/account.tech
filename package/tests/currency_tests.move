#[test_only]
module kraken::currency_tests;

use sui::{
    url,
    sui::SUI,
    coin::{Self, Coin},
    test_utils::destroy,
    test_scenario::most_recent_receiving_ticket
};
use kraken::{
    owned,
    currency,
    test_utils::start_world
};

const OWNER: address = @0xBABE;

public struct CURRENCY_TESTS has drop {}

public struct Auth has drop, copy {}

#[test]
fun mint_end_to_end() {
    let mut world = start_world();
    let addr = world.multisig().addr();
    let key = b"mint proposal".to_string();

    let cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    world.lock_treasury_cap(cap);

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&addr.to_id());
    world.propose_mint<SUI>(key, 100);
    world.approve_proposal(key);

    let mut treasury_lock = world.borrow_treasury_cap<SUI>(receiving_lock);
    let executable = world.execute_proposal(key);
    currency::execute_mint(executable, &mut treasury_lock, world.scenario().ctx());
    currency::put_back_cap(treasury_lock);

    world.scenario().next_tx(OWNER);
    let minted_coin = world.scenario().take_from_address<Coin<SUI>>(addr);
    assert!(minted_coin.value() == 100);

    destroy(minted_coin);
    world.end();
}

#[test]
fun burn_end_to_end() {
    let mut world = start_world();
    let key = b"burn proposal".to_string();

    let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    let sui_coin = cap.mint<SUI>(100, world.scenario().ctx());
    transfer::public_transfer(sui_coin, world.multisig().addr());

    world.scenario().next_tx(OWNER);
    let receiving_coin = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    world.lock_treasury_cap(cap);
    
    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    world.propose_burn<SUI>(key, receiving_coin.receiving_object_id(), 100);
    world.approve_proposal(key);

    let mut treasury_lock = world.borrow_treasury_cap<SUI>(receiving_lock);
    let executable = world.execute_proposal(key);
    currency::execute_burn(executable, world.multisig(), receiving_coin, &mut treasury_lock);

    currency::put_back_cap(treasury_lock);
    world.end();
}

#[test]
fun update_metadata_end_to_end() {
    let mut world = start_world();
    let key = b"update proposal".to_string();

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

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    world.propose_update(
        key, 
        option::some(b"test name".to_string()), 
        option::some(b"test symbol".to_string()), 
        option::some(b"test description".to_string()), 
        option::some(b"https://something.png".to_string()), 
    );
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let treasury_lock = world.borrow_treasury_cap<CURRENCY_TESTS>(receiving_lock);
    currency::execute_update(&mut executable,&treasury_lock, &mut coin_metadata);
    currency::put_back_cap(treasury_lock);
    currency::complete_update(executable);

    assert!(coin_metadata.get_name() == b"test name".to_string());
    assert!(coin_metadata.get_description() == b"test description".to_string());
    assert!(coin_metadata.get_symbol() == b"test symbol".to_ascii_string());
    assert!(coin_metadata.get_icon_url() == option::some(url::new_unsafe_from_bytes(b"https://something.png")));

    destroy(coin_metadata);
    world.end();
}

#[test, expected_failure(abort_code = currency::ENoChange)]
fun update_error_no_change() {
    let mut world = start_world();
    let key = b"update proposal".to_string();

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

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    world.propose_update(
        key, 
        option::none(), 
        option::none(), 
        option::none(), 
        option::none(), 
    );
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let treasury_lock = world.borrow_treasury_cap<CURRENCY_TESTS>(receiving_lock);
    currency::execute_update(&mut executable,&treasury_lock, &mut coin_metadata);
    currency::put_back_cap(treasury_lock);
    currency::complete_update(executable);

    destroy(coin_metadata);
    world.end();
}

#[test, expected_failure(abort_code = currency::EWrongValue)]
fun burn_error_wrong_value() {
    let mut world = start_world();
    let key = b"burn proposal".to_string();

    let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    let sui_coin =  cap.mint<SUI>(101, world.scenario().ctx()); // wrong burn value
    transfer::public_transfer(sui_coin, world.multisig().addr());
    
    world.scenario().next_tx(OWNER);
    let receiving_coin = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    world.lock_treasury_cap(cap);

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    world.propose_burn<SUI>(key, receiving_coin.receiving_object_id(), 100);
    world.approve_proposal(key);

    let mut treasury_lock = world.borrow_treasury_cap<SUI>(receiving_lock);
    let executable = world.execute_proposal(key);
    currency::execute_burn(executable, world.multisig(), receiving_coin, &mut treasury_lock);
    currency::put_back_cap(treasury_lock);

    world.end();
}

#[test, expected_failure(abort_code = currency::EMintNotExecuted)]
fun destroy_mint_error_mint_not_executed() {
    let mut world = start_world();
    let key = b"mint proposal".to_string();

    let cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    world.lock_treasury_cap(cap);

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    let proposal = world.create_proposal(
        Auth {},
        key, 
        0, 
        0, 
        b"description".to_string(), 
    );
    currency::new_mint<SUI>(proposal, 100);
    world.approve_proposal(key);

    world.scenario().next_tx(OWNER);
    let treasury_lock = world.borrow_treasury_cap<SUI>(receiving_lock);
    let mut executable = world.execute_proposal(key);
    currency::destroy_mint<SUI, Auth>(&mut executable, Auth {});
    currency::put_back_cap(treasury_lock);

    destroy(executable);
    world.end();    
}

#[test, expected_failure(abort_code = currency::EBurnNotExecuted)]
fun destroy_burn_error_burn_not_executed() {
    let mut world = start_world();
    let key = b"burn proposal".to_string();

    let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    let sui_coin =  cap.mint<SUI>(100, world.scenario().ctx());
    transfer::public_transfer(sui_coin, world.multisig().addr());

    world.scenario().next_tx(OWNER);
    let receiving_coin = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    world.lock_treasury_cap(cap);

    let proposal = world.create_proposal(
        Auth {},
        key, 
        0, 
        0, 
        b"description".to_string(), 
    );
    owned::new_withdraw(proposal, vector[receiving_coin.receiving_object_id()]);
    currency::new_burn<SUI>(proposal, 100);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let coin = owned::withdraw<Coin<SUI>, Auth>(
        &mut executable, 
        world.multisig(), 
        receiving_coin, 
        Auth {}, 
        0
    );
    owned::destroy_withdraw(&mut executable, Auth {});
    currency::destroy_burn<SUI, Auth>(&mut executable, Auth {});

    destroy(coin);
    destroy(executable);
    world.end();    
}