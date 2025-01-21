#[test_only]
module account_actions::treasury_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::account::Account;
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    treasury,
    treasury_intents,
    vesting::{Self, Stream},
    transfer as acc_transfer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct TREASURY_TESTS has drop {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountConfig".to_string(), @account_config, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let mut account = multisig::new_account(&extensions, scenario.ctx());
    account.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let clock = clock::create_for_testing(scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_request_execute_transfer() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account,  
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    treasury_intents::request_transfer<Multisig, Approvals, SUI>(
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

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // loop over execute_transfer to execute each action
    treasury_intents::execute_transfer<Multisig, Approvals, SUI>(&mut executable, &mut account, scenario.ctx());
    treasury_intents::execute_transfer<Multisig, Approvals, SUI>(&mut executable, &mut account, scenario.ctx());
    treasury_intents::complete_transfer(executable, &account);

    let mut expired = account.destroy_empty_intent(key);
    treasury::delete_spend<SUI>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    treasury::delete_spend<SUI>(&mut expired);
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
    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    treasury_intents::request_vesting<Multisig, Approvals, SUI>(
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

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    treasury_intents::execute_vesting<Multisig, Approvals, SUI>(executable, &mut account, scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    treasury::delete_spend<SUI>(&mut expired);
    vesting::delete_vesting(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Stream<SUI>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 0);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury_intents::ENotSameLength)]
fun test_error_request_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    treasury_intents::request_transfer<Multisig, Approvals, SUI>(
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

#[test, expected_failure(abort_code = treasury_intents::ECoinTypeDoesntExist)]
fun test_error_request_transfer_coin_type_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, TREASURY_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<TREASURY_TESTS>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    treasury_intents::request_transfer<Multisig, Approvals, SUI>(
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

#[test, expected_failure(abort_code = treasury_intents::EInsufficientFunds)]
fun test_error_request_transfer_insufficient_funds() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(1, scenario.ctx())
    );

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    treasury_intents::request_transfer<Multisig, Approvals, SUI>(
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

#[test, expected_failure(abort_code = treasury_intents::ECoinTypeDoesntExist)]
fun test_error_request_vesting_coin_type_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, TREASURY_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<TREASURY_TESTS>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    treasury_intents::request_vesting<Multisig, Approvals, SUI>(
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

#[test, expected_failure(abort_code = treasury_intents::EInsufficientFunds)]
fun test_error_request_vesting_insufficient_funds() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(4, scenario.ctx())
    );

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    treasury_intents::request_vesting<Multisig, Approvals, SUI>(
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
