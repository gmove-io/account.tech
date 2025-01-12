/// The Executable struct is hot potato constructed from a Proposal that has been approved.
/// It ensures that the actions are executed as it can't be stored.
/// Action delegated witness pattern is used to ensure only the proposal interface that created it 
/// can access the underlying actions and destroy it.
/// 
/// Proposal Actions are first placed into the pending Bag and moved to completed when processed.
/// This is to ensure each action is executed exactly once. 

module account_protocol::executable;

// === Imports ===

use std::{
    type_name::TypeName,
    string::String,
};
use account_protocol::{
    issuer::Issuer,
    deps::Deps,
};

// === Errors ===

#[error]
const EActionNotFound: vector<u8> = b"Action not found for type";
#[error]
const EActionsNotEmpty: vector<u8> = b"Actions have not been processed";

// === Structs ===

/// Hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable<Action> {
    // key of the intent that created the executable
    key: String,
    // copied deps from the Account
    deps: Deps,
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // actions to be executed in order, heterogenous array
    action: Action,
}

// === Public functions ===

/// The following functions are called from action modules

/// Access the underlying action mutably
public fun action_mut<Action>(
    executable: &mut Executable<Action>, 
    account_addr: address, // pass account address to ensure that the correct account will be modified
    version: TypeName,
): &mut Action {
    executable.deps.assert_is_dep(version);
    executable.issuer.assert_is_account(account_addr);

    &mut executable.action
}

/// The executable is destroyed and the key is returned
public fun destroy<Action>(
    executable: Executable<Action>,
    version: TypeName, 
): Action {
    executable.deps.assert_is_dep(version);
    let Executable { action, .. } = executable;

    action
}

// === View functions ===

public fun key<Action>(executable: &Executable<Action>): String {
    executable.key
}

public fun deps<Action>(executable: &Executable<Action>): &Deps {
    &executable.deps
}

public fun issuer<Action>(executable: &Executable<Action>): &Issuer {
    &executable.issuer
}

public fun action<Action>(executable: &Executable<Action>): &Action {
    &executable.action
}

// === Package functions ===

/// Is only called from the account module
public(package) fun new<Action>(
    key: String,
    deps: Deps, 
    issuer: Issuer, 
    action: Action
): Executable<Action> {
    Executable { 
        key,
        deps,
        issuer,
        action,
    }
}