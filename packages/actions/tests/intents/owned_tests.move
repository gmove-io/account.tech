#[test_only]
module account_actions::owned_intents_tests;

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
    owned,
};
use account_actions::{
    owned_intents,
    vault,
    vesting::{Self, Vesting},
    transfer as acc_transfer,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Witness() has drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config, Outcome>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()], vector[@account_protocol, @account_actions], vector[1, 1], scenario.ctx());
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

// === Tests ===

#[test]
fun test_request_execute_transfer_to_vault() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let id = send_coin(account.addr(), 1, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    owned_intents::request_withdraw_and_transfer_to_vault<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        id,
        1,
        b"Degen".to_string(),
        scenario.ctx()
    );

    let (executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    owned_intents::execute_withdraw_and_transfer_to_vault<Config, Outcome, SUI>(executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id));

    let mut expired = account.destroy_empty_intent(key);
    owned::delete_withdraw(&mut expired, &mut account);
    vault::delete_deposit<SUI>(&mut expired);
    expired.destroy_empty();

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_exists<SUI>());
    assert!(vault.coin_type_value<SUI>() == 1);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_transfer() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id1 = send_coin(account.addr(), 1, &mut scenario);
    let id2 = send_coin(account.addr(), 2, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    owned_intents::request_withdraw_and_transfer<Config, Outcome>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        vector[id1, id2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    let (mut executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    // loop over execute_transfer to execute each action
    owned_intents::execute_withdraw_and_transfer<Config, Outcome, Coin<SUI>>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id1));
    owned_intents::execute_withdraw_and_transfer<Config, Outcome, Coin<SUI>>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id2));
    owned_intents::complete_withdraw_and_transfer(executable, &account);

    let mut expired = account.destroy_empty_intent(key);
    owned::delete_withdraw(&mut expired, &mut account);
    acc_transfer::delete_transfer(&mut expired);
    owned::delete_withdraw(&mut expired, &mut account);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<SUI>>(@0x2);
    assert!(coin2.value() == 2);

    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_vesting() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    owned_intents::request_withdraw_and_vest<Config, Outcome>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        id, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    let (executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    owned_intents::execute_withdraw_and_vest<Config, Outcome, SUI>(executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id), scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    owned::delete_withdraw(&mut expired, &mut account);
    vesting::delete_vest(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Vesting<SUI>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 0);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock);
} 

#[test, expected_failure(abort_code = owned_intents::EObjectsRecipientsNotSameLength)]
fun test_error_request_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    owned_intents::request_withdraw_and_transfer<Config, Outcome>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(),
        b"".to_string(), 
        0, 
        1, 
        vector[@0x1D.to_id()],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}
