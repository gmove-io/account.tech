/// This module uses the owned apis to transfer assets owned by the multisig.
/// Objects can also be delivered to a single address,
/// meaning that the recipient must claim the objects or the Multisig can retrieve them.

module kraken::transfers {
    use std::string::String;
    use sui::bag::Bag;
    use sui::transfer::Receiving;
    use sui::vec_map::{Self, VecMap};

    use kraken::owned::{Self, Withdraw};
    use kraken::multisig::{Multisig, Executable};

    // === Errors ===

    const EDifferentLength: u64 = 1;
    const ESendAllAssetsBefore: u64 = 2;
    const EDeliveryNotEmpty: u64 = 3;
    const EWrongDelivery: u64 = 4;

    // === Structs ===

    // witness verifying a proposal is destroyed in the module where it was created
    public struct Witness has drop {}

    // [ACTION] 
    public struct Send has store {
        // object id -> recipient address
        transfers: VecMap<ID, address>,
    }

    // [ACTION] a safe send where recipient has to confirm reception
    public struct Deliver has store {
        // address to transfer to
        recipient: address,
    }

    // shared object holding the objects to be received
    public struct Delivery has key {
        id: UID,
        objects: Bag,
    }

    // cap giving right to withdraw objects from the associated Delivery
    public struct DeliveryCap has key { 
        id: UID,
        delivery_id: ID,
    }

    // === [PROPOSALS] Public functions ===

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

        proposal_mut.push_action(new_send(objects, recipients)); // 2nd action to execute
        proposal_mut.push_action(owned::new_withdraw(objects)); // 1st action to execute
    }

    public fun complete_send(executable: Executable) {
        let withdraw: Withdraw = executable.pop_action(Witness {}); // 1st action to complete
        withdraw.destroy_withdraw();
        let send: Send = executable.pop_action(Witness {}); // 2nd action to complete
        send.destroy_send();
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)
    // step 4: loop over send 
    // step 5: destroy send

    // // step 1: propose to deliver object to a recipient that must claim it
    // public fun propose_delivery(
    //     multisig: &mut Multisig, 
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     objects: vector<ID>,
    //     recipient: address,
    //     ctx: &mut TxContext
    // ) {
    //     let withdraw = access::new_withdraw(objects);
    //     let action = Deliver { withdraw, recipient };
    //     multisig.create_proposal(
    //         action,
    //         key,
    //         execution_time,
    //         expiration_epoch,
    //         description,
    //         ctx
    //     );
    // }

    // // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // // step 4: creates a new delivery object that can only be shared (no store)
    // public fun create_delivery(ctx: &mut TxContext): Delivery {
    //     Delivery { id: object::new(ctx), objects: bag::new(ctx) }
    // }

    // // step 5: loop over it in PTB, adds last object from the Deliver action
    // public fun add_to_delivery<T: key + store>(
    //     delivery: &mut Delivery, 
    //     action: &mut Action<Deliver>, 
    //     multisig: &mut Multisig,
    //     received: Receiving<T>
    // ) {
    //     let object = action.action_mut().withdraw.withdraw(multisig, received);
    //     let index = delivery.objects.length();
    //     delivery.objects.add(index, object);
    // }

    // // step 6: share the Delivery and destroy the action
    // #[allow(lint(share_owned))] // cannot be access
    // public fun deliver(delivery: Delivery, action: Action<Deliver>, ctx: &mut TxContext) {
    //     let Deliver { withdraw, recipient } = action.unpack_action();
    //     withdraw.complete_withdraw();
        
    //     transfer::transfer(
    //         DeliveryCap { id: object::new(ctx), delivery_id: object::id(&delivery) }, 
    //         recipient
    //     );
    //     transfer::share_object(delivery);
    // }

    // // step 7: loop over it in PTB, receiver claim objects
    // public fun claim<T: key + store>(delivery: &mut Delivery, cap: &DeliveryCap): T {
    //     assert!(cap.delivery_id == object::id(delivery), EWrongDelivery);
    //     let index = delivery.objects.length() - 1;
    //     let object = delivery.objects.remove(index);
    //     object
    // }

    // // step 7 (bis): loop over it in PTB, multisig retrieve objects (member only)
    // public fun retrieve<T: key + store>(
    //     delivery: &mut Delivery, 
    //     multisig: &Multisig,
    //     ctx: &mut TxContext
    // ) {
    //     multisig.assert_is_member(ctx);
    //     let index = delivery.objects.length() - 1;
    //     let object: T = delivery.objects.remove(index);
    //     transfer::public_transfer(object, multisig.addr());
    // }

    // // step 8: destroy the delivery
    // public fun complete_delivery(delivery: Delivery, cap: DeliveryCap) {
    //     let DeliveryCap { id, delivery_id: _ } = cap;
    //     id.delete();
    //     let Delivery { id, objects } = delivery;
    //     id.delete();
    //     assert!(objects.is_empty(), EDeliveryNotEmpty);
    //     objects.destroy_empty();
    // }

    // // step 8 (bis): destroy the delivery (member only)
    // public fun cancel_delivery(
    //     multisig: &mut Multisig, 
    //     delivery: Delivery, 
    //     ctx: &mut TxContext
    // ) {
    //     multisig.assert_is_member(ctx);
    //     let Delivery { id, objects } = delivery;
    //     id.delete();
    //     assert!(objects.is_empty(), EDeliveryNotEmpty);
    //     objects.destroy_empty();
    // }

    // === [ACTIONS] Public functions ===

    public fun new_send(objects: vector<ID>, recipients: vector<address>): Send {
        Send { transfers: vec_map::from_keys_values(objects, recipients) }
    }

    public fun send<T: key + store>(
        executable: &mut Executable, 
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        idx: u64,
    ) {
        let object = owned::withdraw(executable, multisig, receiving, idx + 1);
        let action = executable.action_mut<Send>(idx);
        let (_, recipient) = action.transfers.remove(&transfer::receiving_object_id(&receiving));
        // abort if receiving object is not in the map
        transfer::public_transfer(object, recipient);
    }

    public fun destroy_send(action: Send) {
        let Send { transfers } = action;
        assert!(transfers.is_empty(), ESendAllAssetsBefore);
        transfers.destroy_empty();
    }
}

