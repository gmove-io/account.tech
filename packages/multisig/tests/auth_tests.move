#[test_only]
module kraken_multisig::auth_tests;

use sui::test_utils::destroy;
use kraken_multisig::{
    multisig,
    auth,
    members,
    multisig_test_utils::start_world
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

    world.multisig().members_mut_for_testing().add(ALICE, 2, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(BOB, 3, option::none(), vector[]);

    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 });
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    executable.action_mut<Witness2, Action>(Witness2 {}, world.multisig().addr());

    destroy(executable);
    world.end();
}  

#[test, expected_failure(abort_code = auth::EWrongMultisig)]
fun test_assert_multisig_executed_error_not_multisig_executable() {
    let mut world = start_world();
    let key = b"key".to_string();

    world.multisig().members_mut_for_testing().add(ALICE, 2, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(BOB, 3, option::none(), vector[]);

    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 });
    world.approve_proposal(key);

    let uid = object::new(world.scenario().ctx());
    let mut executable = world.execute_proposal(key);
    
    let multisig = world.new_multisig();
    let _ = executable.action_mut<Witness, Action>(Witness {}, multisig.addr());

    uid.delete();
    destroy(multisig);
    destroy(executable);
    world.end();
}
