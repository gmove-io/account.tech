/// The Executable struct is hot potato constructed from a Proposal that has been approved.
/// It ensures that the actions are executed as it can't be stored.
/// Action delegated witness pattern is used to ensure only the proposal interface that created it 
/// can access the underlying actions and destroy it.
/// 
/// Proposal Actions are first placed into the pending Bag and moved to completed when processed.
/// This is to ensure each action is executed exactly once. 

module account_protocol::executable;

// === Imports ===

use std::type_name::TypeName;
use sui::bag::Bag;
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
public struct Executable {
    // copied deps from the Account
    deps: Deps,
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // Bag start index, to reduce gas costs for large bags
    start_idx: u64,
    // actions to be executed in order, heterogenous array
    actions: Bag,
}

// === Public functions ===

/// The following functions are called from action modules

/// The action is removed from the actions bag
public fun action<Action: store, W: drop>(
    executable: &mut Executable, 
    account_addr: address, // pass account address to ensure that the correct account will be modified
    version: TypeName,
    witness: W,
): Action {
    executable.deps.assert_is_dep(version);
    executable.issuer.assert_is_constructor(witness);
    executable.issuer.assert_is_account(account_addr);
    assert!(executable.actions.contains_with_type<u64, Action>(executable.start_idx), EActionNotFound);

    let action: Action = executable.actions.remove(executable.start_idx);
    executable.start_idx = executable.start_idx + 1;

    action
}

/// The executable is destroyed
public fun destroy<W: drop>(
    executable: Executable, 
    version: TypeName,
    witness: W
) {
    let Executable { 
        deps,
        issuer, 
        actions,
        ..
    } = executable;

    assert!(actions.is_empty(), EActionsNotEmpty);
    
    deps.assert_is_dep(version);
    issuer.assert_is_constructor(witness);
    actions.destroy_empty();
}

// === View functions ===

public fun deps(executable: &Executable): &Deps {
    &executable.deps
}

public fun issuer(executable: &Executable): &Issuer {
    &executable.issuer
}

// === Package functions ===

/// Is only called from the account module
public(package) fun new(deps: Deps, issuer: Issuer, actions: Bag): Executable {
    Executable { 
        deps,
        issuer,
        start_idx: 0,
        actions,
    }
}