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

use std::type_name::TypeName;
use sui::transfer::Receiving;
use account_protocol::{
    account::Account,
    intents::{Intent, Expired},
    executable::Executable,
};
use account_actions::version;

// === Errors ===

#[error]
const EWrongObject: vector<u8> = b"Wrong object provided";

// === Structs ===

public struct LockWitness() has drop;

/// [ACTION] guards access to account owned objects which can only be received via this action
public struct WithdrawAction has store {
    // the owned objects we want to access
    object_id: ID,
}

// === Public functions ===

public fun new_withdraw<Config, Outcome, W: copy + drop>(
    intent: &mut Intent<Outcome>, 
    account: &mut Account<Config, Outcome>,
    object_id: ID, 
    witness: W,
) {
    let action = WithdrawAction { object_id };
    account.lock_object(intent, &action, object_id, version::current(), LockWitness());
    intent.add_action(action, witness);
}

public fun do_withdraw<Config, Outcome, T: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
    version: TypeName,
    witness: W,
): T {
    let action: &WithdrawAction = account.process_action(executable, version, witness);
    assert!(receiving.receiving_object_id() == action.object_id, EWrongObject);
    
    account.receive(receiving, version)
}

public fun delete_withdraw<Config, Outcome>(
    expired: &mut Expired, 
    account: &mut Account<Config, Outcome>,
) {
    let action: WithdrawAction = expired.remove_action();
    let object_id = action.object_id;

    account.unlock_object(expired, &action, object_id, version::current(), LockWitness());
    let WithdrawAction { .. } = action;
}
