#[test_only]
module account_actions::vault_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin,
    sui::SUI,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::Intent,
    issuer,
    deps,
    version_witness,
};
use account_actions::{
    version,
    vault,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct VAULT_TESTS has drop {}

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

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

    let mut account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
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

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Config, Outcome>, 
): Intent<Outcome> {
    account.create_intent(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_open_vault() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(!vault::has_vault(&account, b"Degen".to_string()));
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(vault::has_vault(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, VAULT_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<VAULT_TESTS>(5, scenario.ctx())
    );

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_exists<SUI>());
    assert!(vault.coin_type_value<SUI>() == 10);
    assert!(vault.coin_type_exists<VAULT_TESTS>());
    assert!(vault.coin_type_value<VAULT_TESTS>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_close_vault() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(vault::has_vault(&account, b"Degen".to_string()));

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_spend<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        5,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    let (mut executable, _) = account.execute_intent(b"dummy".to_string(), &clock, version::current(), DummyIntent());
    let coin = vault::do_spend<Config, Outcome, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::close(auth, &mut account, b"Degen".to_string());
    assert!(!vault::has_vault(&account, b"Degen".to_string()));

    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_deposit<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        5,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    vault::do_deposit<Config, Outcome, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(5, scenario.ctx()),
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_value<SUI>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_flow_joining_balances() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string(); 

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_deposit<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        5,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    vault::do_deposit<Config, Outcome, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(5, scenario.ctx()),
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_value<SUI>() == 10);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_flow_multiple_coins() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string(); 

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, VAULT_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<VAULT_TESTS>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_deposit<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        5,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    vault::do_deposit<Config, Outcome, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(5, scenario.ctx()),
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.size() == 2);
    assert!(vault.coin_type_value<SUI>() == 5);
    assert!(vault.coin_type_value<VAULT_TESTS>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_deposit<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        2,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    vault::delete_deposit<SUI>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_spend_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_spend<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        2,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    let coin = vault::do_spend<Config, Outcome, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_value<SUI>() == 3);
    assert!(coin.value() == 2);

    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_spend_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_spend<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        2,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    vault::delete_spend<SUI>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault::EVaultAlreadyExists)]
fun test_error_open_vault_already_exists() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault::EVaultDoesntExist)]
fun test_error_deposit_vault_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault::EVaultNotEmpty)]
fun test_error_close_not_empty() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::close(auth, &mut account, b"Degen".to_string());

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_update_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut account2 = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    vault::new_spend<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account2,
        b"Degen".to_string(),
        2,
        version::current(),
        DummyIntent(),
    );
    account2.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account2.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    let coin = vault::do_spend<Config, Outcome, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_update_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_spend<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        2,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let coin = vault::do_spend<Config, Outcome, SUI, WrongWitness>(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongWitness(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_update_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    vault::new_spend<Config, Outcome, SUI, DummyIntent>(
        &mut intent, 
        &account,
        b"Degen".to_string(),
        2,
        version::current(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong version TypeName that didn't approve the intent
    let coin = vault::do_spend<Config, Outcome, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}