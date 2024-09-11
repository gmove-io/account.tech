/// This is the core module managing Multisig and Proposals.
/// It provides the apis to create, approve and execute proposals with actions.
/// 
/// The flow is as follows:
///   1. A proposal is created by pushing actions into it. 
///      Actions are stacked from last to first, they must be executed then destroyed from last to first.
///   2. When the threshold is reached, a proposal can be executed. 
///      This returns an Executable hot potato constructed from certain fields of the approved Proposal. 
///      It is directly passed into action functions to enforce multisig approval for an action to be executed.
///   3. The module that created the proposal must destroy all of the actions and the Executable after execution 
///      by passing the same witness that was used for instanciation. 
///      This prevents the actions or the proposal to be stored instead of executed.

module kraken_multisig::executable;

// === Imports ===

use sui::bag::Bag;
use kraken_multisig::auth::Auth;

// === Structs ===

// hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // module that issued the proposal and must destroy it
    auth: Auth,
    // index of the next action to destroy, starts at 0
    next_to_destroy: u64,
    // actions to be executed in order
    actions: Bag,
}

// === Multisig-only functions ===

// return an executable if the number of signers is >= threshold
public(package) fun new(auth: Auth, actions: Bag): Executable {
    Executable { 
        auth,
        next_to_destroy: 0,
        actions
    }
}

public fun action_mut<I: drop, A: store>(
    executable: &mut Executable, 
    issuer: I,
    multisig_addr: address,
): &mut A {
    executable.auth.assert_is_issuer(issuer);
    executable.auth.assert_is_multisig(multisig_addr);

    let idx = executable.action_index<A>();
    executable.actions.borrow_mut(idx)
}

// need to destroy all actions before destroying the executable
public fun remove_action<I: drop, A: store>(
    executable: &mut Executable, 
    issuer: I,
): A {
    executable.auth.assert_is_issuer(issuer);

    let next = executable.next_to_destroy;
    executable.next_to_destroy = next + 1;

    executable.actions.remove(next)
}

// to complete the execution
public fun destroy<I: drop>(
    executable: Executable, 
    issuer: I
) {
    let Executable { 
        auth, 
        actions,
        ..
    } = executable;
    
    auth.assert_is_issuer(issuer);
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
