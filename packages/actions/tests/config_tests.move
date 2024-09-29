#[test_only]
module account_actions::config_tests;

use account_actions::{
    config,
    actions_test_utils::{Self, start_world},
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

#[test]
fun test_config_name_end_to_end() {
    let mut world = start_world();
    let key = b"name proposal".to_string();

    world.propose_config_name(
        key,
        b"new name".to_string(),
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);    
    config::execute_config_name(executable, world.account());

    assert!(world.account().name() == b"new name".to_string());
    world.end();     
}

#[test]
#[allow(implicit_const_copy)]
fun test_config_rules_end_to_end() {
    let mut world = start_world();
    let sender = world.scenario().ctx().sender();
    let account = world.account();
    let key = b"rules proposal".to_string();

    assert!(account.name() == b"Kraken".to_string());
    assert!(account.thresholds().get_global_threshold() == 1);
    assert!(account.members().addresses() == vector[sender]);
    assert!(account.member(sender).weight() == 1);
    assert!(account.proposals().length() == 0);

    let role = actions_test_utils::role(b"config");
    world.propose_config_rules(
        key,
        vector[ALICE, BOB], // removes OWNER
        vector[2, 1],
        vector[vector[], vector[role]],
        3,
        vector[role],
        vector[1],
    );
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    let account = world.account();

    assert!(account.members().addresses() == vector[ALICE, BOB]);
    assert!(account.member(ALICE).weight() == 2);
    assert!(account.member(BOB).weight() == 1);
    assert!(account.member(ALICE).roles() == vector[]);
    assert!(account.member(BOB).roles() == vector[role]);

    assert!(account.thresholds().get_global_threshold() == 3);
    assert!(account.thresholds().get_role_threshold(role) == 1);

    world.end();        
}

// TODO: fix
// #[test]
// fun test_config_deps_end_to_end() {
//     let mut world = start_world();

//     let key = b"deps proposal".to_string();

//     assert!(world.account().deps().get_idx(@account_protocol) == 0);
//     assert!(world.account().deps().get_idx(@0xCAFE) == 1);
//     assert!(world.account().deps().get_version(@account_protocol) == 1);
//     assert!(world.account().deps().get_version(@0xCAFE) == 1);

//     extensions::add(&world.extensions(), name, package, version)

//     world.propose_config_deps(
//         key, 
//         vector[b"AccountProtocol".to_string(), b"AccountActions".to_string(), b"External".to_string()],
//         vector[@account_protocol, @0xCAFE, @0xAAA],
//         vector[2, 3, 1],
//     );
//     world.approve_proposal(key);
//     let executable = world.execute_proposal(key);    
//     config::execute_config_deps(executable, world.account());

//     assert!(world.account().deps().get_idx(@account_protocol) == 0);
//     assert!(world.account().deps().get_idx(@0xCAFE) == 1);
//     assert!(world.account().deps().get_idx(@0xAAA) == 2);
//     assert!(world.account().deps().get_version(@account_protocol) == 2);
//     assert!(world.account().deps().get_version(@0xCAFE) == 3);
//     assert!(world.account().deps().get_version(@0xAAA) == 1);

//     world.end();     
// }

#[test]
fun test_verify_config_no_error_no_member_has_role() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();
    let role = actions_test_utils::role(b"config");

    world.propose_config_rules(
        key,
        vector[OWNER],
        vector[1],
        vector[vector[]],
        1,
        vector[role],
        vector[1],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

#[test, expected_failure(abort_code = config::EThresholdNull)]
fun test_verify_config_error_global_threshold_null() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();

    world.propose_config_rules(
        key,
        vector[OWNER],
        vector[1],
        vector[vector[]],
        0,
        vector[],
        vector[],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

#[test, expected_failure(abort_code = config::EThresholdTooHigh)]
fun test_verify_config_error_global_threshold_too_high() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();
    let role = actions_test_utils::role(b"config");

    world.propose_config_rules(
        key,
        vector[OWNER],
        vector[1],
        vector[vector[]],
        4,
        vector[role],
        vector[1],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

#[test, expected_failure(abort_code = config::EThresholdTooHigh)]
fun test_verify_config_error_role_threshold_too_high() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();
    let role = actions_test_utils::role(b"config");

    world.propose_config_rules(
        key,
        vector[OWNER],
        vector[1],
        vector[vector[role]],
        1,
        vector[role],
        vector[2],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

#[test, expected_failure(abort_code = config::ERoleDoesntExist)]
fun test_verify_config_error_threshold_too_high() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();
    let role = actions_test_utils::role(b"config");

    world.propose_config_rules(
        key,
        vector[OWNER],
        vector[1],
        vector[vector[role]],
        1,
        vector[],
        vector[],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

#[test, expected_failure(abort_code = config::EMembersNotSameLength)]
fun test_verify_config_error_members_not_same_length() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();
    let role = actions_test_utils::role(b"config");

    world.propose_config_rules(
        key,
        vector[OWNER, ALICE],
        vector[1],
        vector[vector[role]],
        1,
        vector[],
        vector[],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

#[test, expected_failure(abort_code = config::EMembersNotSameLength)]
fun test_verify_config_error_members_not_same_length_2() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();
    let role = actions_test_utils::role(b"config");

    world.propose_config_rules(
        key,
        vector[OWNER, ALICE],
        vector[1, 2],
        vector[vector[role]],
        1,
        vector[],
        vector[],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

#[test, expected_failure(abort_code = config::ERolesNotSameLength)]
fun test_verify_config_error_roles_not_same_length() {
    let mut world = start_world();
    let key = b"rules proposal".to_string();
    let role = actions_test_utils::role(b"config");

    world.propose_config_rules(
        key,
        vector[OWNER],
        vector[1],
        vector[vector[]],
        1,
        vector[role],
        vector[],
    );
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);
    config::execute_config_rules(executable, world.account());

    world.end();         
}

