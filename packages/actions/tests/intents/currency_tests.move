#[test_only]
module account_actions::currency_intents_tests;

// === Imports ===

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
    owned,
};
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    currency,
    currency_intents,
    vesting::{Self, Stream},
    transfer as acc_transfer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct CURRENCY_INTENTS_TESTS has drop {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock, TreasuryCap<CURRENCY_INTENTS_TESTS>, CoinMetadata<CURRENCY_INTENTS_TESTS>) {
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
    account.deps_mut_for_testing().add(&extensions, b"AccountConfig".to_string(), @account_config, 1);
    account.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let clock = clock::create_for_testing(scenario.ctx());
    // create TreasuryCap and CoinMetadata
    let (treasury_cap, metadata) = coin::create_currency(
        CURRENCY_INTENTS_TESTS {}, 
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

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock, metadata: CoinMetadata<CURRENCY_INTENTS_TESTS>) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    destroy(metadata);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_request_execute_disable() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_disable<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
    currency_intents::execute_disable<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_disable<CURRENCY_INTENTS_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&account);
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
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
    currency_intents::execute_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(executable, &mut account, scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&account);
    let supply = currency::coin_type_supply<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&account);
    assert!(supply == 5);
    assert!(lock.total_minted() == 5);
    assert!(lock.total_burned() == 0);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_mint_with_max_supply() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(5));
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
    currency_intents::execute_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(executable, &mut account, scenario.ctx());

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&account);
    let supply = currency::coin_type_supply<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&account);
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
    let receiving = ts::most_recent_receiving_ticket<Coin<CURRENCY_INTENTS_TESTS>>(&object::id(&account));

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_burn<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
    currency_intents::execute_burn<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(executable, &mut account, receiving);

    let mut expired = account.destroy_empty_intent(key);
    owned::delete_withdraw(&mut expired, &mut account);
    currency::delete_burn<CURRENCY_INTENTS_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&account);
    let supply = currency::coin_type_supply<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&account);
    assert!(supply == 0);
    assert!(lock.total_minted() == 0);
    assert!(lock.total_burned() == 5);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_update() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_update<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
    currency_intents::execute_update<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(executable, &mut account, &mut metadata);

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_update<CURRENCY_INTENTS_TESTS>(&mut expired);
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
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_transfer<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
        currency_intents::execute_transfer<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account, scenario.ctx());
    });
    currency_intents::complete_transfer(executable, &account);

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<CURRENCY_INTENTS_TESTS>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<CURRENCY_INTENTS_TESTS>>(@0x2);
    assert!(coin2.value() == 2);
    let coin3 = scenario.take_from_address<Coin<CURRENCY_INTENTS_TESTS>>(@0x3);
    assert!(coin3.value() == 3);

    destroy(coin1);
    destroy(coin2);
    destroy(coin3);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_vesting() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_vesting<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
    currency_intents::execute_vesting<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(executable, &mut account, scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    vesting::delete_vesting(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Stream<CURRENCY_INTENTS_TESTS>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 0);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::ENoLock)]
fun test_error_request_disable_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_disable<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ENoLock)]
fun test_error_request_mint_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EMintDisabled)]
fun test_error_request_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EMaxSupply)]
fun test_error_request_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ENoLock)]
fun test_error_request_burn_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_burn<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EBurnDisabled)]
fun test_error_request_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_burn<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_burn<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ENoLock)]
fun test_error_request_update_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_update<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateSymbol)]
fun test_error_request_update_cannot_update_symbol() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_symbol<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_update<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateName)]
fun test_error_request_update_cannot_update_name() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_name<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_update<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateDescription)]
fun test_error_request_update_cannot_update_description() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_description<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_update<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateIcon)]
fun test_error_request_update_cannot_update_icon() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_icon<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_update<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ENoLock)]
fun test_error_request_transfer_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_transfer<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EAmountsRecipentsNotSameLength)]
fun test_error_request_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_transfer<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EMintDisabled)]
fun test_error_request_transfer_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_transfer<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EMaxSupply)]
fun test_error_request_transfer_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_transfer<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::ENoLock)]
fun test_error_request_vesting_no_lock() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_vesting<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EMintDisabled)]
fun test_error_request_vesting_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_mint<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_vesting<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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

#[test, expected_failure(abort_code = currency_intents::EMaxSupply)]
fun test_error_request_vesting_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    currency_intents::request_vesting<Multisig, Approvals, CURRENCY_INTENTS_TESTS>(
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
