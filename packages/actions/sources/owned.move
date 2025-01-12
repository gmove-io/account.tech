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

use std::string::String;
use sui::{
    transfer::Receiving,
    coin::Coin
};
use account_protocol::{
    account::Account,
    executable::Executable,
    auth::Auth,
};
use account_actions::{
    vesting,
    version,
};

// === Errors ===

#[error]
const EWrongObject: vector<u8> = b"Wrong object provided";
#[error]
const EObjectsRecipientsNotSameLength: vector<u8> = b"Recipients and objects vectors must have the same length";

// === Structs ===

public struct Witness() has drop;

/// [ACTION] guards access to account owned objects which can only be received via this action
public struct WithdrawAndTransferAction has drop, store {
    // the owned objects we want to access
    object_ids: vector<ID>,
    // the recipients
    recipients: vector<address>,
}
/// [ACTION] transfer an object to a recipient
public struct WithdrawAndVestingAction has drop, store {
    // the object to transfer
    object_id: ID,
    // timestamp when coins can start to be claimed
    start_timestamp: u64,
    // timestamp when balance is totally unlocked
    end_timestamp: u64,
    // address to pay
    recipient: address,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to send owned objects
public fun request_withdraw_and_transfer<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    object_ids: vector<ID>,
    recipients: vector<address>,
    outcome: Outcome,
) {
    assert!(recipients.length() == object_ids.length(), EObjectsRecipientsNotSameLength);
    
    let action = WithdrawAndTransferAction { object_ids, recipients };
    object_ids.do!(|id| {
        account.intents_mut(version::current()).lock(id); // throws if already locked
    });

    account.create_intent(
        auth,
        key,
        description,
        execution_time,
        expiration_time,
        action,
        outcome,
        version::current(),
        Witness(),
        b"".to_string(),
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_withdraw_and_transfer<Config, Obj: key + store>(
    executable: &mut Executable<WithdrawAndTransferAction>, 
    account: &mut Account<Config>, 
    receiving: Receiving<Obj>,
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    let (object_id, recipient) = (action_mut.object_ids.remove(0), action_mut.recipients.remove(0));
    assert!(receiving.receiving_object_id() == object_id, EWrongObject);
    account.intents_mut(version::current()).unlock(object_id);
    
    let obj = account.receive(receiving, version::current());
    transfer::public_transfer(obj, recipient);
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_withdraw_and_transfer(executable: Executable<WithdrawAndTransferAction>) {
    executable.destroy(version::current(), Witness());
}

// step 1: propose to create a Stream with a specific amount to be paid at each interval
public fun request_withdraw_and_vesting<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    coin_id: ID, // coin owned by the account, must have the total amount to be paid
    start_timestamp: u64,
    end_timestamp: u64, 
    recipient: address,
    outcome: Outcome,
) {
    let action = WithdrawAndVestingAction { 
        object_id: coin_id, 
        start_timestamp, 
        end_timestamp, 
        recipient 
    };
    account.intents_mut(version::current()).lock(coin_id);
    account.create_intent(
        auth,
        key,
        description,
        execution_time,
        expiration_time,
        action,
        outcome,
        version::current(),
        Witness(),
        b"".to_string(),
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: withdraw and place the coin into Stream to be paid
public fun execute_withdraw_and_vesting<Config, CoinType: drop>(
    mut executable: Executable<WithdrawAndVestingAction>, 
    account: &mut Account<Config>, 
    receiving: Receiving<Coin<CoinType>>,
    ctx: &mut TxContext
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    assert!(receiving.receiving_object_id() == action_mut.object_id, EWrongObject);
    account.intents_mut(version::current()).unlock(action_mut.object_id);
    
    let obj = account.receive(receiving, version::current());
    vesting::create_stream(
        obj, 
        action_mut.start_timestamp, 
        action_mut.end_timestamp, 
        action_mut.recipient, 
        ctx
    );

    executable.destroy(version::current(), Witness());
}