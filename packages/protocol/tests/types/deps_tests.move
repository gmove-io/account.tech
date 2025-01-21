#[test_only]
module account_protocol::deps_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    package,
};
use account_protocol::{
    deps,
    version,
    version_witness,
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

    let deps = deps::new(&extensions, false);
    // assertions
    deps.check(version::current());
    // deps getters
    assert!(deps.length() == 2);
    assert!(deps.contains_name(b"AccountProtocol".to_string()));
    assert!(deps.contains_name(b"AccountConfig".to_string()));
    assert!(deps.contains_addr(@account_protocol));
    assert!(deps.contains_addr(@0x1));
    assert!(deps.get_idx_for_addr(@account_protocol) == 0);
    assert!(deps.get_idx_for_addr(@0x1) == 1);
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

    let mut deps = deps::new(&extensions, false);
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
fun test_deps_add_unverified_allowed() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions, true);
    deps.add(&extensions, b"Other".to_string(), @0xB, 1);
    // verify
    let dep = deps.get_from_name(b"Other".to_string());
    assert!(dep.name() == b"Other".to_string());
    assert!(dep.addr() == @0xB);
    assert!(dep.version() == 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::ENotExtension)]
fun test_error_deps_add_not_extension_unverified_not_allowed() {
    let (scenario, extensions) = start();

    let mut deps = deps::new(&extensions, false);
    deps.add(&extensions, b"Other".to_string(), @0xB, 1);

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_deps_add_name_already_exists() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions, false);
    deps.add(&extensions, b"AccountProtocol".to_string(), @0xB, 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepAlreadyExists)]
fun test_error_deps_add_addr_already_exists() {
    let (mut scenario, extensions) = start();
    let cap = package::test_publish(@0xA.to_id(), scenario.ctx());

    let mut deps = deps::new(&extensions, false);
    deps.add(&extensions, b"Other".to_string(), @account_protocol, 1);

    destroy(cap);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_assert_is_dep() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions, false);
    deps.check(version_witness::new_for_testing(@0xDE9));

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_name_not_found() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions, false);
    deps.get_from_name(b"Other".to_string());

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_addr_not_found() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions, false);
    deps.get_from_addr(@0xA);

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_idx_not_found() {
    let (scenario, extensions) = start();

    let deps = deps::new(&extensions, false);
    deps.get_idx_for_addr(@0xA);

    end(scenario, extensions);
}