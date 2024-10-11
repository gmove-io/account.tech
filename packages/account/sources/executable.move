/// The Executable struct is hot potato constructed from a Proposal that has been approved.
/// It ensures that the actions are executed as it can't be stored.
/// A delegated witness pattern is used to ensure only the proposal interface that created it 
/// can access the underlying actions and destroy it.

module account_protocol::executable;

// === Imports ===

use sui::bag::Bag;
use account_protocol::source::Source;

// === Errors ===

const EActionNotFound: u64 = 0;

// === Structs ===

/// Hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // module that issued the proposal and must destroy it
    source: Source,
    // actions to be executed in order, heterogenous array
    actions: Bag,
}

// === Account-only functions ===

/// Is only called from the action modules, as well as the following functions
public fun action_mut<A: store, W: drop>(
    executable: &mut Executable, 
    account_addr: address,
    witness: W,
): &mut A {
    executable.source.assert_is_constructor(witness);
    executable.source.assert_is_account(account_addr);

    let idx = executable.action_index<A>();
    executable.actions.borrow_mut(idx)
}

/// Needs to destroy all actions before destroying the executable
/// Action must resolved before, so we don't need to check the Account address
public fun remove_action<A: store, W: drop>(
    executable: &mut Executable, 
    witness: W,
): A {
    executable.source.assert_is_constructor(witness);

    let idx = executable.action_index<A>();
    executable.actions.remove(idx)
}

/// Completes the execution
public fun destroy<W: drop>(
    executable: Executable, 
    witness: W
) {
    let Executable { 
        source, 
        actions,
        ..
    } = executable;
    
    source.assert_is_constructor(witness);
    actions.destroy_empty();
}

// === View functions ===

public fun source(executable: &Executable): &Source {
    &executable.source
}

public fun actions_length(executable: &Executable): u64 {
    executable.actions.length()
}

public fun action_index<A: store>(executable: &Executable): u64 {
    let mut idx = 0;
    executable.actions.length().do!(|i| {
        if (executable.actions.contains_with_type<u64, A>(i)) idx = i;
        // returns length if not found
    });
    assert!(idx != executable.actions.length(), EActionNotFound);

    idx
}

public fun action<A: store>(executable: &Executable): &A {
    let idx = executable.action_index<A>();
    executable.actions.borrow(idx)
}

// === Package functions ===

/// Is only called from the account module
public(package) fun new(source: Source, actions: Bag): Executable {
    Executable { 
        source,
        actions
    }
}