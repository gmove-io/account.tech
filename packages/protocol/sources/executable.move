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

// === Errors ===

#[error]
const EActionNotFound: vector<u8> = b"Action not found for type";
#[error]
const EActionsRemaining: vector<u8> = b"Actions have not been processed";

// === Structs ===

/// Hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // key of the intent that created the executable
    key: String,
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // current action index, to reduce gas costs for large bags
    action_idx: u64,
}

// === View functions ===

public fun key(executable: &Executable): String {
    executable.key
}

public fun issuer(executable: &Executable): &Issuer {
    &executable.issuer
}

public fun action_idx(executable: &Executable): u64 {
    executable.action_idx
}

// === Package functions ===

/// Is only called from the account module
public(package) fun new(
    key: String,
    issuer: Issuer, 
): Executable {
    Executable { 
        key,
        issuer,
        action_idx: 0,
    }
}
public(package) fun next_action<W: drop>(
    executable: &mut Executable, 
    account_addr: address, // pass account address to ensure that the correct account will be modified
    witness: W,
): (String, u64) {
    executable.issuer.assert_is_constructor(witness);
    executable.issuer.assert_is_account(account_addr);

    let (key, action_idx) = (executable.key, executable.action_idx);
    executable.action_idx = executable.action_idx + 1;

    (key, action_idx)
}

/// The executable is destroyed
public(package) fun destroy<W: drop>(
    executable: Executable, 
    actions_length: u64,
    witness: W
) {
    let Executable { 
        issuer, 
        action_idx,
        ..
    } = executable;

    assert!(action_idx == actions_length, EActionsRemaining);
    
    issuer.assert_is_constructor(witness);
}