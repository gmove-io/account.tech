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
use sui::bag::{Self, Bag};
use account_protocol::{
    issuer::Issuer,
    deps::Deps,
};

// === Errors ===

#[error]
const EActionNotFound: vector<u8> = b"Action not found for type";

// === Structs ===

/// Hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // copied deps from the Account
    deps: Deps,
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // Bag start index, to reduce gas costs for large bags
    pending_start: u64,
    // actions to be executed in order, heterogenous array
    pending: Bag,
    // Bag start index, to reduce gas costs for large bags
    completed_start: u64,
    // actions that have been executed and must be destroyed
    completed: Bag,
}

// === Public functions ===

/// The following functions are called from action modules

/// 1. The action is read from the pending bag
public fun load<Action: store, W: drop>(
    executable: &mut Executable, 
    account_addr: address, // pass account address to ensure that the correct account will be modified
    version: TypeName,
    witness: W,
): &mut Action {
    executable.deps.assert_is_dep(version);
    executable.issuer.assert_is_constructor(witness);
    executable.issuer.assert_is_account(account_addr);

    let idx = pending_action_index<Action>(executable);
    executable.pending.borrow_mut(idx)
}

/// 2. The action is moved from pending to completed
public fun process<Action: store, W: drop>(
    executable: &mut Executable, 
    version: TypeName,
    witness: W,
) {
    executable.deps.assert_is_dep(version);
    executable.issuer.assert_is_constructor(witness);

    let action: Action = executable.completed.remove(executable.pending_start);
    let length = executable.completed.length();

    executable.completed.add(length, action);
    executable.pending_start = executable.pending_start + 1;
}

/// 3. The action is removed from the completed bag to be destroyed
public fun cleanup<Action: store, W: drop>(
    executable: &mut Executable, 
    version: TypeName,
    witness: W,
): Action {
    executable.deps.assert_is_dep(version);
    executable.issuer.assert_is_constructor(witness);

    executable.completed_start = executable.completed_start + 1;
    let action = executable.completed.remove(executable.completed_start);

    action
}

/// 4. The executable is destroyed
public fun terminate<W: drop>(
    executable: Executable, 
    version: TypeName,
    witness: W
) {
    let Executable { 
        deps,
        issuer, 
        pending,
        completed,
        ..
    } = executable;
    
    deps.assert_is_dep(version);
    issuer.assert_is_constructor(witness);
    pending.destroy_empty();
    completed.destroy_empty();
}

// === View functions ===

public fun deps(executable: &Executable): &Deps {
    &executable.deps
}

public fun issuer(executable: &Executable): &Issuer {
    &executable.issuer
}

public fun pending_action_index<Action: store>(executable: &Executable): u64 {
    let mut idx = executable.pending_start;
    executable.pending.length().do!(|i| {
        if (executable.pending.contains_with_type<u64, Action>(i)) idx = i;
        // returns length if not found
    });
    assert!(idx != executable.pending_start + executable.pending.length(), EActionNotFound);

    idx
}

public fun pending_action<Action: store>(executable: &Executable): &Action {
    let idx = pending_action_index<Action>(executable);
    executable.pending.borrow(idx)
}

public fun completed_action_index<Action: store>(executable: &Executable): u64 {
    let mut idx = executable.completed_start;
    executable.completed.length().do!(|i| {
        if (executable.completed.contains_with_type<u64, Action>(i)) idx = i;
        // returns length if not found
    });
    assert!(idx != executable.completed_start + executable.completed.length(), EActionNotFound);

    idx
}

public fun completed_action<Action: store>(executable: &Executable): &Action {
    let idx = completed_action_index<Action>(executable);
    executable.completed.borrow(idx)
}

public fun action_is_completed<Action: store>(executable: &Executable): bool {
    let mut idx = executable.completed_start;
    executable.completed.length().do!(|i| {
        if (executable.completed.contains_with_type<u64, Action>(i)) idx = i;
        // returns length if not found
    });
    idx != executable.completed_start + executable.completed.length()
}

// === Package functions ===

/// Is only called from the account module
public(package) fun new(deps: Deps, issuer: Issuer, pending: Bag, ctx: &mut TxContext): Executable {
    Executable { 
        deps,
        issuer,
        pending_start: 0,
        pending,
        completed_start: 0,
        completed: bag::new(ctx),
    }
}