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

#[error]
const ENoLock: vector<u8> = b"No Lock for this Cap type";

// === Structs ===    

/// [PROPOSAL] witness defining the access cap proposal, and associated role
public struct BorrowCapIntent() has copy, drop;

// step 1: propose to mint an amount of a coin that will be transferred to the Account
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

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountMultisig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_borrow_cap<Config, Outcome, Cap: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): (Borrowed<Cap>, Cap) {
    access_control::do_borrow(executable, account, version::current(), BorrowCapIntent())
}

// step 5: return the cap to destroy Borrow, the action and executable
public fun complete_borrow_cap<Config, Outcome, Cap: key + store>(
    executable: Executable, 
    account: &mut Account<Config, Outcome>,
    borrow: Borrowed<Cap>, 
    cap: Cap
) {
    access_control::return_borrowed(account, borrow, cap, version::current());
    account.confirm_execution(executable, version::current(), BorrowCapIntent());
}