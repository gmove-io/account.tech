#[test_only]
module kraken::multisig_tests;

use std::{
    type_name,
};
use sui::test_utils::destroy;
use kraken::{
    multisig,
    test_utils::start_world
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xa11e7;
const BOB: address = @0x10;

public struct Auth has drop {}

public struct Auth2 has drop {}

public struct Action has store {
    value: u64
}

// test expiration & execution time

#[test]
fun new_multisig() {
    let mut world = start_world();

    let sender = world.scenario().ctx().sender();
    let multisig = world.multisig();

    assert!(multisig.name() == b"kraken".to_string());
    assert!(multisig.threshold(b"global".to_string()) == 1);
    assert!(multisig.member_addresses() == vector[sender]);
    assert!(multisig.proposals_length() == 0);

    world.end();
} 

#[test]
fun create_proposal() {
    let mut world = start_world();

    let proposal = world.create_proposal(
        Auth {},
        b"key".to_string(),
        5,
        2,
        b"proposal".to_string(),
    );

    proposal.add_action(Action { value: 1 });
    proposal.add_action(Action { value: 2 });   

    assert!(proposal.approved() == vector[]);
    assert!(proposal.module_witness() == type_name::get<Auth>());
    assert!(proposal.description() == b"proposal".to_string());
    assert!(proposal.expiration_epoch() == 2);
    assert!(proposal.execution_time() == 5);
    assert!(proposal.total_weight() == 0);
    assert!(proposal.actions_length() == 2);

    world.end();
}

#[test]
fun approve_proposal() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    proposal.add_action(Action { value: 1 });
    proposal.add_action(Action { value: 2 });   

    world.scenario().next_tx(ALICE);
    world.approve_proposal(key);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.total_weight() == 2);

    world.scenario().next_tx(BOB);
    world.approve_proposal(key);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.total_weight() == 5);

    world.end();        
}

#[test]
fun remove_approval() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    proposal.add_action(Action { value: 1 });
    proposal.add_action(Action { value: 2 });   

    world.scenario().next_tx(ALICE);
    world.approve_proposal(key);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.total_weight() == 2);

    world.scenario().next_tx(BOB);
    world.approve_proposal(key);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.total_weight() == 5);

    world.scenario().next_tx(BOB);
    world.remove_approval(key);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.total_weight() == 2);        

    world.end();        
}

#[test]
fun delete_proposal() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    assert!(world.multisig().proposals_length() == 1);

    let actions = world.delete_proposal(key);
    actions.destroy_empty();
    assert!(world.multisig().proposals_length() == 0);

    world.end();
}

#[test]
fun test_setters() {
    let mut world = start_world();

    assert!(world.multisig().name() == b"kraken".to_string());
    assert!(world.multisig().version() == 1);
    assert!(world.multisig().threshold(b"global".to_string()) == 1);

    world.multisig().set_name(b"krakenV2".to_string());
    world.multisig().set_version(2);
    world.multisig().set_threshold(b"global".to_string(), 3);

    assert!(world.multisig().name() == b"krakenV2".to_string());
    assert!(world.multisig().version() == 2);
    assert!(world.multisig().threshold(b"global".to_string()) == 3);

    world.end();        
}

#[test, allow(implicit_const_copy)]
fun members_end_to_end() {
    let mut world = start_world();

    assert!(!world.multisig().is_member(&ALICE));
    assert!(!world.multisig().is_member(&BOB));

    world.multisig().add_members(&mut vector[ALICE, BOB]);
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    assert!(world.multisig().is_member(&ALICE));
    assert!(world.multisig().is_member(&BOB));
    assert!(world.multisig().member(&ALICE).weight() == 2);
    assert!(world.multisig().member(&BOB).weight() == 3);
    assert!(world.multisig().member(&ALICE).account_id().is_none());
    assert!(world.multisig().member(&BOB).account_id().is_none());

    world.scenario().next_tx(ALICE);
    let uid = object::new(world.scenario().ctx());
    world.register_account_id(uid.uid_to_inner());
    world.assert_is_member();
    assert!(!world.multisig().member(&ALICE).account_id().is_none());
    assert!(world.multisig().member(&ALICE).account_id().extract() == uid.uid_to_inner());
    assert!(world.multisig().member(&BOB).account_id().is_none());
    uid.delete();

    world.scenario().next_tx(ALICE);
    world.unregister_account_id();      
    assert!(world.multisig().member(&ALICE).account_id().is_none());

    world.scenario().next_tx(OWNER);
    world.multisig().remove_members(&mut vector[ALICE]);
    assert!(!world.multisig().is_member(&ALICE));

    world.end();          
}

