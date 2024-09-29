#[test_only]
module account_protocol::account_tests;

use sui::test_utils::destroy;
use account_protocol::{
    account,
    auth,
    members,
    account_test_utils::start_world
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xa11e7;
const BOB: address = @0x10;

public struct Witness has copy, drop {}

public struct Witness2 has copy, drop {}

public struct Action has store {
    value: u64
}

// test expiration & execution time

#[test]
fun test_new_account() {
    let mut world = start_world();

    let sender = world.scenario().ctx().sender();
    let account = world.account();

    assert!(account.name() == b"kraken".to_string());
    assert!(account.thresholds().get_global_threshold() == 1);
    assert!(account.members().addresses() == vector[sender]);
    assert!(account.proposals().length() == 0);

    world.end();
} 

#[test]
fun test_create_proposal() {
    let mut world = start_world();
    let addr = world.account().addr();

    let mut proposal = world.create_proposal(
        Witness {},
        b"".to_string(),
        b"key".to_string(),
        b"proposal".to_string(),
        5,
        2,
    );

    proposal.add_action(Action { value: 1 }, Witness {});
    proposal.add_action(Action { value: 2 }, Witness {}); 

    proposal.auth().assert_is_witness(Witness {});
    proposal.auth().assert_is_account(addr);
    assert!(proposal.approved() == vector[]);
    assert!(proposal.description() == b"proposal".to_string());
    assert!(proposal.expiration_epoch() == 2);
    assert!(proposal.execution_time() == 5);
    assert!(proposal.total_weight() == 0);
    assert!(proposal.actions_length() == 2);

    world.account().add_proposal(proposal, Witness {});  
    world.end();
}

#[test]
fun test_approve_proposal() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.account().members_mut_for_testing().add(ALICE, 1, option::none(), vector[]);
    world.account().members_mut_for_testing().add(BOB, 1, option::none(), vector[]);

    world.account().member_mut(ALICE).set_weight(2);
    world.account().member_mut(BOB).set_weight(3);

    let mut proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 }, Witness {});
    proposal.add_action(Action { value: 2 }, Witness {});   
    world.account().add_proposal(proposal, Witness {});

    world.scenario().next_tx(ALICE);
    world.approve_proposal(key);
    let proposal = world.account().proposals().get(key);
    assert!(proposal.total_weight() == 2);

    world.scenario().next_tx(BOB);
    world.approve_proposal(key);
    let proposal = world.account().proposals().get(key);
    assert!(proposal.total_weight() == 5);

    world.end();        
}

#[test]
fun test_remove_approval() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.account().members_mut_for_testing().add(ALICE, 1, option::none(), vector[]);
    world.account().members_mut_for_testing().add(BOB, 1, option::none(), vector[]);

    world.account().member_mut(ALICE).set_weight(2);
    world.account().member_mut(BOB).set_weight(3);

    let mut proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 }, Witness {});
    proposal.add_action(Action { value: 2 }, Witness {});   
    world.account().add_proposal(proposal, Witness {});

    world.scenario().next_tx(ALICE);
    world.approve_proposal(key);
    let proposal = world.account().proposals().get(key);
    assert!(proposal.total_weight() == 2);

    world.scenario().next_tx(BOB);
    world.approve_proposal(key);
    let proposal = world.account().proposals().get(key);
    assert!(proposal.total_weight() == 5);

    world.scenario().next_tx(BOB);
    world.remove_approval(key);
    let proposal = world.account().proposals().get(key);
    assert!(proposal.total_weight() == 2);        

    world.end();        
}

// TODO:
// #[test]
// fun delete_proposal() {
//     let mut world = start_world();
//     let key = b"key".to_string();

//     world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
//     assert!(world.account().proposals_length() == 1);

//     let actions = world.delete_proposal(key);
//     actions.destroy_empty();
//     assert!(world.account().proposals_length() == 0);

//     world.end();
// }

#[test, expected_failure(abort_code = account::ECallerIsNotMember)]
fun test_assert_is_member_error_caller_is_not_member() {
    let mut world = start_world();

    world.scenario().next_tx(ALICE);
    world.assert_is_member();

    world.end();     
}    

#[test, expected_failure(abort_code = account::ECantBeExecutedYet)]
fun test_execute_proposal_error_cant_be_executed_yet() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.account().members_mut_for_testing().add(ALICE, 2, option::none(), vector[]);
    world.account().members_mut_for_testing().add(BOB, 3, option::none(), vector[]);

    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 5, 0);
    world.account().add_proposal(proposal, Witness {});
    world.approve_proposal(key);
    let executable = world.execute_proposal(key);

    destroy(executable);
    world.end();
}      

// TODO:
// #[test, expected_failure(abort_code = account::EHasntExpired)]
// fun delete_proposal_error_hasnt_expired() {
//     let mut world = start_world();
//     let key = b"key".to_string();

//     world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 2);
//     assert!(world.account().proposals().length() == 1);

//     let actions = world.delete_proposal(key);
//     actions.destroy_empty();
//     assert!(world.account().proposals().length() == 0);

//     world.end();
// }
