#[test_only]
module kraken_actions::transfers_tests;

use sui::{
    transfer::Receiving,
    test_scenario::{most_recent_receiving_ticket, take_from_address_by_id},
    test_utils::destroy
};
use kraken_actions::{
    actions_test_utils::{start_world, World},
    transfers
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xA11CE;

public struct Object has key, store {
    id: UID
}

public struct Object2 has key, store {
    id: UID
}

#[test]
fun test_transfer_object_end_to_end() {
    let mut world = start_world();
    let key = b"send proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_transfer_objects(key, vector[vector[id1], vector[id2]], vector[OWNER, ALICE]);
    world.approve_proposal(key);

    world.scenario().next_tx(OWNER);
    let mut executable = world.execute_proposal(key);
    transfers::execute_transfer_object<Object>(&mut executable, world.multisig(), receiving1);
    transfers::confirm_transfer_objects(&mut executable);
    transfers::execute_transfer_object<Object2>(&mut executable, world.multisig(), receiving2);
    transfers::confirm_transfer_objects(&mut executable);
    transfers::complete_transfers(executable);

    world.scenario().next_tx(OWNER);
    let object1 = take_from_address_by_id<Object>(world.scenario(), OWNER, id1);
    let object2 = take_from_address_by_id<Object2>(world.scenario(), ALICE, id2);

    destroy(object1);
    destroy(object2);
    world.end();
}

#[test, expected_failure(abort_code = transfers::EDifferentLength)]
fun test_propose_transfer_object_error_different_length() {
    let mut world = start_world();
    let key = b"send proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_transfer_objects(key, vector[vector[id1], vector[id2]], vector[OWNER]);        

    world.end();
}    

fun create_transfer_and_return_receiving1(world: &mut World): Receiving<Object> {
    let multisig_address = world.multisig().addr();
    let obj = Object { id: object::new(world.scenario().ctx()) };
    transfer::public_transfer(obj, multisig_address);
    world.scenario().next_tx(OWNER);
    most_recent_receiving_ticket<Object>(&multisig_address.to_id())
}

fun create_transfer_and_return_receiving2(world: &mut World): Receiving<Object2> {
    let multisig_address = world.multisig().addr();
    let obj = Object2 { id: object::new(world.scenario().ctx()) };
    transfer::public_transfer(obj, multisig_address);
    world.scenario().next_tx(OWNER);
    most_recent_receiving_ticket<Object2>(&multisig_address.to_id())
}