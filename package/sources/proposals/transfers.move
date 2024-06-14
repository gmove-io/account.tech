/// This module uses the owned apis to transfer assets owned by the multisig.
/// Objects can also be delivered to a single address, meaning that the recipient must claim the objects.
/// If the delivery is not confirmed, the Multisig can retrieve the objects.

module kraken::transfers {
    use std::string::String;
    use sui::bag::{Self, Bag};
    use sui::transfer::Receiving;
    use sui::vec_map::{Self, VecMap};

    use kraken::owned;
    use kraken::multisig::{Multisig, Executable, Proposal};

    // === Errors ===

    const EDifferentLength: u64 = 1;
    const ESendAllAssetsBefore: u64 = 2;
    const EDeliveryNotEmpty: u64 = 3;
    const EWrongDelivery: u64 = 4;
    const EWrongMultisig: u64 = 5;
    const EDeliverAllObjectsBefore: u64 = 6;

    // === Structs ===

    // witness verifying a proposal is destroyed in the module where it was created
    public struct Witness has copy, drop {}

    // [ACTION] 
    public struct Send has store {
        // object id -> recipient address
        transfers: VecMap<ID, address>,
    }

    // [ACTION] a safe send where recipient has to confirm reception
    public struct Deliver has store {
        // objects to deposit
        to_deposit: vector<ID>,
        // address to transfer to
        recipient: address,
    }

    // shared object holding the objects to be received
    public struct Delivery has key {
        id: UID,
        multisig_id: ID,
        objects: Bag,
    }

    // cap giving right to withdraw objects from the associated Delivery
    public struct DeliveryCap has key { 
        id: UID,
        delivery_id: ID,
    }

    // === [PROPOSAL] Public functions ===

    // step 1: propose to send owned objects
    public fun propose_send(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
        recipients: vector<address>,
        ctx: &mut TxContext
    ) {
        assert!(recipients.length() == objects.length(), EDifferentLength);
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        new_send(proposal_mut, objects, recipients);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)
    
    // step 4: loop over send
    public fun execute_send<T: key + store>(
        executable: &mut Executable, 
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
    ) {
        send(executable, multisig, receiving, Witness {}, 0); // send action group starts from 0
    }

