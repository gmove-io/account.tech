#[test_only]
module kraken_account::members_tests;

use sui::test_utils::destroy;
use kraken_account::{
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

#[test, allow(implicit_const_copy)]
fun test_members_end_to_end() {
    let mut world = start_world();

    assert!(!world.account().members().is_member(ALICE));
    assert!(!world.account().members().is_member(BOB));

    world.account().members_mut_for_testing().add(ALICE, 2, option::none(), vector[]);
    world.account().members_mut_for_testing().add(BOB, 3, option::none(), vector[]);

    assert!(world.account().members().is_member(ALICE));
    assert!(world.account().members().is_member(BOB));
    assert!(world.account().member(ALICE).weight() == 2);
    assert!(world.account().member(BOB).weight() == 3);
    assert!(world.account().member(ALICE).user_id().is_none());
    assert!(world.account().member(BOB).user_id().is_none());

    world.scenario().next_tx(ALICE);
    let uid = object::new(world.scenario().ctx());
    world.account().member_mut(ALICE).register_user_id(uid.uid_to_inner());
    world.assert_is_member();
    assert!(!world.account().member(ALICE).user_id().is_none());
    assert!(world.account().member(ALICE).user_id().extract() == uid.uid_to_inner());
    assert!(world.account().member(BOB).user_id().is_none());
    uid.delete();

    world.scenario().next_tx(ALICE);
    world.account().member_mut(ALICE).unregister_user_id();      
    assert!(world.account().member(ALICE).user_id().is_none());

    world.scenario().next_tx(OWNER);
    world.account().members_mut_for_testing().remove(ALICE);
    assert!(!world.account().members().is_member(ALICE));

    world.end();          
}