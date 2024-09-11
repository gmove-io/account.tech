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

public struct Issuer has copy, drop {}

public struct Issuer2 has copy, drop {}

public struct Action has store {
    value: u64
}


#[test, expected_failure(abort_code = auth::EWrongIssuer)]
fun test_action_mut_error_not_issuer_module() {
    let mut world = start_world();
    let key = b"key".to_string();

    let alice = members::new_member(ALICE, 2, option::none(), vector[]);
    let bob = members::new_member(BOB, 3, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(alice);
    world.multisig().members_mut_for_testing().add(bob);

    let proposal = world.create_proposal(Issuer {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 });
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    executable.action_mut<Issuer2, Action>(Issuer2 {}, world.multisig().addr());

    destroy(executable);
    world.end();
}  

#[test, expected_failure(abort_code = auth::EWrongMultisig)]
fun test_assert_multisig_executed_error_not_multisig_executable() {
    let mut world = start_world();
    let key = b"key".to_string();

    let alice = members::new_member(ALICE, 2, option::none(), vector[]);
    let bob = members::new_member(BOB, 3, option::none(), vector[]);

    world.multisig().members_mut_for_testing().add(alice);
    world.multisig().members_mut_for_testing().add(bob);

    let proposal = world.create_proposal(Issuer {}, b"".to_string(), key, b"".to_string(), 0, 0);
    proposal.add_action(Action { value: 1 });
    world.approve_proposal(key);

    let uid = object::new(world.scenario().ctx());
    let mut executable = world.execute_proposal(key);
    
    let multisig = world.new_multisig();
    let _ = executable.action_mut<Issuer, Action>(Issuer {}, multisig.addr());

    uid.delete();
    destroy(multisig);
    destroy(executable);
    world.end();
}