#[test, expected_failure(abort_code = multisig::ECallerIsNotMember)]
fun assert_is_member_error_caller_is_not_member() {
    let mut world = start_world();

    world.scenario().next_tx(ALICE);
    world.assert_is_member();

    world.end();     
}    

#[test, expected_failure(abort_code = multisig::EThresholdNotReached)]
fun execute_proposal_error_threshold_not_reached() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.multisig().add_members(&mut vector[ALICE, BOB]);
    world.multisig().modify_weight(ALICE, 1);
    world.multisig().modify_weight(BOB, 3);

    world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    let executable = world.execute_proposal(key);

    destroy(executable);
    world.end();
} 

#[test, expected_failure(abort_code = multisig::ECantBeExecutedYet)]
fun execute_proposal_error_cant_be_executed_yet() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.multisig().add_members(&mut vector[ALICE, BOB]);
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    world.create_proposal(Auth {}, key, 5, 0, b"".to_string());
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);

    destroy(executable);
    world.end();
}      

#[test, expected_failure(abort_code = multisig::ENotIssuerModule)]
fun action_mut_error_not_issuer_module() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.multisig().add_members(&mut vector[ALICE, BOB]);
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    proposal.add_action(Action { value: 1 });
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    executable.action_mut<Auth2, Action>(Auth2 {}, 0);

    destroy(executable);
    world.end();
}  

#[test, expected_failure(abort_code = multisig::EHasntExpired)]
fun delete_proposal_error_hasnt_expired() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.create_proposal(Auth {}, key, 0, 2, b"".to_string());
    assert!(world.multisig().proposals_length() == 1);

    let actions = world.delete_proposal(key);
    actions.destroy_empty();
    assert!(world.multisig().proposals_length() == 0);

    world.end();
}

#[test, expected_failure(abort_code = multisig::EWrongVersion)]
fun assert_version_error_wrong_version() {
    let mut world = start_world();

    world.multisig().set_version(2);
    world.multisig().assert_version();

    world.end();
}

#[test, expected_failure(abort_code = multisig::ENotMultisigExecutable)]
fun assert_multisig_executed_error_not_multisig_executable() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.multisig().add_members(&mut vector[ALICE, BOB]);
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    proposal.add_action(Action { value: 1 });
    world.approve_proposal(key);

    let uid = object::new(world.scenario().ctx());
    let multisig = multisig::new(b"krakenV3".to_string(), uid.uid_to_inner(), world.scenario().ctx());
    let executable = world.execute_proposal(key);
    multisig.assert_executed(&executable);
    
    uid.delete();
    destroy(multisig);
    destroy(executable);
    world.end();
}

#[test, expected_failure(abort_code = multisig::EProposalNotFound)]
fun approve_proposal_error_proposal_not_found() {
    let mut world = start_world();

    world.approve_proposal(b"does not exist".to_string());

    world.end();
}

#[test, expected_failure(abort_code = multisig::EMemberNotFound)]
fun register_account_id_error_member_not_found() {
    let mut world = start_world();
    let id = object::new(world.scenario().ctx());

    world.scenario().next_tx(ALICE);
    world.register_account_id(id.uid_to_inner());

    id.delete();
    world.end();
}

#[test, expected_failure(abort_code = multisig::EMemberNotFound)]
fun unregister_account_id_error_member_not_found() {
    let mut world = start_world();
    let id = object::new(world.scenario().ctx());

    world.scenario().next_tx(ALICE);
    world.unregister_account_id();

    id.delete();
    world.end();
}
