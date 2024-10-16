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

use std::{
    string::String,
    type_name::TypeName
};
use sui::{
    transfer::Receiving,
    coin::Coin
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};
use account_actions::{
    transfers,
    payments,
    version,
};

// === Errors ===

#[error]
const EWrongObject: vector<u8> = b"Wrong object provided";
#[error]
const EObjectsRecipientsNotSameLength: vector<u8> = b"Recipients and objects vectors must have the same length";

// === Structs ===

/// [PROPOSAL] transfers multiple objects
public struct TransferProposal() has copy, drop;
/// [PROPOSAL] streams an amount of coin to be paid at specific intervals
public struct PayProposal() has copy, drop;

/// [ACTION] guards access to account owned objects which can only be received via this action
public struct WithdrawAction has store {
    // the owned objects we want to access
    objects: vector<ID>,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to send owned objects
public fun propose_transfer<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    objects: vector<vector<ID>>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(recipients.length() == objects.length(), EObjectsRecipientsNotSameLength);
    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        TransferProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    objects.zip_do!(recipients, |objs, recipient| {
        new_withdraw(&mut proposal, objs, TransferProposal());
        transfers::new_transfer(&mut proposal, recipient, TransferProposal());
    });

    account.add_proposal(proposal, version::current(), TransferProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<Config, Outcome, T: key + store>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
) {
    let object = withdraw(executable, account, receiving, version::current(), TransferProposal());
    let mut is_executed = false;
    
    if (executable.action_is_completed<WithdrawAction>()) {
        destroy_withdraw(executable, version::current(), TransferProposal());
        is_executed = true;
    };

    transfers::transfer(executable, account, object, version::current(), TransferProposal(), is_executed);

    if (is_executed) transfers::destroy_transfer(executable, version::current(), TransferProposal());
}

// step 5: complete transfers and destroy the executable
public fun complete_transfers(executable: Executable) {
    executable.terminate(version::current(), TransferProposal());
}

// step 1: propose to create a Stream with a specific amount to be paid at each interval
public fun propose_pay<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
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
        auth,
        outcome,
        version::current(),
        PayProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    
    new_withdraw(&mut proposal, vector[coin], PayProposal());
    payments::new_pay(&mut proposal, amount, interval, recipient, PayProposal());

    account.add_proposal(proposal, version::current(), PayProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<Config, Outcome, C: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    let coin: Coin<C> = withdraw(&mut executable, account, receiving, version::current(), PayProposal());
    payments::pay(&mut executable, account, coin, version::current(), PayProposal(), ctx);

    destroy_withdraw(&mut executable, version::current(), PayProposal());
    payments::destroy_pay(&mut executable, version::current(), PayProposal());
    executable.terminate(version::current(), PayProposal());
}

// === [ACTION] Public functions ===

public fun new_withdraw<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    objects: vector<ID>, 
    witness: W,
) {
    proposal.add_action(WithdrawAction { objects }, witness);
}

public fun withdraw<Config, Outcome, T: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
    version: TypeName,
    witness: W,
): T {
    let withdraw_action = executable.load<WithdrawAction, W>(account.addr(), version, witness);
    let (_, idx) = withdraw_action.objects.index_of(&transfer::receiving_object_id(&receiving));
    let id = withdraw_action.objects.remove(idx);

    let received = account.receive(receiving, version);
    let received_id = object::id(&received);
    assert!(received_id == id, EWrongObject);

    if (withdraw_action.objects.is_empty()) executable.process<WithdrawAction, W>(version, witness);

    received
}

public fun destroy_withdraw<W: drop>(executable: &mut Executable, version: TypeName, witness: W) {
    let WithdrawAction { .. } = executable.cleanup(version, witness);
}

public fun delete_withdraw_action<Outcome>(expired: &mut Expired<Outcome>) {
    let WithdrawAction { .. } = expired.remove_expired_action();
}