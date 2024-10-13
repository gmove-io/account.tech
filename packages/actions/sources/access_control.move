/// Developers can restrict access to functions in their own package with an Access.
/// Access structs are issued using a Cap type that can be locked at any time.
/// 
/// The Access has copy and drop abilities to be used multiple times within a single PTB
/// It has a generic type which acts as a proof of cap. 
/// It is similar to the Cap pattern but it is issued by an Account upon proposal execution.
/// 
/// e.g.
/// 
/// public struct AdminCap has key, store {}
/// 
/// public fun foo(_: Access<AdminCap>) { ... }

module account_actions::access_control;

// === Imports ===

use std::{
    type_name,
    string::String
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth
};

// === Errors ===

#[error]
const ENoLock: vector<u8> = b"No Lock for this Cap type";
#[error]
const EWrongAccount: vector<u8> = b"This Cap has not been borrowed from this acccount";

// === Structs ===    

/// Dynamic Field key for the AccessLock
public struct AccessKey<phantom Cap> has copy, drop, store {}
/// Dynamic Field wrapper storing a cap
public struct AccessLock<Cap: store> has store {
    cap: Cap,
}

/// [PROPOSAL] issues an Access<Cap>, Cap being the type of a Cap held by the Account
public struct AccessProposal() has drop;

/// [ACTION] mint new coins
public struct AccessAction<phantom Cap> has store {}

/// This struct is created upon approval to ensure the cap is returned
public struct Borrow<phantom Cap> {
    account_addr: address
}

// === [MEMBER] Public functions ===

/// Only a member can lock a Cap, the Cap must have at least store ability
public fun lock_cap<Config, Outcome, Cap: store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    cap: Cap,
) {
    auth.verify(account.addr());
    account.add_managed_asset(AccessKey<Cap> {}, AccessLock { cap });
}

public fun has_lock<Config, Outcome, Cap>(
    account: &Account<Config, Outcome>
): bool {
    account.has_managed_asset(AccessKey<Cap> {})
}

// === [PROPOSAL] Public functions ===

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun propose_access<Config, Outcome, Cap>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        AccessProposal(), 
        type_to_name<Cap>(), // the cap type is the witness role name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );

    new_access<Outcome, Cap, AccessProposal>(&mut proposal, AccessProposal());
    account.add_proposal(proposal, AccessProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_access<Config, Outcome, Cap: store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): (Borrow<Cap>, Cap) {
    access_cap<Config, Outcome, Cap, AccessProposal>(executable, account, AccessProposal())
}

// step 5: return the cap to destroy Borrow, the action and executable
public fun complete_access<Config, Outcome, Cap: store>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>,
    borrow: Borrow<Cap>, 
    cap: Cap
) {
    return_cap(account, borrow, cap);
    destroy_access<Cap, AccessProposal>(&mut executable, AccessProposal());
    executable.destroy(AccessProposal());
}

// === [ACTION] Public functions ===

public fun new_access<Outcome, Cap, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    witness: W,    
) {
    proposal.add_action(AccessAction<Cap> {}, witness);
}

public fun access_cap<Config, Outcome, Cap: store, W: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    witness: W, 
): (Borrow<Cap>, Cap) {
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);
    // check to be sure this cap type has been approved
    let _access_mut: &mut AccessAction<Cap> = executable.action_mut(account.addr(), witness);
    let AccessLock<Cap> { cap } = account.remove_managed_asset(AccessKey<Cap> {});

    (Borrow<Cap> { account_addr: account.addr() }, cap)
}

public fun return_cap<Config, Outcome, Cap: store>(
    account: &mut Account<Config, Outcome>,
    borrow: Borrow<Cap>,
    cap: Cap,
) {
    let Borrow<Cap> { account_addr } = borrow;
    assert!(account_addr == account.addr(), EWrongAccount);

    account.add_managed_asset(AccessKey<Cap> {}, AccessLock { cap });
}

public fun destroy_access<Cap, W: drop>(executable: &mut Executable, witness: W) {
    let AccessAction<Cap> {} = executable.remove_action(witness);
}

public fun delete_access_action<Outcome, Cap>(expired: &mut Expired<Outcome>) {
    let AccessAction<Cap> { .. } = expired.remove_expired_action();
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}
