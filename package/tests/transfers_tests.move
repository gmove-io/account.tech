#[test_only]
module kraken::transfers_tests;

use std::string::utf8;

use sui::test_utils::{destroy, assert_eq};
use sui::test_scenario::{
    receiving_ticket_by_id, 
    take_from_address_by_id, 
    take_from_address, 
    take_shared
};

use kraken::{
    test_utils::start_world,
    transfers::{Self, Delivery, DeliveryCap}
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
fun test_send_end_to_end() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object2(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_send(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        vector[OWNER, ALICE]
    );

    world.scenario().next_epoch(OWNER);
    world.clock().set_for_testing(101);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(utf8(b"1"));

    transfers::execute_send<Object>(&mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_send<Object2>(&mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_send(executable);

    world.scenario().next_tx(OWNER);

    // They were sent
    let object1 = take_from_address_by_id<Object>(world.scenario(), OWNER, id1);
    let object2 = take_from_address_by_id<Object2>(world.scenario(), ALICE, id2);

    destroy(object1);
    destroy(object2);
    world.end();
}

#[test]
fun test_delivery_end_to_end() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_delivery(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        ALICE
    );

    world.scenario().next_epoch(OWNER);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(utf8(b"1"));

    let (mut delivery, delivery_cap) = world.create_delivery();

    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(ALICE);

    let mut delivery = world.scenario().take_shared<Delivery>();
    let delivery_cap = world.scenario().take_from_address<DeliveryCap>(ALICE);

    // LIFO
    let object2 = delivery.claim<Object2>(&delivery_cap);
    let object1 = delivery.claim<Object>(&delivery_cap);

    assert_eq(object::id(&object1), id1);
    assert_eq(object::id(&object2), id2);
    
    delivery.confirm_delivery(delivery_cap);
    
    destroy(object1);
    destroy(object2);
    world.end();        
}

#[test]
fun test_cancel_delivery() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_delivery(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        ALICE
    );

    world.scenario().next_epoch(OWNER);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let (mut delivery, delivery_cap) = world.create_delivery();

    let mut executable = world.execute_proposal(utf8(b"1"));

    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(OWNER);

    let mut delivery = world.scenario().take_shared<Delivery>();

    // LIFO
    world.retrieve<Object2>(&mut delivery);
    world.retrieve<Object>(&mut delivery);

    world.cancel_delivery(delivery);
    world.end();          
}

#[test]
#[expected_failure(abort_code = transfers::EDifferentLength)]
fun test_propose_send_error_different_length() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    world.propose_send(
        utf8(b"1"), 
        100, 
        1, 
        utf8(b"send objects"), 
        vector[id1, id2],
        vector[OWNER]
    );        

    destroy(object1);
    destroy(object2);
    world.end();
}    

#[test]
#[expected_failure(abort_code = transfers::EDeliveryNotEmpty)]
fun test_confirm_delivery_error_delivery_not_empty() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_delivery(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        ALICE
    );

    world.scenario().next_epoch(OWNER);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(utf8(b"1"));

    let (mut delivery, delivery_cap) = world.create_delivery();

    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(ALICE);

    let mut delivery = world.scenario().take_shared<Delivery>();
    let delivery_cap = world.scenario().take_from_address<DeliveryCap>(ALICE);

    // LIFO
    let object2 = delivery.claim<Object2>(&delivery_cap);
    
    delivery.confirm_delivery(delivery_cap);

    destroy(object2);
    world.end();  
}    

#[test]
#[expected_failure(abort_code = transfers::EWrongDelivery)]
fun test_complete_delivery_error_wrong_delivery() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_delivery(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        ALICE
    );

    world.scenario().next_epoch(OWNER);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(utf8(b"1"));

    let (mut delivery, delivery_cap) = world.create_delivery();
    let (delivery2, delivery_cap2) = world.create_delivery();

    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap2, &mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_deliver(delivery, delivery_cap, executable);
    
    destroy(delivery2);
    destroy(delivery_cap2);
    world.end(); 
}   

#[test]
#[expected_failure(abort_code = transfers::EWrongDelivery)]
fun test_claim_error_wrong_delivery() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_delivery(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        ALICE
    );

    world.scenario().next_epoch(OWNER);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(utf8(b"1"));

    let (mut delivery, delivery_cap) = world.create_delivery();
    let (delivery2, delivery_cap2) = world.create_delivery();

    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(ALICE);

    let mut delivery = world.scenario().take_shared<Delivery>();
    let delivery_cap = world.scenario().take_from_address<DeliveryCap>(ALICE);

    // LIFO
    let object2 = delivery.claim<Object2>(&delivery_cap2);
    let object1 = delivery.claim<Object>(&delivery_cap);
    
    delivery.confirm_delivery(delivery_cap);
    
    destroy(delivery2);
    destroy(delivery_cap2);
    destroy(object1);
    destroy(object2);
    world.end();      
}   

#[test]
#[expected_failure(abort_code = transfers::EWrongMultisig)]
fun test_cancel_delivery_error_wrong_multisig() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_delivery(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        ALICE
    );

    world.scenario().next_epoch(OWNER);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let (mut delivery, delivery_cap) = world.create_delivery();

    let mut executable = world.execute_proposal(utf8(b"1"));

    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(OWNER);

    let delivery = world.scenario().take_shared<Delivery>();        

    let multisig2 = world.new_multisig();

    transfers::cancel_delivery(&multisig2, delivery, world.scenario().ctx());

    destroy(multisig2);
    world.end();          
}

#[test]
#[expected_failure(abort_code = transfers::EDeliveryNotEmpty)]
fun test_cancel_delivery_error_delivery_not_empty() {
    let mut world = start_world();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());

    let id1 = object::id(&object1);
    let id2 = object::id(&object2);

    let multisig_address = world.multisig().addr();

    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.propose_delivery(
        utf8(b"1"), 
        0, 
        0, 
        utf8(b"send objects"), 
        vector[id1, id2],
        ALICE
    );

    world.scenario().next_epoch(OWNER);

    world.approve_proposal(utf8(b"1"));

    world.scenario().next_tx(OWNER);

    let (mut delivery, delivery_cap) = world.create_delivery();

    let mut executable = world.execute_proposal(utf8(b"1"));

    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id1));
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving_ticket_by_id(id2));

    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(OWNER);

    let delivery = world.scenario().take_shared<Delivery>();   

    world.cancel_delivery(delivery);

    world.end();        
}

fun new_object(ctx: &mut TxContext): Object {
    Object {
        id: object::new(ctx)
    }
}

fun new_object2(ctx: &mut TxContext): Object2 {
    Object2 {
        id: object::new(ctx)
    }
}