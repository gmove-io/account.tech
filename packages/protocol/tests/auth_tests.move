#[test_only]
module account_protocol::auth_tests;

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


#[test, expected_failure(abort_code = auth::EWrongWitness)]
fun test_action_mut_error_not_witness_module() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.account().members_mut_for_testing().add(ALICE, 2, option::none(), vector[]);
    world.account().members_mut_for_testing().add(BOB, 3, option::none(), vector[]);

    let mut proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 }, Witness {});
    world.account().add_proposal(proposal, Witness {});
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    executable.action_mut<Action, Witness2>(world.account().addr(), Witness2 {});

    destroy(executable);
    world.end();
}  

#[test, expected_failure(abort_code = auth::EWrongaccount)]
fun test_assert_account_executed_error_not_account_executable() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.account().members_mut_for_testing().add(ALICE, 2, option::none(), vector[]);
    world.account().members_mut_for_testing().add(BOB, 3, option::none(), vector[]);

    let mut proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 }, Witness {});
    world.account().add_proposal(proposal, Witness {});
    world.approve_proposal(key);

    let uid = object::new(world.scenario().ctx());
    let mut executable = world.execute_proposal(key);
    
    let account = world.new_account();
    let _ = executable.action_mut<Action, Witness>(account.addr(), Witness {});

    uid.delete();
    destroy(account);
    destroy(executable);
    world.end();
}
