#[test_only]
module account_actions::vault_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::account::{Self, Account};
use account_actions::{
    vault,
    vault_intents,
    vesting::{Self, Vesting},
    transfer as acc_transfer,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

public struct Witness() has drop;

public struct VAULT_TESTS has drop {}

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

// === Tests ===

#[test]
fun test_request_execute_transfer() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account,  
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    vault_intents::request_spend_and_transfer<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    let (mut executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    // loop over execute_spend_and_transfer to execute each action
    vault_intents::execute_spend_and_transfer<Config, Outcome, SUI>(&mut executable, &mut account, scenario.ctx());
    vault_intents::execute_spend_and_transfer<Config, Outcome, SUI>(&mut executable, &mut account, scenario.ctx());
    vault_intents::complete_spend_and_transfer(executable, &account);

    let mut expired = account.destroy_empty_intent(key);
    vault::delete_spend<SUI>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    vault::delete_spend<SUI>(&mut expired);
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
    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    vault_intents::request_spend_and_vest<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        b"Degen".to_string(),
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    let (executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    vault_intents::execute_spend_and_vest<Config, Outcome, SUI>(executable, &mut account, scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    vault::delete_spend<SUI>(&mut expired);
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

#[test, expected_failure(abort_code = vault_intents::ENotSameLength)]
fun test_error_request_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    vault_intents::request_spend_and_transfer<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault_intents::ECoinTypeDoesntExist)]
fun test_error_request_transfer_coin_type_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::deposit<Config, Outcome, VAULT_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<VAULT_TESTS>(5, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    vault_intents::request_spend_and_transfer<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault_intents::EInsufficientFunds)]
fun test_error_request_transfer_insufficient_funds() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(1, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    vault_intents::request_spend_and_transfer<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault_intents::ECoinTypeDoesntExist)]
fun test_error_request_vesting_coin_type_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::deposit<Config, Outcome, VAULT_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<VAULT_TESTS>(5, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    vault_intents::request_spend_and_vest<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        b"Degen".to_string(),
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault_intents::EInsufficientFunds)]
fun test_error_request_vesting_insufficient_funds() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(4, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    vault_intents::request_spend_and_vest<Config, Outcome, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        b"Degen".to_string(),
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}
