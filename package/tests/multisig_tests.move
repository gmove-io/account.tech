#[test_only]
module kraken::multisig_tests;

use std::{
    type_name,
    string::utf8,
};

use sui::test_utils::{assert_eq, destroy};

use kraken::{
    multisig,
    test_utils::start_world
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xa11e7;
const BOB: address = @0x10;

public struct Witness has drop {}

public struct Witness2 has drop {}

public struct Action has store {
    value: u64
}

#[test]
fun test_new() {
    let mut world = start_world();

    let sender = world.scenario().ctx().sender();
    let multisig = world.multisig();

    assert_eq(multisig.name(), utf8(b"kraken"));
    assert_eq(multisig.threshold(b"global".to_string()), 1);
    assert_eq(multisig.member_addresses(), vector[sender]);
    assert_eq(multisig.proposals_length(), 0);

    world.end();
} 

#[test]
fun test_create_proposal() {
    let mut world = start_world();

    let proposal = world.create_proposal(
        Witness {},
        utf8(b"key"),
        5,
        2,
        utf8(b"proposal1"),
    );

    proposal.add_action(Action { value: 1 });
    proposal.add_action(Action { value: 2 });   

    assert_eq(proposal.approved(), vector[]);
    assert_eq(proposal.module_witness(), type_name::get<Witness>());
    assert_eq(proposal.description(), utf8(b"proposal1"));
    assert_eq(proposal.expiration_epoch(), 2);
    assert_eq(proposal.execution_time(), 5);
    assert_eq(proposal.total_weight(), 0);
    assert_eq(proposal.actions_length(), 2);

    world.end();
}

#[test]
fun test_approve_proposal() {
    let mut world = start_world();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let proposal = world.create_proposal(
        Witness {},
        utf8(b"key"),
        5,
        2,
        utf8(b"proposal1"),
    );

    proposal.add_action(Action { value: 1 });
    proposal.add_action(Action { value: 2 });   

    assert_eq(proposal.approved(), vector[]);
    assert_eq(proposal.module_witness(), type_name::get<Witness>());
    assert_eq(proposal.description(), utf8(b"proposal1"));
    assert_eq(proposal.expiration_epoch(), 2);
    assert_eq(proposal.execution_time(), 5);
    assert_eq(proposal.total_weight(), 0);
    assert_eq(proposal.actions_length(), 2);

    world.scenario().next_tx(ALICE);

    world.approve_proposal(utf8(b"key"));

    let proposal = world.multisig().proposal(&utf8(b"key"));

    assert_eq(proposal.total_weight(), 2);

    world.scenario().next_tx(BOB);

    world.approve_proposal(utf8(b"key"));

    let proposal = world.multisig().proposal(&utf8(b"key"));

    assert_eq(proposal.total_weight(), 5);

    world.end();        
}

#[test]
fun test_remove_approval() {
    let mut world = start_world();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let proposal = world.create_proposal(
        Witness {},
        utf8(b"key"),
        5,
        2,
        utf8(b"proposal1"),
    );

    proposal.add_action(Action { value: 1 });
    proposal.add_action(Action { value: 2 });   

    assert_eq(proposal.approved(), vector[]);
    assert_eq(proposal.module_witness(), type_name::get<Witness>());
    assert_eq(proposal.description(), utf8(b"proposal1"));
    assert_eq(proposal.expiration_epoch(), 2);
    assert_eq(proposal.execution_time(), 5);
    assert_eq(proposal.total_weight(), 0);
    assert_eq(proposal.actions_length(), 2);

    world.scenario().next_tx(ALICE);

    world.approve_proposal(utf8(b"key"));

    let proposal = world.multisig().proposal(&utf8(b"key"));

    assert_eq(proposal.total_weight(), 2);

    world.scenario().next_tx(BOB);

    world.approve_proposal(utf8(b"key"));

    let proposal = world.multisig().proposal(&utf8(b"key"));

    assert_eq(proposal.total_weight(), 5);

    world.scenario().next_tx(BOB);

    world.remove_approval(utf8(b"key"));

    let proposal = world.multisig().proposal(&utf8(b"key"));

    assert_eq(proposal.total_weight(), 2);        

    world.end();        
}

#[test]
fun test_delete_proposal() {
    let mut world = start_world();

    world.create_proposal(
        Witness {},
        utf8(b"key"),
        5,
        2,
        utf8(b"proposal1"),
    );        

    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    assert_eq(world.multisig().proposals_length(), 1);

    let actions = world.delete_proposal(utf8(b"key"));

    actions.destroy_empty();

    assert_eq(world.multisig().proposals_length(), 0);

    world.end();
}

#[test]
fun test_setters() {
    let mut world = start_world();

    assert_eq(world.multisig().name(), utf8(b"kraken"));
    assert_eq(world.multisig().version(), 1);
    assert_eq(world.multisig().threshold(b"global".to_string()), 1);

    world.multisig().set_name(utf8(b"krakenV2"));
    world.multisig().set_version(2);
    world.multisig().set_threshold(b"global".to_string(), 3);

    assert_eq(world.multisig().name(), utf8(b"krakenV2"));
    assert_eq(world.multisig().version(), 2);
    assert_eq(world.multisig().threshold(b"global".to_string()), 3);

    world.end();        
}

#[test]
#[allow(implicit_const_copy)]
fun test_members_end_to_end() {
    let mut world = start_world();

    assert_eq(world.multisig().is_member(&ALICE), false);
    assert_eq(world.multisig().is_member(&BOB), false);

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    assert_eq(world.multisig().is_member(&ALICE), true);
    assert_eq(world.multisig().is_member(&BOB), true);
    assert_eq(world.multisig().member(&ALICE).weight(), 2);
    assert_eq(world.multisig().member(&BOB).weight(), 3);
    assert_eq(world.multisig().member(&ALICE).account_id().is_none(), true);
    assert_eq(world.multisig().member(&BOB).account_id().is_none(), true);

    world.scenario().next_tx(ALICE);

    let id1 = object::new(world.scenario().ctx());

    world.register_account_id(id1.uid_to_inner());

    world.assert_is_member();
    assert_eq(world.multisig().member(&ALICE).account_id().is_none(), false);
    assert_eq(world.multisig().member(&ALICE).account_id().extract(), id1.uid_to_inner());
    assert_eq(world.multisig().member(&BOB).account_id().is_none(), true);

    id1.delete();

    world.scenario().next_tx(ALICE);

    world.unregister_account_id();      

    assert_eq(world.multisig().member(&ALICE).account_id().is_none(), true);

    world.scenario().next_tx(OWNER);

    world.multisig().remove_members(&mut vector[ALICE]);

    assert_eq(world.multisig().is_member(&ALICE), false);

    world.end();          
}

#[test]
#[expected_failure(abort_code = multisig::ECallerIsNotMember)]
fun test_assert_is_member_error_caller_is_not_member() {
    let mut world = start_world();

    world.scenario().next_tx(ALICE);

    world.assert_is_member();

    world.end();     
}    

#[test]
#[expected_failure(abort_code = multisig::EThresholdNotReached)]
fun test_execute_proposal_error_threshold_not_reached() {
    let mut world = start_world();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 1);
    world.multisig().modify_weight(BOB, 3);

    let key = utf8(b"key");

    world.create_proposal(
        Witness {},
        key,
        0,
        2,
        utf8(b"proposal1"),
    );

    world.multisig().set_threshold(b"global".to_string(), 3);

    world.scenario().next_tx(ALICE);

    world.approve_proposal(key);

    let executable = world.execute_proposal(key);

    destroy(executable);
    world.end();
} 

