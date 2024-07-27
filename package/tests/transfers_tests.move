#[test_only]
module kraken::transfers_tests;

use sui::{
    transfer::Receiving,
    test_scenario::{most_recent_receiving_ticket, take_from_address_by_id, take_from_address, take_shared},
    test_utils::destroy
};
use kraken::{
    test_utils::{start_world, World},
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
fun send_end_to_end() {
    let mut world = start_world();
    let key = b"send proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_send(key, vector[id1, id2], vector[OWNER, ALICE]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    transfers::execute_send<Object>(&mut executable, world.multisig(), receiving1);
    transfers::execute_send<Object2>(&mut executable, world.multisig(), receiving2);
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
fun delivery_end_to_end() {
    let mut world = start_world();
    let key = b"delivery proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_delivery(key, vector[id1, id2], ALICE);
    world.approve_proposal(key);

    let (mut delivery, delivery_cap) = world.create_delivery();
    let mut executable = world.execute_proposal(key);
    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving1);
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving2);
    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(ALICE);
    let mut delivery = world.scenario().take_shared<Delivery>();
    let delivery_cap = world.scenario().take_from_address<DeliveryCap>(ALICE);
    // LIFO
    let object2 = delivery.claim<Object2>(&delivery_cap);
    let object1 = delivery.claim<Object>(&delivery_cap);

    assert!(object::id(&object1) == id1);
    assert!(object::id(&object2) == id2);
    
    delivery.confirm_delivery(delivery_cap);
    
    destroy(object1);
    destroy(object2);
    world.end();        
}

#[test]
fun cancel_delivery() {
    let mut world = start_world();
    let key = b"send proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_delivery(key, vector[id1, id2], ALICE);
    world.approve_proposal(key);

    let (mut delivery, delivery_cap) = world.create_delivery();
    let mut executable = world.execute_proposal(key);
    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving1);
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving2);
    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(OWNER);
    let mut delivery = world.scenario().take_shared<Delivery>();
    // LIFO
    world.retrieve<Object2>(&mut delivery);
    world.retrieve<Object>(&mut delivery);

    world.cancel_delivery(delivery);
    world.end();          
}

#[test, expected_failure(abort_code = transfers::EDifferentLength)]
fun propose_send_error_different_length() {
    let mut world = start_world();
    let key = b"send proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_send(key, vector[id1, id2], vector[OWNER]);        

    world.end();
}    

#[test, expected_failure(abort_code = transfers::EDeliveryNotEmpty)]
fun confirm_delivery_error_delivery_not_empty() {
    let mut world = start_world();
    let key = b"delivery proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_delivery(key, vector[id1, id2], ALICE);
    world.approve_proposal(key);

    let (mut delivery, delivery_cap) = world.create_delivery();
    let mut executable = world.execute_proposal(key);
    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving1);
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving2);
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

#[test, expected_failure(abort_code = transfers::EWrongDelivery)]
fun complete_delivery_error_wrong_delivery() {
    let mut world = start_world();
    let key = b"delivery proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_delivery(key, vector[id1, id2], ALICE);
    world.approve_proposal(key);

    let (mut delivery, delivery_cap) = world.create_delivery();
    let (delivery2, delivery_cap2) = world.create_delivery();
    let mut executable = world.execute_proposal(key);
    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving1);
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap2, &mut executable, world.multisig(), receiving2);
    transfers::complete_deliver(delivery, delivery_cap, executable);
    
    destroy(delivery2);
    destroy(delivery_cap2);
    world.end(); 
}   

#[test, expected_failure(abort_code = transfers::EWrongDelivery)]
fun claim_error_wrong_delivery() {
    let mut world = start_world();
    let key = b"delivery proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_delivery(key, vector[id1, id2], ALICE);
    world.approve_proposal(key);

    let (mut delivery, delivery_cap) = world.create_delivery();
    let (delivery2, delivery_cap2) = world.create_delivery();
    let mut executable = world.execute_proposal(key);
    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving1);
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving2);
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

#[test, expected_failure(abort_code = transfers::EWrongMultisig)]
fun cancel_delivery_error_wrong_multisig() {
    let mut world = start_world();
    let key = b"delivery proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_delivery(key, vector[id1, id2], ALICE);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let (mut delivery, delivery_cap) = world.create_delivery();
    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving1);
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving2);
    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(OWNER);
    let delivery = world.scenario().take_shared<Delivery>();        
    let multisig2 = world.new_multisig();
    transfers::cancel_delivery(&multisig2, delivery, world.scenario().ctx());

    destroy(multisig2);
    world.end();          
}

#[test, expected_failure(abort_code = transfers::EDeliveryNotEmpty)]
fun cancel_delivery_error_delivery_not_empty() {
    let mut world = start_world();
    let key = b"delivery proposal".to_string();

    let receiving1 = create_transfer_and_return_receiving1(&mut world);
    let receiving2 = create_transfer_and_return_receiving2(&mut world);
    let id1 = receiving1.receiving_object_id();
    let id2 = receiving2.receiving_object_id();

    world.propose_delivery(key, vector[id1, id2], ALICE);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let (mut delivery, delivery_cap) = world.create_delivery();
    transfers::execute_deliver<Object>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving1);
    transfers::execute_deliver<Object2>(&mut delivery, &delivery_cap, &mut executable, world.multisig(), receiving2);
    transfers::complete_deliver(delivery, delivery_cap, executable);

    world.scenario().next_tx(OWNER);
    let delivery = world.scenario().take_shared<Delivery>();   
    world.cancel_delivery(delivery);

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