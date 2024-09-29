/// The Executable struct is hot potato constructed from a Proposal that has been approved.
/// It ensures that the actions are executed as it can't be stored.
/// A delegated witness pattern is used to ensure only the proposal interface that created it 
/// can access the underlying actions and destroy it.

module account_protocol::executable;

// === Imports ===

use sui::bag::Bag;
use account_protocol::auth::Auth;

// === Structs ===

/// Hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // module that issued the proposal and must destroy it
    auth: Auth,
    // index of the next action to destroy, starts at 0
    next_to_destroy: u64,
    // actions to be executed in order, heterogenous array
    actions: Bag,
}

// === Account-only functions ===

/// Is only called from the proposal module
public(package) fun new(auth: Auth, actions: Bag): Executable {
    Executable { 
        auth,
        next_to_destroy: 0,
        actions
    }
}

/// Is only called from the proposal module, as well as the following functions
public fun action_mut<W: drop, A: store>(
    executable: &mut Executable, 
    witness: W,
    account_addr: address,
): &mut A {
    executable.auth.assert_is_witness(witness);
    executable.auth.assert_is_account(account_addr);

    let idx = executable.action_index<A>();
    executable.actions.borrow_mut(idx)
}

/// Needs to destroy all actions before destroying the executable
public fun remove_action<W: drop, A: store>(
    executable: &mut Executable, 
    witness: W,
): A {
    executable.auth.assert_is_witness(witness);

    let next = executable.next_to_destroy;
    executable.next_to_destroy = next + 1;

    executable.actions.remove(next)
}

/// Completes the execution
public fun destroy<W: drop>(
    executable: Executable, 
    witness: W
) {
    let Executable { 
        auth, 
        actions,
        ..
    } = executable;
    
    auth.assert_is_witness(witness);
    actions.destroy_empty();
}

// === View functions ===

public fun auth(executable: &Executable): &Auth {
    &executable.auth
}

public fun next_to_destroy(executable: &Executable): u64 {
    executable.next_to_destroy
}

public fun actions_length(executable: &Executable): u64 {
    executable.actions.length()
}

public fun action<A: store>(executable: &Executable): &A {
    let idx = executable.action_index<A>();
    executable.actions.borrow(idx)
}

public fun action_index<A: store>(executable: &Executable): u64 {
    let mut idx = executable.next_to_destroy;
    let last_idx = idx + executable.actions.length();

    loop {
        if (
            idx == last_idx || // returns length if action not found
            executable.actions.contains_with_type<u64, A>(idx)
        ) break idx;
        idx = idx + 1;
    };

    idx
}
