/// This module allows proposals to access objects owned by the account in a secure way with Transfer to Object (TTO).
/// The objects can be taken only via an WithdrawAction action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed by adding both a WithdrawAction and a ReturnAction action to the proposal.
/// This is automatically handled by the borrow functions.
/// Caution: borrowed Coins and similar assets can be emptied, only withdraw the amount you need (merge and split coins before if necessary)
/// 
/// Objects owned by the account can also be transferred to any address.
/// Objects can be used to stream payments at specific intervals.

module account_actions::owned;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    coin::Coin
};
use account_protocol::{
    account::Account,
    proposals::Proposal,
    executable::Executable
};
use account_actions::{
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

/// [ACTION] guards access to account owned objects which can only be received via this action
public struct WithdrawAction has store {
    // the owned objects we want to access
    objects: vector<ID>,
}

/// [ACTION] enforces accessed objects to be sent back to the account, depends on WithdrawAction
public struct ReturnAction has store {
    // list of objects to put back into the account
    to_return: vector<ID>,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to send owned objects
public fun propose_transfer(
    account: &mut Account, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    objects: vector<vector<ID>>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(recipients.length() == objects.length(), EDifferentLength);
    let mut proposal = account.create_proposal(
        TransferProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    objects.zip_do!(recipients, |objs, recipient| {
        new_withdraw(&mut proposal, objs, TransferProposal {});
        transfers::new_transfer(&mut proposal, recipient, TransferProposal {});
    });

    account.add_proposal(proposal, TransferProposal {});
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<T: key + store>(
    executable: &mut Executable, 
    account: &mut Account, 
    receiving: Receiving<T>,
) {
    let object = withdraw(executable, account, receiving, TransferProposal {});
    
    let mut is_executed = false;
    let withdraw: &WithdrawAction = executable.action();
    
    if (withdraw.objects.is_empty()) {
        let WithdrawAction { objects } = executable.remove_action(TransferProposal {});
        objects.destroy_empty();
        is_executed = true;
    };

    transfers::transfer(executable, account, object, TransferProposal {}, is_executed);

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
    account: &mut Account, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin: ID, // coin owned by the account, must have the total amount to be paid
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
    let mut proposal = account.create_proposal(
        PayProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    
    new_withdraw(&mut proposal, vector[coin], PayProposal {});
    payments::new_pay(&mut proposal, amount, interval, recipient, PayProposal {});

    account.add_proposal(proposal, PayProposal {});
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<C: drop>(
    mut executable: Executable, 
    account: &mut Account, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    let coin: Coin<C> = withdraw(&mut executable, account, receiving, PayProposal {});
    payments::pay(&mut executable, account, coin, PayProposal {}, ctx);

    destroy_withdraw(&mut executable, PayProposal {});
    payments::destroy_pay(&mut executable, PayProposal {});
    executable.destroy(PayProposal {});
}

// === [ACTION] Public functions ===

public fun new_withdraw<W: copy + drop>(
    proposal: &mut Proposal, 
    objects: vector<ID>, 
    witness: W,
) {
    proposal.add_action(WithdrawAction { objects }, witness);
}

public fun withdraw<T: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account, 
    receiving: Receiving<T>,
    witness: W,
): T {
    let withdraw_mut: &mut WithdrawAction = executable.action_mut(account.addr(), witness);
    let (_, idx) = withdraw_mut.objects.index_of(&transfer::receiving_object_id(&receiving));
    let id = withdraw_mut.objects.remove(idx);

    let received = account.receive(witness, receiving);
    let received_id = object::id(&received);
    assert!(received_id == id, EWrongObject);

    received
}

public fun destroy_withdraw<W: copy + drop>(executable: &mut Executable, witness: W) {
    let WithdrawAction { objects } = executable.remove_action(witness);
    assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
}

public fun new_borrow<W: copy + drop>(
    proposal: &mut Proposal, 
    objects: vector<ID>, 
    witness: W,
) {
    new_withdraw(proposal, objects, witness);
    proposal.add_action(ReturnAction { to_return: objects }, witness);
}

public fun borrow<T: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account, 
    receiving: Receiving<T>,
    witness: W,
): T {
    withdraw(executable, account, receiving, witness)
}

public fun put_back<T: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &Account, 
    returned: T, 
    witness: W,
) {
    let borrow_mut: &mut ReturnAction = executable.action_mut(account.addr(), witness);
    let (exists_, idx) = borrow_mut.to_return.index_of(&object::id(&returned));
    assert!(exists_, EWrongObject);

    borrow_mut.to_return.remove(idx);
    transfer::public_transfer(returned, account.addr());
}

public fun destroy_borrow<W: copy + drop>(executable: &mut Executable, witness: W) {
    destroy_withdraw(executable, witness);
    let ReturnAction { to_return } = executable.remove_action(witness);
    assert!(to_return.is_empty(), EReturnAllObjectsBefore);
}

// === [CORE DEPS] Public functions ===

public fun delete_withdraw_action<W: copy + drop>(
    action: WithdrawAction, 
    account: &Account, 
    witness: W
) {
    account.deps().assert_core_dep(witness);
    let WithdrawAction { .. } = action;
}

public fun delete_return_action<W: copy + drop>(
    action: ReturnAction, 
    account: &Account, 
    witness: W
) {
    account.deps().assert_core_dep(witness);
    let ReturnAction { .. } = action;
}
