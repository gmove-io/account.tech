module account_actions::access_control_intents;

// === Imports ===

use std::{
    type_name,
    string::String
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
};
use account_actions::{
    access_control::{Self, Borrow},
    version,
};

// === Errors ===

#[error]
const ENoLock: vector<u8> = b"No Lock for this Cap type";

// === Structs ===    

/// [PROPOSAL] witness defining the access cap proposal, and associated role
public struct AccessIntent() has copy, drop;

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun request_access<Config, Outcome, Cap>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    ctx: &mut TxContext
) {
    assert!(access_control::has_lock<Config, Outcome, Cap>(account), ENoLock);

    let mut intent = account.create_intent(
        auth,
        key, 
        description, 
        execution_times, 
        expiration_time, 
        outcome,
        version::current(),
        AccessIntent(), 
        type_name::get<Cap>().into_string().to_string(), // the cap type is the witness role name 
        ctx
    );

    access_control::new_access<Outcome, Cap, AccessIntent>(&mut intent, AccessIntent());
    account.add_intent(intent, version::current(), AccessIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_access<Config, Outcome, Cap: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): (Borrow<Cap>, Cap) {
    access_control::do_access(executable, account, version::current(), AccessIntent())
}

// step 5: return the cap to destroy Borrow, the action and executable
public fun complete_access<Config, Outcome, Cap: key + store>(
    executable: Executable, 
    account: &mut Account<Config, Outcome>,
    borrow: Borrow<Cap>, 
    cap: Cap
) {
    access_control::return_cap(account, borrow, cap, version::current());
    account.confirm_execution(executable, version::current(), AccessIntent());
}