    // step 5: destroy send
    public fun complete_send(mut executable: Executable) {
        destroy_send(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // // step 1: propose to deliver object to a recipient that must claim it
    public fun propose_delivery(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        new_deliver(proposal_mut, objects, recipient);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: creates a new delivery object that can only be shared (no store)
    public fun create_delivery(multisig: &Multisig, ctx: &mut TxContext): (Delivery, DeliveryCap) {
        let delivery = Delivery { id: object::new(ctx), multisig_id: object::id(multisig), objects: bag::new(ctx) };
        let cap = DeliveryCap { id: object::new(ctx), delivery_id: object::id(&delivery) };
        (delivery, cap)
    }

    // step 5: loop over it in PTB, adds last object from the Deliver action
    public fun execute_deliver<T: key + store>(
        delivery: &mut Delivery, 
        cap: &DeliveryCap,
        executable: &mut Executable, 
        multisig: &mut Multisig,
        receiving: Receiving<T>,
    ) {
        deliver(delivery, cap, executable, multisig, receiving, Witness {}, 0);
    }

    // step 6: share the Delivery and destroy the action
    #[allow(lint(share_owned))]
    public fun complete_deliver(delivery: Delivery, cap: DeliveryCap, mut executable: Executable) {
        assert!(cap.delivery_id == object::id(&delivery), EWrongDelivery);
        
        owned::destroy_withdraw(&mut executable, Witness {});
        let recipient = destroy_deliver(&mut executable, Witness {});
        executable.destroy(Witness {});
        
        transfer::transfer(cap, recipient);
        transfer::share_object(delivery);
    }

    // step 7: loop over it in PTB, receiver claim objects
    public fun claim<T: key + store>(delivery: &mut Delivery, cap: &DeliveryCap): T {
        assert!(cap.delivery_id == object::id(delivery), EWrongDelivery);
        let index = delivery.objects.length() - 1;
        let object = delivery.objects.remove(index);
        object
    }

    // step 7 (bis): loop over it in PTB, multisig retrieve objects (member only)
    public fun retrieve<T: key + store>(
        delivery: &mut Delivery, 
        multisig: &Multisig,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let index = delivery.objects.length() - 1;
        let object: T = delivery.objects.remove(index);
        transfer::public_transfer(object, multisig.addr());
    }

    // step 8: destroy the delivery
    public fun confirm_delivery(delivery: Delivery, cap: DeliveryCap) {
        let DeliveryCap { id, delivery_id: _ } = cap;
        id.delete();
        let Delivery { id, multisig_id: _, objects } = delivery;
        id.delete();
        assert!(objects.is_empty(), EDeliveryNotEmpty);
        objects.destroy_empty();
    }

    // step 8 (bis): destroy the delivery (member only)
    public fun cancel_delivery(
        multisig: &Multisig, 
        delivery: Delivery, 
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let Delivery { id, multisig_id, objects } = delivery;
        
        assert!(multisig_id == object::id(multisig), EWrongMultisig);
        assert!(objects.is_empty(), EDeliveryNotEmpty);
        objects.destroy_empty();
        id.delete();
    }

    // === [ACTION] Public functions ===

    public fun new_send(proposal: &mut Proposal, objects: vector<ID>, recipients: vector<address>) {
        owned::new_withdraw(proposal, objects); // 1st action to be executed
        proposal.add_action(Send { transfers: vec_map::from_keys_values(objects, recipients) }); // 2nd action to be executed
    }

    public fun send<T: key + store, W: copy + drop>(
        executable: &mut Executable, 
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        witness: W,
        idx: u64, // index in actions bag 
    ) {
        multisig.assert_executed(executable);
        
        let object = owned::withdraw(executable, multisig, receiving, witness, idx);
        let send_mut: &mut Send = executable.action_mut(witness, idx + 1);
        let (_, recipient) = send_mut.transfers.remove(&object::id(&object));
        // abort if receiving object is not in the map
        transfer::public_transfer(object, recipient);
    }

    public fun destroy_send<W: copy + drop>(executable: &mut Executable, witness: W) {
        owned::destroy_withdraw(executable, witness);
        let send: Send = executable.remove_action(witness);
        let Send { transfers } = send;
        assert!(transfers.is_empty(), ESendAllAssetsBefore);
    }

    public fun new_deliver(proposal: &mut Proposal, objects: vector<ID>, recipient: address) {
        owned::new_withdraw(proposal, objects);
        proposal.add_action(Deliver { to_deposit: objects, recipient });
    }    
    
    public fun deliver<T: key + store, W: copy + drop>(
        delivery: &mut Delivery, 
        cap: &DeliveryCap,
        executable: &mut Executable, 
        multisig: &mut Multisig,
        receiving: Receiving<T>,
        witness: W,
        idx: u64 // index of first action in bag (withdraw)
    ) {
        multisig.assert_executed(executable);
        assert!(cap.delivery_id == object::id(delivery), EWrongDelivery);
        
        let object = owned::withdraw(executable, multisig, receiving, witness, idx);
        let deliver_mut: &mut Deliver = executable.action_mut(witness, idx + 1);
        let (_, index) = deliver_mut.to_deposit.index_of(&object::id(&object));
        deliver_mut.to_deposit.swap_remove(index); // we don't care about the order

        let index = delivery.objects.length();
        delivery.objects.add(index, object);
    }

    public fun destroy_deliver<W: copy + drop>(executable: &mut Executable, witness: W): address {
        owned::destroy_withdraw(executable, witness);
        let Deliver { to_deposit, recipient } = executable.remove_action(witness);
        assert!(to_deposit.is_empty(), EDeliverAllObjectsBefore);
        recipient
    }
}

