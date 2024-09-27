/// This module allows proposals to access objects owned by the multisig in a secure way with Transfer to Object (TTO).
/// The objects can be taken only via an WithdrawAction action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed by adding both a WithdrawAction and a ReturnAction action to the proposal.
/// This is automatically handled by the borrow functions.
/// Caution: borrowed Coins and similar assets can be emptied, only withdraw the amount you need (merge and split coins before if necessary)
/// 
/// Objects owned by the multisig can also be transferred to any address.
/// Objects can be used to stream payments at specific intervals.

module kraken_actions::owned;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    coin::Coin
};
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
};
use kraken_actions::{
    transfers,
    payments,
};

// === Errors ===

const EWrongObject: u64 = 0;
const EReturnAllObjectsBefore: u64 = 1;
const ERetrieveAllObjectsBefore: u64 = 2;
const EDifferentLength: u64 = 3;

// === Structs ===

/// [PROPOSAL] transfers multiple objects
public struct TransferProposal has copy, drop {}
/// [PROPOSAL] streams an amount of coin to be paid at specific intervals
public struct PayProposal has copy, drop {}

/// [ACTION] guards access to multisig owned objects which can only be received via this action
public struct WithdrawAction has store {
    // the owned objects we want to access
    objects: vector<ID>,
}

/// [ACTION] enforces accessed objects to be sent back to the multisig, depends on WithdrawAction
public struct ReturnAction has store {
    // list of objects to put back into the multisig
    to_return: vector<ID>,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to send owned objects
public fun propose_transfer(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    objects: vector<vector<ID>>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(recipients.length() == objects.length(), EDifferentLength);
    let proposal_mut = multisig.create_proposal(
        TransferProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    objects.zip_do!(recipients, |objs, recipient| {
        new_withdraw(proposal_mut, objs);
        transfers::new_transfer(proposal_mut, recipient);
    });
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<T: key + store>(
    executable: &mut Executable, 
    multisig: &mut Multisig, 
    receiving: Receiving<T>,
) {
    let object = withdraw(executable, multisig, receiving, TransferProposal {});
    
    let mut is_executed = false;
    let withdraw: &WithdrawAction = executable.action();
    
    if (withdraw.objects.is_empty()) {
        let WithdrawAction { objects } = executable.remove_action(TransferProposal {});
        objects.destroy_empty();
        is_executed = true;
    };

    transfers::transfer(executable, multisig, object, TransferProposal {}, is_executed);

    if (is_executed) {
        transfers::destroy_transfer(executable, TransferProposal {});
    }
}

// step 5: complete transfers and destroy the executable
public fun complete_transfers(executable: Executable) {
    executable.destroy(TransferProposal {});
}

// step 1: propose to create a Stream with a specific amount to be paid at each interval
public fun propose_pay(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin: ID, // coin owned by the multisig, must have the total amount to be paid
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        PayProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    
    new_withdraw(proposal_mut, vector[coin]);
    payments::new_pay(proposal_mut, amount, interval, recipient);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<C: drop>(
    mut executable: Executable, 
    multisig: &mut Multisig, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    let coin: Coin<C> = withdraw(&mut executable, multisig, receiving, PayProposal {});
    payments::pay(&mut executable, multisig, coin, PayProposal {}, ctx);

    destroy_withdraw(&mut executable, PayProposal {});
    payments::destroy_pay(&mut executable, PayProposal {});
    executable.destroy(PayProposal {});
}

// === [ACTION] Public functions ===

public fun new_withdraw(proposal: &mut Proposal, objects: vector<ID>) {
    proposal.add_action(WithdrawAction { objects });
}

public fun withdraw<T: key + store, W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    receiving: Receiving<T>,
    witness: W,
): T {
    let withdraw_mut: &mut WithdrawAction = executable.action_mut(witness, multisig.addr());
    let (_, idx) = withdraw_mut.objects.index_of(&transfer::receiving_object_id(&receiving));
    let id = withdraw_mut.objects.remove(idx);

    let received = multisig.receive(witness, receiving);
    let received_id = object::id(&received);
    assert!(received_id == id, EWrongObject);

    received
}

public fun destroy_withdraw<W: drop>(executable: &mut Executable, witness: W) {
    let WithdrawAction { objects } = executable.remove_action(witness);
    assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
}

public fun new_borrow(proposal: &mut Proposal, objects: vector<ID>) {
    new_withdraw(proposal, objects);
    proposal.add_action(ReturnAction { to_return: objects });
}

public fun borrow<T: key + store, W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    receiving: Receiving<T>,
    witness: W,
): T {
    withdraw(executable, multisig, receiving, witness)
}

public fun put_back<T: key + store, W: copy + drop>(
    executable: &mut Executable,
    multisig: &Multisig, 
    returned: T, 
    witness: W,
) {
    let borrow_mut: &mut ReturnAction = executable.action_mut(witness, multisig.addr());
    let (exists_, idx) = borrow_mut.to_return.index_of(&object::id(&returned));
    assert!(exists_, EWrongObject);

    borrow_mut.to_return.remove(idx);
    transfer::public_transfer(returned, multisig.addr());
}

public fun destroy_borrow<W: copy + drop>(executable: &mut Executable, witness: W) {
    destroy_withdraw(executable, witness);
    let ReturnAction { to_return } = executable.remove_action(witness);
    assert!(to_return.is_empty(), EReturnAllObjectsBefore);
}

// === [CORE DEPS] Public functions ===

public fun delete_withdraw_action<W: copy + drop>(
    action: WithdrawAction, 
    multisig: &Multisig, 
    witness: W
) {
    multisig.deps().assert_core_dep(witness);
    let WithdrawAction { .. } = action;
}

public fun delete_return_action<W: copy + drop>(
    action: ReturnAction, 
    multisig: &Multisig, 
    witness: W
) {
    multisig.deps().assert_core_dep(witness);
    let ReturnAction { .. } = action;
}
