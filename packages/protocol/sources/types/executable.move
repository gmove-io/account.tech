/// The Executable struct is hot potato constructed from an Intent that has been resolved.
/// It ensures that the actions are executed as intended as it can't be stored.
/// Action index is tracked to ensure each action is executed exactly once.

module account_protocol::executable;

// === Imports ===

use account_protocol::issuer::Issuer;

// === Structs ===

/// Hot potato ensuring the actions in the intent are executed as intended.
public struct Executable {
    // issuer of the corresponding intent
    issuer: Issuer,
    // current action index
    action_idx: u64,
}

// === View functions ===

/// Returns the issuer of the corresponding intent
public fun issuer(executable: &Executable): &Issuer {
    &executable.issuer
}

/// Returns the current action index
public fun action_idx(executable: &Executable): u64 {
    executable.action_idx
}

// === Package functions ===

/// Creates a new executable from an issuer
public(package) fun new(issuer: Issuer): Executable {
    Executable { issuer, action_idx: 0 }
}

/// Returns the next action index
public(package) fun next_action(executable: &mut Executable): u64 {
    let action_idx = executable.action_idx;
    executable.action_idx = executable.action_idx + 1;
    action_idx
}

/// Destroys the executable
public(package) fun destroy(executable: Executable) {
    let Executable { .. } = executable;
}