#[test]
#[expected_failure(abort_code = multisig::ECantBeExecutedYet)]
fun test_execute_proposal_error_cant_be_executed_yet() {
    let mut world = start_world();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let key = utf8(b"key");

    world.create_proposal(
        Witness {},
        key,
        5,
        2,
        utf8(b"proposal1"),
    );

    world.multisig().set_threshold(b"global".to_string(), 3);

    world.scenario().next_tx(BOB);

    world.approve_proposal(key);

    let executable = world.execute_proposal(key);

    destroy(executable);
    world.end();
}      

#[test]
#[expected_failure(abort_code = multisig::ENotIssuerModule)]
fun test_action_mut_error_not_issuer_module() {
    let mut world = start_world();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let key = utf8(b"key");

    let proposal = world.create_proposal(
        Witness {},
        key,
        0,
        0,
        utf8(b"proposal1"),
    );

    proposal.add_action(Action { value: 1 });

    world.multisig().set_threshold(b"global".to_string(), 3);

    world.scenario().next_tx(BOB);

    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);

    executable.action_mut<Witness2, Action>(Witness2 {}, 0);

    destroy(executable);
    world.end();
}  

#[test]
#[expected_failure(abort_code = multisig::EHasntExpired)]
fun test_delete_proposal_error_hasnt_expired() {
    let mut world = start_world();

    world.create_proposal(
        Witness {},
        utf8(b"key"),
        5,
        2,
        utf8(b"proposal1"),
    );        

    assert_eq(world.multisig().proposals_length(), 1);

    let actions = world.delete_proposal(utf8(b"key"));

    actions.destroy_empty();

    assert_eq(world.multisig().proposals_length(), 0);

    world.end();
}

