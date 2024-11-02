#[test_only]
module account_protocol::coin_operations_tests;

// === Imports ===

use std::string::String;
use sui::{
    sui::SUI,
    coin::{Self, Coin},
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
};
use account_protocol::{
    account::{Self, Account},
    version,
    auth,
    coin_operations,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

// === Constants ===

const OWNER: address = @0xBABE;

// === Helpers ===

fun start(): (Scenario, Extensions, Account<bool, bool>) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountConfig".to_string(), @0x1, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0x2, 1);
    // Account generic types are dummy types (bool, bool)
    let account = account::new(&extensions, b"Main".to_string(), true, scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<bool, bool>) {
    destroy(extensions);
    destroy(account);
    ts::end(scenario);
}

fun full_role(): String {
    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::auth_tests::DummyProposal::Degen");
    full_role
}

fun keep_coin(addr: address, amount: u64, scenario: &mut Scenario): ID {
    let coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, addr);
    
    scenario.next_tx(OWNER);
    id
}

// === Tests ===

#[test]
fun test_merge_and_split_2_coins() {
    let (mut scenario, extensions, mut account) = start();

    let coin_to_split = coin::mint_for_testing<SUI>(100, scenario.ctx());
    transfer::public_transfer(coin_to_split, account.addr());
    
    scenario.next_tx(OWNER);
    let receiving_to_split = ts::most_recent_receiving_ticket<Coin<SUI>>(&object::id(&account));
    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let split_coin_ids = coin_operations::merge_and_split<bool, bool, SUI>(
        &auth,
        &mut account,
        vector[receiving_to_split],
        vector[40, 30],
        scenario.ctx()
    );

    scenario.next_tx(OWNER);
    let split_coin0 = scenario.take_from_address_by_id<Coin<SUI>>(
        account.addr(), 
        split_coin_ids[0]
    );
    let split_coin1 = scenario.take_from_address_by_id<Coin<SUI>>(
        account.addr(), 
        split_coin_ids[1]
    );
    assert!(split_coin0.value() == 40);
    assert!(split_coin1.value() == 30);

    destroy(auth);
    destroy(split_coin0);
    destroy(split_coin1);
    end(scenario, extensions, account);          
}  

#[test]
fun test_merge_2_coins_and_split() {
    let (mut scenario, extensions, mut account) = start();
    let account_address = account.addr();

    let id1 = keep_coin(account_address, 60, &mut scenario);
    let id2 = keep_coin(account_address, 40, &mut scenario);

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let merge_coin_id = coin_operations::merge_and_split<bool, bool, SUI>(
        &auth,
        &mut account,
        vector[ts::receiving_ticket_by_id(id1), ts::receiving_ticket_by_id(id2)],
        vector[100],
        scenario.ctx()
    );

    scenario.next_tx(OWNER);
    let merge_coin = scenario.take_from_address_by_id<Coin<SUI>>(
        account_address, 
        merge_coin_id[0]
    );
    assert!(merge_coin.value() == 100);

    destroy(auth);
    destroy(merge_coin);
    end(scenario, extensions, account);          
}  