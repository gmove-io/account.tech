#[test_only]
module account_actions::currency_tests;

// === Imports ===

use std::type_name::{Self, TypeName};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin, TreasuryCap, CoinMetadata},
    url,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
    intents::Intent,
    issuer,
    deps,
};
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    version,
    currency,
    owned,
    vesting::{Self, Stream},
    transfer as acc_transfer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct CURRENCY_TESTS has drop {}

public struct DummyIntent() has copy, drop;

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock, TreasuryCap<CURRENCY_TESTS>, CoinMetadata<CURRENCY_TESTS>) {
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
    // Account generic types are dummy types (bool, bool)
    let account = multisig::new_account(&extensions, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create TreasuryCap and CoinMetadata
    let (treasury_cap, metadata) = coin::create_currency(
        CURRENCY_TESTS {}, 
        9, 
        b"SYMBOL", 
        b"Name", 
        b"description", 
        option::some(url::new_unsafe_from_bytes(b"https://url.com")), 
        scenario.ctx()
    );
    // create world
    destroy(cap);
    (scenario, extensions, account, clock, treasury_cap, metadata)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock, metadata: CoinMetadata<CURRENCY_TESTS>) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    destroy(metadata);
    ts::end(scenario);
}

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
): Intent<Approvals> {
    let auth = multisig::authenticate(extensions, account, scenario.ctx());
    let outcome = multisig::empty_outcome(account, scenario.ctx());
    account.create_intent(
        auth, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        outcome, 
        version::current(), 
        DummyIntent(), 
        b"".to_string(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock_cap() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    assert!(!currency::has_cap<Multisig, Approvals, CURRENCY_TESTS>(&account));
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(100));
    assert!(currency::has_cap<Multisig, Approvals, CURRENCY_TESTS>(&account));

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_lock_getters() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(100));

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_TESTS>(&account);
    let supply = currency::coin_type_supply<Multisig, Approvals, CURRENCY_TESTS>(&account);
    assert!(supply == 0);
    assert!(lock.total_minted() == 0);
    assert!(lock.total_burned() == 0);
    assert!(lock.can_mint() == true);
    assert!(lock.can_burn() == true);
    assert!(lock.can_update_name() == true);
    assert!(lock.can_update_symbol() == true);
    assert!(lock.can_update_description() == true);
    assert!(lock.can_update_icon() == true);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_public_burn() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(100));

    currency::public_burn(&mut account, coin);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_disable() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_disable<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        true,
        true,
        true,
        true,
        true,
        true,
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    currency::execute_disable<Multisig, Approvals, CURRENCY_TESTS>(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_disable<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_TESTS>(&account);
    assert!(lock.can_mint() == false);
    assert!(lock.can_burn() == false);
    assert!(lock.can_update_name() == false);
    assert!(lock.can_update_symbol() == false);
    assert!(lock.can_update_description() == false);
    assert!(lock.can_update_icon() == false);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_mint() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_mint<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        5,
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    currency::execute_mint<Multisig, Approvals, CURRENCY_TESTS>(executable, &mut account, scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_mint<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_TESTS>(&account);
    let supply = currency::coin_type_supply<Multisig, Approvals, CURRENCY_TESTS>(&account);
    assert!(supply == 5);
    assert!(lock.total_minted() == 5);
    assert!(lock.total_burned() == 0);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_mint_with_max_supply() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(5));
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_mint<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        5,
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    currency::execute_mint<Multisig, Approvals, CURRENCY_TESTS>(executable, &mut account, scenario.ctx());

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_TESTS>(&account);
    let supply = currency::coin_type_supply<Multisig, Approvals, CURRENCY_TESTS>(&account);
    assert!(supply == 5);
    assert!(lock.total_minted() == 5);
    assert!(lock.total_burned() == 0);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_burn() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    // create cap, mint and transfer coin to Account
    let coin = cap.mint(5, scenario.ctx());
    assert!(cap.total_supply() == 5);
    let coin_id = object::id(&coin);
    account.keep(coin);
    scenario.next_tx(OWNER);
    let receiving = ts::most_recent_receiving_ticket<Coin<CURRENCY_TESTS>>(&object::id(&account));

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_burn<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        coin_id,
        5,
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    currency::execute_burn<Multisig, Approvals, CURRENCY_TESTS>(executable, &mut account, receiving);

    let mut expired = account.destroy_empty_intent(key);
    owned::delete_withdraw(&mut expired, &mut account);
    currency::delete_burn<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_TESTS>(&account);
    let supply = currency::coin_type_supply<Multisig, Approvals, CURRENCY_TESTS>(&account);
    assert!(supply == 0);
    assert!(lock.total_minted() == 0);
    assert!(lock.total_burned() == 5);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_update() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_update<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    currency::execute_update<Multisig, Approvals, CURRENCY_TESTS>(executable, &mut account, &mut metadata);

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_update<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    assert!(metadata.get_symbol() == b"NEW".to_ascii_string());
    assert!(metadata.get_name() == b"New".to_string());
    assert!(metadata.get_description() == b"new".to_string());
    assert!(metadata.get_icon_url().extract() == url::new_unsafe_from_bytes(b"https://new.com"));

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_transfer() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_transfer<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        vector[1, 2, 3],
        vector[@0x1, @0x2, @0x3],
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // loop over execute_transfer to execute each action
    3u64.do!(|_| {
        currency::execute_transfer<Multisig, Approvals, CURRENCY_TESTS>(&mut executable, &mut account, scenario.ctx());
    });
    currency::complete_transfer(executable, &account);

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_mint<CURRENCY_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    currency::delete_mint<CURRENCY_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    currency::delete_mint<CURRENCY_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<CURRENCY_TESTS>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<CURRENCY_TESTS>>(@0x2);
    assert!(coin2.value() == 2);
    let coin3 = scenario.take_from_address<Coin<CURRENCY_TESTS>>(@0x3);
    assert!(coin3.value() == 3);

    destroy(coin1);
    destroy(coin2);
    destroy(coin3);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_vesting() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_vesting<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    currency::execute_vesting<Multisig, Approvals, CURRENCY_TESTS>(executable, &mut account, scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_mint<CURRENCY_TESTS>(&mut expired);
    vesting::delete_vesting(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Stream<CURRENCY_TESTS>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 0);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_disable_flow() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_disable<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        true,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_disable<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_mint_flow() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_mint<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let coin = currency::do_mint<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );
    assert!(coin.value() == 5);
    account.confirm_execution(executable, version::current(), DummyIntent());

    destroy(coin);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_burn_flow() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_burn<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_burn<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_update_flow() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    assert!(metadata.get_symbol() == b"NEW".to_ascii_string());
    assert!(metadata.get_name() == b"New".to_string());
    assert!(metadata.get_description() == b"new".to_string());
    assert!(metadata.get_icon_url().extract() == url::new_unsafe_from_bytes(b"https://new.com"));

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_disable_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_disable<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        true,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    currency::delete_disable<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_mint_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_mint<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    currency::delete_mint<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_burn_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_burn<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    currency::delete_burn<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_update_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    currency::delete_update<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoLock)]
fun test_error_public_burn_no_lock() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();

    currency::public_burn(&mut account, cap.mint(5, scenario.ctx()));

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EBurnDisabled)]
fun test_error_public_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_burn<Multisig, Approvals, CURRENCY_TESTS>(&mut account);
    currency::public_burn(&mut account, coin);

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoLock)]
fun test_error_request_disable_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_disable<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        true,
        true,
        true,
        true,
        true,
        true,
        scenario.ctx()
    );

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoLock)]
fun test_error_request_mint_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_mint<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        5,
        scenario.ctx()
    );

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMintDisabled)]
fun test_error_request_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_mint<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_mint<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        5,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMaxSupply)]
fun test_error_request_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_mint<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        5,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoLock)]
fun test_error_request_burn_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_burn<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        @0x1D.to_id(),
        5,
        scenario.ctx()
    );

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EBurnDisabled)]
fun test_error_request_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_burn<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_burn<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        @0x1D.to_id(),
        5,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoLock)]
