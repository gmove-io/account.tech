#[test_only]
module account_protocol::owned_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::Intent,
    issuer,
    deps,
    owned,
    version,
    version_witness,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Witness() has copy, drop;
public struct WrongWitness() has copy, drop;
public struct DummyIntent() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config, Outcome>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    account::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountConfig".to_string(), @0x1, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0x2, 1);
    // Account generic types are dummy types (bool, bool)
    let account = account::new(&extensions, Config {}, false, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config, Outcome>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

fun send_coin(addr: address, amount: u64, scenario: &mut Scenario): ID {
    let coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, addr);
    
    scenario.next_tx(OWNER);
    id
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Config, Outcome>, 
): Intent<Outcome> {
    account.create_intent(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
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
fun test_withdraw_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    owned::new_withdraw(&mut intent, &mut account, id, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable,
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    assert!(coin.value() == 5);
    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_withdraw_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    owned::new_withdraw(&mut intent, &mut account, id, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    owned::delete_withdraw(&mut expired, &mut account);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_merge_and_split_2_coins() {
    let (mut scenario, extensions, mut account, clock) = start();

    let coin_to_split = coin::mint_for_testing<SUI>(100, scenario.ctx());
    transfer::public_transfer(coin_to_split, account.addr());
    
    scenario.next_tx(OWNER);
    let receiving_to_split = ts::most_recent_receiving_ticket<Coin<SUI>>(&object::id(&account));
    let auth = account.new_auth(Witness());
    let split_coin_ids = owned::merge_and_split<Config, Outcome, SUI>(
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
    end(scenario, extensions, account, clock);          
}  

#[test]
fun test_merge_2_coins_and_split() {
    let (mut scenario, extensions, mut account, clock) = start();
    let account_address = account.addr();

    let id1 = keep_coin(account_address, 60, &mut scenario);
    let id2 = keep_coin(account_address, 40, &mut scenario);

    let auth = account.new_auth(Witness());
    let merge_coin_id = owned::merge_and_split<Config, Outcome, SUI>(
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
    end(scenario, extensions, account, clock);          
}  

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_withdraw_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let mut account2 = account::new(&extensions, Config {}, false, scenario.ctx());
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    owned::new_withdraw(&mut intent, &mut account, id, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account2.execute_intent(key, &clock, version::current(), Witness());
    // try to disable from the account that didn't approve the intent
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable, 
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        version::current(), 
        DummyIntent(),
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_withdraw_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    owned::new_withdraw(&mut intent, &mut account, id, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    // try to disable with the wrong witness that didn't approve the intent
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable, 
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        version::current(), 
        WrongWitness(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_withdraw_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    owned::new_withdraw(&mut intent, &mut account, id, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    // try to disable with the wrong version TypeName that didn't approve the intent
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable, 
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        version_witness::new_for_testing(@0xDE9),
        DummyIntent(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}