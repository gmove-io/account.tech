// #[test_only]
// module kraken_actions::config_tests;

// use kraken_actions::{
//     config,
//     test_utils::{Self, start_world},
// };

// const OWNER: address = @0xBABE;
// const ALICE: address = @0xA11CE;
// const BOB: address = @0xB0B;

// #[test]
// fun name_end_to_end() {
//     let mut world = start_world();
//     let key = b"name proposal".to_string();

//     world.propose_name(
//         key,
//         b"new name".to_string(),
//     );
//     world.approve_proposal(key);
//     let executable = world.execute_proposal(key);    
//     config::execute_name(executable, world.multisig());

//     assert!(world.multisig().name() == b"new name".to_string());
//     world.end();     
// }

// #[test]
// #[allow(implicit_const_copy)]
// fun modify_rules_end_to_end() {
//     let mut world = start_world();
//     let sender = world.scenario().ctx().sender();
//     let multisig = world.multisig();
//     let key = b"modify proposal".to_string();

//     assert!(multisig.name() == b"kraken".to_string());
//     assert!(multisig.threshold(b"global".to_string()) == 1);
//     assert!(multisig.member_addresses() == vector[sender]);
//     assert!(multisig.proposals_length() == 0);
//     assert!(*multisig.get_weights_for_roles().get(&b"global".to_string()) == 1);

//     let role = test_utils::role(b"config");
//     world.propose_modify_rules(
//         key,
//         vector[ALICE, BOB],
//         vector[OWNER],
//         vector[ALICE],
//         vector[2],
//         vector[ALICE, BOB],
//         vector[vector[role], vector[role]],
//         vector[ALICE],
//         vector[vector[role]],
//         vector[b"global".to_string(), role],
//         vector[3, 1],
//     );
//     world.approve_proposal(key);

//     let executable = world.execute_proposal(key);
//     config::execute_modify_rules(executable, world.multisig());

//     let multisig = world.multisig();

//     assert!(multisig.member_addresses() == vector[BOB, ALICE]);
//     assert!(multisig.member(&ALICE).weight() == 2);
//     assert!(multisig.member(&BOB).weight() == 1);
//     assert!(multisig.member(&ALICE).roles() == vector[b"global".to_string()]);
//     assert!(multisig.member(&BOB).roles() == vector[b"global".to_string(), role]);

//     assert!(multisig.threshold(b"global".to_string()) == 3);
//     assert!(multisig.threshold(role) == 1);
//     assert!(*multisig.get_weights_for_roles().get(&b"global".to_string()) == 3); 
//     assert!(*multisig.get_weights_for_roles().get(&role) == 1); 

//     world.end();        
// }

// // TODO: add others

// #[test]
// fun migrate_end_to_end() {
//     let mut world = start_world();

//     let key = b"migrate proposal".to_string();

//     assert!(world.multisig().version() == 1);

//     world.propose_migrate(key, 2);
//     world.approve_proposal(key);

//     let executable = world.execute_proposal(key);    
//     config::execute_migrate(executable, world.multisig());

//     assert!(world.multisig().version() == 2);

//     world.end();     
// }

// #[test, expected_failure(abort_code = config::EAlreadyMember)]
// fun verify_new_config_error_added_already_member() {
//     let mut world = start_world();
//     let key = b"modify proposal".to_string();

//     world.propose_members(
//         key,
//         vector[OWNER],
//         vector[],
//     );
//     world.approve_proposal(key);

//     let executable = world.execute_proposal(key);
//     config::execute_modify_rules(executable, world.multisig());

//     world.end();         
// }   

// #[test, expected_failure(abort_code = config::ENotMember)]
// fun verify_new_config_error_removed_not_member() {
//     let mut world = start_world();
//     let key = b"modify proposal".to_string();

//     world.propose_members(
//         key,
//         vector[],
//         vector[ALICE],
//     );
//     world.approve_proposal(key);

//     let executable = world.execute_proposal(key);
//     config::execute_modify_rules(executable, world.multisig());

//     world.end();         
// }

// #[test, expected_failure(abort_code = config::ENotMember)]
// fun verify_new_config_error_modified_not_member() {
//     let mut world = start_world();
//     let key = b"modify proposal".to_string();

//     world.propose_weights(
//         key,
//         vector[ALICE],
//         vector[2],
//     );
//     world.approve_proposal(key);

//     let executable = world.execute_proposal(key);
//     config::execute_modify_rules(executable, world.multisig());

//     world.end();         
// }

// #[test, expected_failure(abort_code = config::EThresholdTooHigh)]
// fun verify_new_config_error_threshold_too_high() {
//     let mut world = start_world();
//     let key = b"modify proposal".to_string();

//     world.propose_thresholds(
//         key,
//         vector[b"global".to_string()],
//         vector[4],
//     );
//     world.approve_proposal(key);
    
//     let executable = world.execute_proposal(key);
//     config::execute_modify_rules(executable, world.multisig());

//     world.end();         
// }

// #[test, expected_failure(abort_code = config::EThresholdNull)]
// fun verify_new_config_error_threshold_null() {
//     let mut world = start_world();
//     let key = b"modify proposal".to_string();

//     world.propose_thresholds(
//         key,
//         vector[b"global".to_string()],
//         vector[0],
//     );
//     world.approve_proposal(key);

//     let executable = world.execute_proposal(key);
//     config::execute_modify_rules(executable, world.multisig());

//     world.end();         
// }  