fun test_error_request_update_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_update<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );

    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateSymbol)]
fun test_error_request_update_cannot_update_symbol() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_symbol<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_update<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateName)]
fun test_error_request_update_cannot_update_name() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_name<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_update<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateDescription)]
fun test_error_request_update_cannot_update_description() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_description<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_update<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateIcon)]
fun test_error_request_update_cannot_update_icon() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_icon<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_update<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoLock)]
fun test_error_request_transfer_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_transfer<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        vector[1, 2, 3],
        vector[@0x1, @0x2],
        scenario.ctx()
    );
    
    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EAmountsRecipentsNotSameLength)]
fun test_error_request_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_transfer<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        vector[1, 2, 3],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMintDisabled)]
fun test_error_request_transfer_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_mint<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_transfer<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        vector[1],
        vector[@0x1],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMaxSupply)]
fun test_error_request_transfer_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_transfer<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        vector[1, 2, 3],
        vector[@0x1, @0x2, @0x3],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoLock)]
fun test_error_request_vesting_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_vesting<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1,
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );
    
    destroy(cap);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMintDisabled)]
fun test_error_request_vesting_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_mint<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_vesting<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1,
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );
    
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMaxSupply)]
fun test_error_request_vesting_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    currency::request_vesting<Multisig, Approvals, CURRENCY_TESTS>(
        auth, 
        outcome, 
        &mut account, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1,
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );
    
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoChange)]
fun test_error_disable_nothing() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_disable<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        false,
        false,
        false,
        false,
        false,
        false,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMintDisabled)]
