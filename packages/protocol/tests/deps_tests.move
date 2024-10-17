#[test_only]
module account_protocol::deps_tests;

// === Imports ===

use std::type_name;
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    package,
};
use account_protocol::{
    deps,
    version,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Helpers ===

fun start(): (Scenario, Extensions) {
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
    extensions.add(&cap, b"External".to_string(), @0xA, 1);
    // create world
    destroy(cap);
    (scenario, extensions)
}

fun end(scenario: Scenario, extensions: Extensions) {
    destroy(extensions);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_deps_new_and_getters() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions);
    // assertions
    deps.assert_is_dep(version::current());
    deps.assert_is_core_dep(version::current());
    // deps getters
    assert!(deps.length() == 3);
    assert!(deps.contains_name(b"AccountProtocol".to_string()));
    assert!(deps.contains_name(b"AccountConfig".to_string()));
    assert!(deps.contains_name(b"AccountActions".to_string()));
    assert!(deps.contains_addr(@account_protocol));
    assert!(deps.contains_addr(@0x1));
    assert!(deps.contains_addr(@0x2));
    assert!(deps.get_idx_for_addr(@account_protocol) == 0);
    assert!(deps.get_idx_for_addr(@0x1) == 1);
    assert!(deps.get_idx_for_addr(@0x2) == 2);
    // dep getters
    let dep = deps.get_from_name(b"AccountProtocol".to_string());
    assert!(dep.name() == b"AccountProtocol".to_string());
    assert!(dep.addr() == @account_protocol);
    assert!(dep.version() == 1);
    let dep = deps.get_from_addr(@0x1);
    assert!(dep.name() == b"AccountConfig".to_string());
    assert!(dep.addr() == @0x1);
    assert!(dep.version() == 1);

    end(scenario, extensions);
}

#[test]
fun test_deps_add() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions);
    deps.add(&extensions, b"External".to_string(), @0xA, 1);
    // verify
    let dep = deps.get_from_name(b"External".to_string());
    assert!(dep.name() == b"External".to_string());
    assert!(dep.addr() == @0xA);
    assert!(dep.version() == 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test]
fun test_deps_add_with_upgrade_cap() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions);
    deps.add_with_upgrade_cap(&cap, b"Other".to_string(), @0xA, 1);
    // verify
    let dep = deps.get_from_name(b"Other".to_string());
    assert!(dep.name() == b"Other".to_string());
    assert!(dep.addr() == @0xA);
    assert!(dep.version() == 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = extensions::EExtensionNotFound)]
fun test_error_deps_add_not_extension() {
    let (scenario, extensions) = start();

    let mut deps = deps::new(&extensions);
    deps.add(&extensions, b"Other".to_string(), @0xB, 1);

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EWrongUpgradeCap)]
fun test_error_deps_add_with_wrong_upgrade_cap() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions);
    deps.add_with_upgrade_cap(&cap, b"Other".to_string(), @0xB, 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_deps_add_name_already_exists() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions);
    deps.add_with_upgrade_cap(&cap, b"AccountProtocol".to_string(), @0xB, 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_deps_add_addr_already_exists() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions);
    deps.add_with_upgrade_cap(&cap, b"Other".to_string(), @account_protocol, 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_assert_is_dep() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions);
    deps.assert_is_dep(type_name::get<Extensions>());

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::ENotCoreDep)]
fun test_error_assert_is_core_dep() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@account_extensions.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions);
    deps.add_with_upgrade_cap(&cap, b"Other".to_string(), @account_extensions, 1);
    deps.assert_is_core_dep(type_name::get<Extensions>());

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_assert_is_core_dep_not_found() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions);
    deps.assert_is_core_dep(type_name::get<Extensions>());

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_name_not_found() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions);
    deps.get_from_name(b"Other".to_string());

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_addr_not_found() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions);
    deps.get_from_addr(@0xA);

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_idx_not_found() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions);
    deps.get_idx_for_addr(@0xA);

    end(scenario, extensions);
}