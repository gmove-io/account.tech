#[test_only]
module account_protocol::user_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
};
use account_protocol::user::{Self, Registry, User};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;

// === Structs ===

public struct DummyIntent() has drop;

// === Helpers ===

fun start(): (Scenario, Registry) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    user::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let registry = scenario.take_shared<Registry>();

    (scenario, registry)
}

fun end(scenario: Scenario, registry: Registry) {
    destroy(registry);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_user_flow() {
    let (mut scenario, mut registry) = start();

    let mut user = user::new(scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    user.add_account(@0xACC1, b"multisig".to_string());
    user.add_account(@0xACC2, b"multisig".to_string());
    user.add_account(@0xACC3, b"dao".to_string());
    assert!(user.all_ids() == vector[@0xACC3, @0xACC1, @0xACC2]);
    assert!(user.ids_for_type(b"multisig".to_string()) == vector[@0xACC1, @0xACC2]);
    assert!(user.ids_for_type(b"dao".to_string()) == vector[@0xACC3]);

    user.remove_account(@0xACC1, b"multisig".to_string());
    user.remove_account(@0xACC2, b"multisig".to_string());
    user.remove_account(@0xACC3, b"dao".to_string());
    assert!(user.all_ids() == vector[]);

    registry.transfer(user, OWNER, scenario.ctx());
    assert!(registry.users().length() == 1);
    assert!(registry.users().contains(OWNER));

    scenario.next_tx(OWNER);
    let user = scenario.take_from_sender<User>();
    registry.destroy(user, scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    end(scenario, registry);
}

#[test, expected_failure(abort_code = user::EAccountAlreadyRegistered)]
fun test_error_add_already_existing_account() {
    let (mut scenario, registry) = start();

    let mut user = user::new(scenario.ctx());
    user.add_account(@0xACC2, b"multisig".to_string());
    user.add_account(@0xACC2, b"multisig".to_string());
    
    destroy(user);
    end(scenario, registry);
}

#[test, expected_failure(abort_code = user::EAccountTypeDoesntExist)]
fun test_error_remove_empty_account_type() {
    let (mut scenario, registry) = start();

    let mut user = user::new(scenario.ctx());
    user.remove_account(@0xACC1, b"multisig".to_string());

    destroy(user);
    end(scenario, registry);
}

#[test, expected_failure(abort_code = user::EAccountNotFound)]
fun test_error_remove_wrong_account() {
    let (mut scenario, registry) = start();

    let mut user = user::new(scenario.ctx());
    user.add_account(@0xACC2, b"multisig".to_string());
    user.remove_account(@0xACC1, b"multisig".to_string());

    destroy(user);
    end(scenario, registry);
}

#[test, expected_failure(abort_code = user::EAlreadyHasUser)]
fun test_error_transfer_to_existing_user() {
    let (mut scenario, mut registry) = start();

    registry.transfer(user::new(scenario.ctx()), OWNER, scenario.ctx());
    registry.transfer(user::new(scenario.ctx()), OWNER, scenario.ctx());

    end(scenario, registry);
}

#[test, expected_failure(abort_code = user::EWrongUserId)]
fun test_error_transfer_wrong_user_object() {
    let (mut scenario, mut registry) = start();

    registry.transfer(user::new(scenario.ctx()), OWNER, scenario.ctx());
    // OWNER transfers wrong user object to ALICE
    registry.transfer(user::new(scenario.ctx()), ALICE, scenario.ctx());

    end(scenario, registry);
}

#[test, expected_failure(abort_code = user::ENotEmpty)]
fun test_error_destroy_non_empty_user() {
    let (mut scenario, mut registry) = start();

    let mut user = user::new(scenario.ctx());
    user.add_account(@0xACC, b"multisig".to_string());
    registry.destroy(user, scenario.ctx());

    end(scenario, registry);
}
