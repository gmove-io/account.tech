/// This module allows proposals to access objects owned by the account in a secure way with Transfer to Object (TTO).
/// The objects can be taken only via an WithdrawAction action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed by adding both a WithdrawAction and a ReturnAction action to the proposal.
/// This is automatically handled by the borrow functions.
/// Caution: borrowed Coins and similar assets can be emptied, only withdraw the amount you need (merge and split coins before if necessary)
/// 
/// Objects owned by the account can also be transferred to any address.
/// Objects can be used to stream vesting at specific intervals.

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
    transfer as acc_transfer,
    vesting,
    version,
};

// === Errors ===

#[error]
const EWrongObject: vector<u8> = b"Wrong object provided";
#[error]
const EObjectsRecipientsNotSameLength: vector<u8> = b"Recipients and objects vectors must have the same length";

// === Structs ===

/// [PROPOSAL] acc_transfer multiple objects
public struct TransferProposal() has copy, drop;
/// [PROPOSAL] streams an amount of coin to be paid at specific intervals
public struct PayProposal() has copy, drop;

/// [ACTION] guards access to account owned objects which can only be received via this action
public struct WithdrawAction has store {
    // the owned objects we want to access
    object_id: ID,
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
    object_ids: vector<ID>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(recipients.length() == object_ids.length(), EObjectsRecipientsNotSameLength);
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

    object_ids.zip_do!(recipients, |object_id, recipient| {
        new_withdraw(&mut proposal, object_id, TransferProposal());
        acc_transfer::new_transfer(&mut proposal, recipient, TransferProposal());
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
    let object = do_withdraw(executable, account, receiving, version::current(), TransferProposal());
    acc_transfer::do_transfer(executable, account, object, version::current(), TransferProposal());
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_transfer(executable: Executable) {
    executable.destroy(version::current(), TransferProposal());
}

// step 1: propose to create a Stream with a specific amount to be paid at each interval
public fun propose_vesting<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_id: ID, // coin owned by the account, must have the total amount to be paid
    start_timestamp: u64,
    end_timestamp: u64, 
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
    
    new_withdraw(&mut proposal, coin_id, PayProposal());
    vesting::new_vesting(&mut proposal, start_timestamp, end_timestamp, recipient, PayProposal());

    account.add_proposal(proposal, version::current(), PayProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: withdraw and place the coin into Stream to be paid
public fun execute_vesting<Config, Outcome, C: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    let coin: Coin<C> = do_withdraw(&mut executable, account, receiving, version::current(), PayProposal());
    vesting::do_vesting(&mut executable, account, coin, version::current(), PayProposal(), ctx);
    executable.destroy(version::current(), PayProposal());
}

// === [ACTION] Public functions ===

public fun new_withdraw<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    object_id: ID, 
    witness: W,
) {
    proposal.add_action(WithdrawAction { object_id }, witness);
}

public fun do_withdraw<Config, Outcome, T: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
    version: TypeName,
    witness: W,
): T {
    let WithdrawAction { object_id } = executable.action(account.addr(), version, witness);
    assert!(receiving.receiving_object_id() == object_id, EWrongObject);
    account.receive(receiving, version)
}

public fun delete_withdraw_action<Outcome>(expired: &mut Expired<Outcome>) {
    let WithdrawAction { .. } = expired.remove_expired_action();
}