#[test_only]
module account_protocol::proposals_tests;

use sui::test_utils::destroy;
use account_protocol::{
    account,
    auth,
    members,
    proposals,
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

#[test, expected_failure(abort_code = proposals::EProposalNotFound)]
fun test_approve_proposal_error_proposal_not_found() {
    let mut world = start_world();

    world.approve_proposal(b"does not exist".to_string());

    world.end();
}