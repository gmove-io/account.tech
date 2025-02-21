/// The Executable struct is hot potato constructed from a Proposal that has been approved.
/// It ensures that the actions are executed as it can't be stored.
/// Action delegated witness pattern is used to ensure only the proposal interface that created it 
/// can access the underlying actions and destroy it.
/// 
/// Proposal Actions are first placed into the pending Bag and moved to completed when processed.
/// This is to ensure each action is executed exactly once. 

module account_protocol::executable;

// === Imports ===

use account_protocol::issuer::Issuer;

// === Structs ===

/// Hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // current action index, to reduce gas costs for large bags
    action_idx: u64,
}

// === View functions ===

public fun issuer(executable: &Executable): &Issuer {
    &executable.issuer
}

public fun action_idx(executable: &Executable): u64 {
    executable.action_idx
}

// === Package functions ===

/// Is only called from the account module
public(package) fun new(issuer: Issuer): Executable {
    Executable { issuer, action_idx: 0 }
}

public(package) fun next_action(executable: &mut Executable): u64 {
    let action_idx = executable.action_idx;
    executable.action_idx = executable.action_idx + 1;
    action_idx
}

/// The executable is destroyed
public(package) fun destroy(executable: Executable) {
    let Executable { .. } = executable;
}