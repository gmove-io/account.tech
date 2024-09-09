#[test_only]
module kraken_multisig::proposals_tests;

use sui::test_utils::destroy;
use kraken_multisig::{
    multisig,
    auth,
    members,
    proposals,
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

#[test, expected_failure(abort_code = proposals::EProposalNotFound)]
fun approve_proposal_error_proposal_not_found() {
    let mut world = start_world();

    world.approve_proposal(b"does not exist".to_string());

    world.end();
}