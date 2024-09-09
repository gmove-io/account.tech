#[test_only]
module kraken_multisig::thresholds_tests;

use sui::test_utils::destroy;
use kraken_multisig::{
    multisig,
    auth,
    members,
    thresholds,
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

#[test, expected_failure(abort_code = thresholds::EThresholdNotReached)]
fun execute_proposal_error_threshold_not_reached() {
    let mut world = start_world();
    let key = b"key".to_string();

    let alice = members::new_member(ALICE, 2, option::none(), vector[]);
    let bob = members::new_member(BOB, 3, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(alice);
    world.multisig().members_mut_for_testing().add(bob);

    world.create_proposal(Issuer {}, b"".to_string(), key, b"".to_string(), 0, 0);
    let executable = world.execute_proposal(key);

    destroy(executable);
    world.end();
} 