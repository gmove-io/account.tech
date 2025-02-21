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
    access_control::{Self, Borrowed},
    version,
};

// === Errors ===

const ENoLock: u64 = 0;

// === Structs ===    

/// Intent Witness defining the intent to borrow an access cap.
public struct BorrowCapIntent() has copy, drop;

// === Public functions ===

/// Creates a BorrowCapIntent and adds it to an Account.
public fun request_borrow_cap<Config, Outcome, Cap>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(access_control::has_lock<_, _, Cap>(account), ENoLock);

    let mut intent = account.create_intent(
        key, 
        description, 
        execution_times, 
        expiration_time, 
        type_name::get<Cap>().into_string().to_string(),
        outcome,
        version::current(),
        BorrowCapIntent(), 
        ctx
    );

    access_control::new_borrow<_, _, Cap, _>(&mut intent, account, version::current(), BorrowCapIntent());
    account.add_intent(intent, version::current(), BorrowCapIntent());
}

/// Executes a BorrowCapIntent, returns a cap and a hot potato.
public fun execute_borrow_cap<Config, Outcome, Cap: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): (Borrowed<Cap>, Cap) {
    access_control::do_borrow(executable, account, version::current(), BorrowCapIntent())
}

/// Completes a BorrowCapIntent, destroys the executable and returns the cap to the account if the matching hot potato is returned.
public fun complete_borrow_cap<Config, Outcome, Cap: key + store>(
    executable: Executable, 
    account: &mut Account<Config, Outcome>,
    borrow: Borrowed<Cap>, 
    cap: Cap
) {
    access_control::return_borrowed(account, borrow, cap, version::current());
    account.confirm_execution(executable, version::current(), BorrowCapIntent());
}