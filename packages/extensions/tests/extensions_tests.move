#[test_only]
module account_extensions::extensions_tests;

// === Imports === 

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Helpers ===

fun start(): (Scenario, Extensions, AdminCap) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @0x0, 1);
    extensions.add(&cap, b"AccountConfig".to_string(), @0x1, 1);
    // create world
    (scenario, extensions, cap)
}

fun end(scenario: Scenario, extensions: Extensions, cap: AdminCap) {
    destroy(extensions);
    destroy(cap);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_core_deps_v1() {
    let (scenario, extensions, cap) = start();

    // assertions
    assert!(extensions.is_extension(b"AccountProtocol".to_string(), @0x0, 1));
    assert!(extensions.is_extension(b"AccountConfig".to_string(), @0x1, 1));
    // core deps getters
    let addresses = extensions.get_core_deps_addresses();
    assert!(addresses == vector[@0x0, @0x1]);
    let (addresses, versions) = extensions.get_latest_core_deps();
    assert!(addresses == vector[@0x0, @0x1]);
    assert!(versions == vector[1, 1]);

    end(scenario, extensions, cap);
}

#[test]
fun test_update_core_deps_to_v2() {
    let (scenario, mut extensions, cap) = start();

    // update core deps
    extensions.update(&cap, b"AccountConfig".to_string(), @0x11, 2);
    // core deps getters
    let addresses = extensions.get_core_deps_addresses();
    assert!(addresses == vector[@0x0, @0x1, @0x11]);
    let (addresses, versions) = extensions.get_latest_core_deps();
    assert!(addresses == vector[@0x0, @0x11]);
    assert!(versions == vector[1, 2]);

    end(scenario, extensions, cap);
}

#[test]
fun test_add_deps() {
    let (scenario, mut extensions, cap) = start();

    // add extension
    extensions.add(&cap, b"A".to_string(), @0xA, 1);
    extensions.add(&cap, b"B".to_string(), @0xB, 1);
    extensions.add(&cap, b"C".to_string(), @0xC, 1);
    // assertions
    assert!(extensions.is_extension(b"A".to_string(), @0xA, 1));
    assert!(extensions.is_extension(b"B".to_string(), @0xB, 1));
    assert!(extensions.is_extension(b"C".to_string(), @0xC, 1));

    end(scenario, extensions, cap);
}

#[test]
fun test_update_deps() {
    let (scenario, mut extensions, cap) = start();

    // add extension (checked above)
    extensions.add(&cap, b"A".to_string(), @0xA, 1);
    extensions.add(&cap, b"B".to_string(), @0xB, 1);
    extensions.add(&cap, b"C".to_string(), @0xC, 1);
    // update deps
    extensions.update(&cap, b"B".to_string(), @0x1B, 2);
    extensions.update(&cap, b"C".to_string(), @0x1C, 2);
    extensions.update(&cap, b"C".to_string(), @0x2C, 3);
    // assertions
    // verify core deps didn't change
    let addresses = extensions.get_core_deps_addresses();
    assert!(addresses == vector[@0x0, @0x1]);
    let (addresses, versions) = extensions.get_latest_core_deps();
    assert!(addresses == vector[@0x0, @0x1]);
    assert!(versions == vector[1, 1]);

    end(scenario, extensions, cap);
}

#[test]
fun test_remove_deps() {
    let (scenario, mut extensions, cap) = start();

    // add extension (checked above)
    extensions.add(&cap, b"A".to_string(), @0xA, 1);
    extensions.add(&cap, b"B".to_string(), @0xB, 1);
    extensions.add(&cap, b"C".to_string(), @0xC, 1);
    // update deps
    extensions.update(&cap, b"B".to_string(), @0x1B, 2);
    extensions.update(&cap, b"C".to_string(), @0x1C, 2);
    extensions.update(&cap, b"C".to_string(), @0x2C, 3);
    // remove deps
    extensions.remove(&cap, b"A".to_string());
    extensions.remove(&cap, b"B".to_string());
    extensions.remove(&cap, b"C".to_string());
    // assertions
    assert!(!extensions.is_extension(b"A".to_string(), @0xA, 1));
    assert!(!extensions.is_extension(b"B".to_string(), @0xB, 1));
    assert!(!extensions.is_extension(b"B".to_string(), @0x1B, 2));
    assert!(!extensions.is_extension(b"C".to_string(), @0xC, 1));
    assert!(!extensions.is_extension(b"C".to_string(), @0x1C, 2));
    assert!(!extensions.is_extension(b"C".to_string(), @0x2C, 3));

    end(scenario, extensions, cap);
}

#[test, expected_failure(abort_code = extensions::ECannotRemoveCoreDep)]
fun test_error_remove_account_protocol() {
    let (scenario, mut extensions, cap) = start();
    extensions.remove(&cap, b"AccountProtocol".to_string());
    end(scenario, extensions, cap);
}

#[test, expected_failure(abort_code = extensions::ECannotRemoveCoreDep)]
fun test_error_remove_account_config() {
    let (scenario, mut extensions, cap) = start();
    extensions.remove(&cap, b"AccountConfig".to_string());
    end(scenario, extensions, cap);
}

#[test, expected_failure(abort_code = extensions::EExtensionAlreadyExists)]
fun test_error_add_extension_name_already_exists() {
    let (scenario, mut extensions, cap) = start();
    extensions.add(&cap, b"AccountProtocol".to_string(), @0xA, 1);
    end(scenario, extensions, cap);
}

#[test, expected_failure(abort_code = extensions::EExtensionAlreadyExists)]
fun test_error_add_extension_address_already_exists() {
    let (scenario, mut extensions, cap) = start();
    extensions.add(&cap, b"A".to_string(), @0x0, 1);
    end(scenario, extensions, cap);
}

#[test, expected_failure(abort_code = extensions::EExtensionNotFound)]
fun test_error_update_not_extension() {
    let (scenario, mut extensions, cap) = start();
    extensions.update(&cap, b"A".to_string(), @0x0, 1);
    end(scenario, extensions, cap);
}

#[test, expected_failure(abort_code = extensions::EExtensionNotFound)]
fun test_error_remove_not_extension() {
    let (scenario, mut extensions, cap) = start();
    extensions.remove(&cap, b"A".to_string());
    end(scenario, extensions, cap);
}