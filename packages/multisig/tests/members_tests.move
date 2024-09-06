#[test_only]
module kraken_multisig::members_tests;

use sui::test_utils::destroy;
use kraken_multisig::{
    multisig,
    auth,
    members,
    test_utils::start_world
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xa11e7;
const BOB: address = @0x10;

public struct Issuer has copy, drop {}

public struct Issuer2 has copy, drop {}

public struct Action has store {
    value: u64
}

#[test, allow(implicit_const_copy)]
fun members_end_to_end() {
    let mut world = start_world();

    assert!(!world.multisig().members().is_member(ALICE));
    assert!(!world.multisig().members().is_member(BOB));

    let alice = members::new_member(ALICE, 2, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(alice);
    let bob = members::new_member(BOB, 3, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(bob);

    assert!(world.multisig().members().is_member(ALICE));
    assert!(world.multisig().members().is_member(BOB));
    assert!(world.multisig().member(ALICE).weight() == 2);
    assert!(world.multisig().member(BOB).weight() == 3);
    assert!(world.multisig().member(ALICE).account_id().is_none());
    assert!(world.multisig().member(BOB).account_id().is_none());

    world.scenario().next_tx(ALICE);
    let uid = object::new(world.scenario().ctx());
    world.multisig().member_mut(ALICE).register_account_id(uid.uid_to_inner());
    world.assert_is_member();
    assert!(!world.multisig().member(ALICE).account_id().is_none());
    assert!(world.multisig().member(ALICE).account_id().extract() == uid.uid_to_inner());
    assert!(world.multisig().member(BOB).account_id().is_none());
    uid.delete();

    world.scenario().next_tx(ALICE);
    world.multisig().member_mut(ALICE).unregister_account_id();      
    assert!(world.multisig().member(ALICE).account_id().is_none());

    world.scenario().next_tx(OWNER);
    world.multisig().members_mut_for_testing().remove(ALICE);
    assert!(!world.multisig().members().is_member(ALICE));

    world.end();          
}