#[test]
#[expected_failure(abort_code = multisig::EWrongVersion)]
fun test_assert_version_error_wrong_version() {
    let mut world = start_world();

    world.multisig().set_version(2);

    world.multisig().assert_version();

    world.end();
}

#[test]
#[expected_failure(abort_code = multisig::ENotMultisigExecutable)]
fun test_assert_multisig_executed_error_not_multisig_executable() {
    let mut world = start_world();

    world.multisig().add_members(
        &mut vector[ALICE, BOB],
    );
    world.multisig().modify_weight(ALICE, 2);
    world.multisig().modify_weight(BOB, 3);

    let key = utf8(b"key");

    let proposal = world.create_proposal(
        Witness {},
        key,
        0,
        0,
        utf8(b"proposal1"),
    );

    proposal.add_action(Action { value: 1 });

    world.multisig().set_threshold(b"global".to_string(), 3);

    world.scenario().next_tx(BOB);

    world.approve_proposal(key);

    let id = object::new(world.scenario().ctx());

    let multisig = multisig::new(utf8(b"krakenV3"), id.uid_to_inner(), world.scenario().ctx());

    let executable = world.execute_proposal(key);

    multisig.assert_executed(&executable);
    
    id.delete();
    destroy(multisig);
    destroy(executable);
    world.end();
}

#[test]
#[expected_failure(abort_code = multisig::EProposalNotFound)]
fun test_approve_proposal_error_proposal_not_found() {
    let mut world = start_world();

    world.approve_proposal(utf8(b"does not exist"));

    world.end();
}

#[test]
#[expected_failure(abort_code = multisig::EMemberNotFound)]
fun test_register_account_id_error_member_not_found() {
    let mut world = start_world();

    let id = object::new(world.scenario().ctx());

    world.scenario().next_tx(ALICE);

    world.register_account_id(id.uid_to_inner());

    id.delete();
    world.end();
}

#[test]
#[expected_failure(abort_code = multisig::EMemberNotFound)]
fun test_unregister_account_id_error_member_not_found() {
    let mut world = start_world();

    let id = object::new(world.scenario().ctx());

    world.scenario().next_tx(ALICE);

    world.unregister_account_id();

    id.delete();
    world.end();
}
