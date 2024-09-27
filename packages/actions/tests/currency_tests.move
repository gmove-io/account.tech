#[test_only]
module kraken_actions::currency_tests;

use sui::{
    url,
    sui::SUI,
    coin::{Self, Coin},
    test_utils::destroy,
    test_scenario::most_recent_receiving_ticket
};
use kraken_actions::{
    owned,
    currency,
    actions_test_utils::start_world,
};

const OWNER: address = @0xBABE;

public struct CURRENCY_TESTS has drop {}

public struct Witness has drop, copy {}

#[test]
fun test_mint_end_to_end() {
    let mut world = start_world();
    let addr = world.account().addr();
    let key = b"mint proposal".to_string();

    let cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    world.lock_treasury_cap(cap);

    world.scenario().next_tx(OWNER);
    world.propose_mint<SUI>(key, 100);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    world.execute_mint<SUI>(executable);

    world.scenario().next_tx(OWNER);
    let minted_coin = world.scenario().take_from_address<Coin<SUI>>(addr);
    assert!(minted_coin.value() == 100);

    destroy(minted_coin);
    world.end();
}

#[test]
fun test_burn_end_to_end() {
    let mut world = start_world();
    let key = b"burn proposal".to_string();

    let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    let sui_coin = cap.mint<SUI>(100, world.scenario().ctx());
    transfer::public_transfer(sui_coin, world.account().addr());

    world.scenario().next_tx(OWNER);
    let receiving_coin = most_recent_receiving_ticket(&world.account().addr().to_id());
    world.lock_treasury_cap(cap);
    
    world.scenario().next_tx(OWNER);
    world.propose_burn<SUI>(key, receiving_coin.receiving_object_id(), 100);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    currency::execute_burn<SUI>(executable, world.account(), receiving_coin);

    world.end();
}

#[test]
fun test_update_metadata_end_to_end() {
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
    world.propose_update<CURRENCY_TESTS>(
        key, 
        option::some(b"test name".to_string()), 
        option::some(b"test symbol".to_string()), 
        option::some(b"test description".to_string()), 
        option::some(b"https://something.png".to_string()), 
    );
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    currency::execute_update(executable, world.account(), &mut coin_metadata);

    assert!(coin_metadata.get_name() == b"test name".to_string());
    assert!(coin_metadata.get_description() == b"test description".to_string());
    assert!(coin_metadata.get_symbol() == b"test symbol".to_ascii_string());
    assert!(coin_metadata.get_icon_url() == option::some(url::new_unsafe_from_bytes(b"https://something.png")));

    destroy(coin_metadata);
    world.end();
}

#[test, expected_failure(abort_code = currency::ENoChange)]
fun test_update_error_no_change() {
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
    world.propose_update<CURRENCY_TESTS>(
        key, 
        option::none(), 
        option::none(), 
        option::none(), 
        option::none(), 
    );
    let executable = world.execute_proposal(key);
    world.approve_proposal(key);

    currency::execute_update(executable, world.account(), &mut coin_metadata);

    destroy(coin_metadata);
    world.end();
}

#[test, expected_failure(abort_code = currency::EWrongValue)]
fun test_burn_error_wrong_value() {
    let mut world = start_world();
    let key = b"burn proposal".to_string();

    let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    let sui_coin =  cap.mint<SUI>(101, world.scenario().ctx()); // wrong burn value
    transfer::public_transfer(sui_coin, world.account().addr());
    
    world.scenario().next_tx(OWNER);
    let receiving_coin = most_recent_receiving_ticket(&world.account().addr().to_id());
    world.lock_treasury_cap(cap);

    world.scenario().next_tx(OWNER);
    world.propose_burn<SUI>(key, receiving_coin.receiving_object_id(), 100);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    currency::execute_burn<SUI>(executable, world.account(), receiving_coin);

    world.end();
}

#[test, expected_failure(abort_code = currency::EMintNotExecuted)]
fun test_destroy_mint_error_mint_not_executed() {
    let mut world = start_world();
    let key = b"mint proposal".to_string();

    let cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    world.lock_treasury_cap(cap);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(
        Witness {},
        b"".to_string(),
        key, 
        b"description".to_string(), 
        0, 
        0, 
    );
    currency::new_mint<SUI>(proposal, 100);
    world.approve_proposal(key);

    world.scenario().next_tx(OWNER);
    let mut executable = world.execute_proposal(key);
    currency::destroy_mint<SUI, Witness>(&mut executable, Witness {});

    destroy(executable);
    world.end();    
}

#[test, expected_failure(abort_code = currency::EBurnNotExecuted)]
fun test_destroy_burn_error_burn_not_executed() {
    let mut world = start_world();
    let key = b"burn proposal".to_string();

    let mut cap = coin::create_treasury_cap_for_testing<SUI>(world.scenario().ctx()); 
    let sui_coin =  cap.mint<SUI>(100, world.scenario().ctx());
    transfer::public_transfer(sui_coin, world.account().addr());

    world.scenario().next_tx(OWNER);
    let receiving_coin = most_recent_receiving_ticket(&world.account().addr().to_id());
    world.lock_treasury_cap(cap);

    let proposal = world.create_proposal(
        Witness {},
        b"".to_string(),
        key, 
        b"description".to_string(), 
        0, 
        0, 
    );
    owned::new_withdraw(proposal, vector[receiving_coin.receiving_object_id()]);
    currency::new_burn<SUI>(proposal, 100);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let coin = owned::withdraw<Coin<SUI>, Witness>(
        &mut executable, 
        world.account(), 
        receiving_coin, 
        Witness {}, 
    );
    owned::destroy_withdraw(&mut executable, Witness {});
    currency::destroy_burn<SUI, Witness>(&mut executable, Witness {});

    destroy(coin);
    destroy(executable);
    world.end();    
}