fun test_error_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    let key = b"dummy".to_string();

    currency::toggle_can_mint<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_mint<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let coin = currency::do_mint<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(executable);
    destroy(coin);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMaxSupply)]
fun test_error_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_mint<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let coin = currency::do_mint<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(executable);
    destroy(coin);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EWrongValue)]
fun test_error_burn_wrong_value() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_burn<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        4,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_burn<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EBurnDisabled)]
fun test_error_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    currency::toggle_can_burn<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_burn<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_burn<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoChange)]
fun test_error_update_nothing() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateSymbol)]
fun test_error_update_symbol_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    currency::toggle_can_update_symbol<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::none(),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateName)]
fun test_error_update_name_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    currency::toggle_can_update_name<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::none(),
        option::some(b"New".to_string()),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateDescription)]
fun test_error_update_description_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    currency::toggle_can_update_description<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::none(),
        option::none(),
        option::some(b"new".to_string()),
        option::none(),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateIcon)]
fun test_error_update_icon_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    currency::toggle_can_update_icon<Multisig, Approvals, CURRENCY_TESTS>(&mut account);

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::none(),
        option::none(),
        option::none(),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_disable_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2, &extensions);
    currency::new_disable<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        true,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to disable from the account that didn't approve the intent
    currency::do_disable<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_disable_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_disable<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        true,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to disable with the wrong witness that didn't approve the intent
    currency::do_disable<Multisig, Approvals, CURRENCY_TESTS, issuer::WrongWitness>(
        &mut executable, 
        &mut account, 
        version::current(), 
        issuer::wrong_witness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_disable_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_disable<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        true,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to disable with the wrong version TypeName that didn't approve the intent
    currency::do_disable<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        wrong_version(), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_mint_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2, &extensions);
    currency::new_mint<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to mint from the right account that didn't approve the intent
    let coin = currency::do_mint<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_mint_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_mint<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the intent
    let coin = currency::do_mint<Multisig, Approvals, CURRENCY_TESTS, issuer::WrongWitness>(
        &mut executable, 
        &mut account, 
        version::current(), 
        issuer::wrong_witness(),
        scenario.ctx(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_mint_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_mint<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the intent
    let coin = currency::do_mint<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        wrong_version(), 
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_burn_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2, &extensions);
    currency::new_burn<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the intent
    currency::do_burn<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_burn_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_burn<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to burn with the wrong witness that didn't approve the intent
    currency::do_burn<Multisig, Approvals, CURRENCY_TESTS, issuer::WrongWitness>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        issuer::wrong_witness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_burn_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_burn<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the intent
    currency::do_burn<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        coin,
        wrong_version(), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_update_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the intent
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_update_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the intent
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, issuer::WrongWitness>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        issuer::wrong_witness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_update_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    currency::new_update<Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the intent
    currency::do_update<Multisig, Approvals, CURRENCY_TESTS, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        wrong_version(), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}