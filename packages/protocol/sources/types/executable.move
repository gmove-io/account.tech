/// The Executable struct is hot potato constructed from a Proposal that has been approved.
/// It ensures that the actions are executed as it can't be stored.
/// Action delegated witness pattern is used to ensure only the proposal interface that created it 
/// can access the underlying actions and destroy it.
/// 
/// Proposal Actions are first placed into the pending Bag and moved to completed when processed.
/// This is to ensure each action is executed exactly once. 

module account_protocol::executable;

// === Imports ===

use std::string::String;
use account_protocol::issuer::Issuer;

// === Structs ===

/// Hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // key of the intent that created the executable
    key: String,
    // current action index, to reduce gas costs for large bags
    action_idx: u64,
}

// === View functions ===

public fun issuer(executable: &Executable): &Issuer {
    &executable.issuer
}

public fun key(executable: &Executable): String {
    executable.key
}

public fun action_idx(executable: &Executable): u64 {
    executable.action_idx
}

// === Package functions ===

/// Is only called from the account module
public(package) fun new(issuer: Issuer, key: String): Executable {
    Executable { issuer, key, action_idx: 0 }
}

public(package) fun next_action(executable: &mut Executable): (String, u64) {
    let (key, action_idx) = (executable.key, executable.action_idx);
    executable.action_idx = executable.action_idx + 1;

    (key, action_idx)
}

/// The executable is destroyed
public(package) fun destroy(executable: Executable) {
    let Executable { .. } = executable;
}