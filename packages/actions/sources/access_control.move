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

const ENoLock: u64 = 0;

// === Structs ===    

/// Dynamic Field key for the AccessLock
public struct AccessKey<phantom Cap> has copy, drop, store {}
/// Dynamic Field wrapper storing a cap
public struct AccessLock<Cap: store> has store {
    cap: Cap,
}

/// [MEMBER] can lock a custom Cap in the Account to restrict access to certain functions
public struct Do() has drop;
/// [PROPOSAL] issues an Access<Cap>, Cap being the type of a Cap held by the Account
public struct AccessProposal() has drop;

/// [ACTION] mint new coins
public struct AccessAction<phantom Cap> has store {}

/// This struct is created upon approval to grant access to certain functions gated by an Access<Cap> type
/// Similar to a cap but issued by an Account, with copy and drop to be used multiple times within a single PTB
public struct Access<phantom Cap> has copy, drop {}

// === [MEMBER] Public functions ===

/// Only a member can lock a Cap, the Cap must have at least store ability
public fun lock_cap<Config, Outcome, Cap: store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    cap: Cap,
) {
    auth.verify(account.addr());

    let lock = AccessLock { cap };
    account.add_managed_asset(Do(), AccessKey<Cap> {}, lock);
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
        type_to_name<Cap>(), // the coin type is the auth name 
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
public fun execute_access<Config, Outcome, Cap>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
): Access<Cap> {
    let access = access<Config, Outcome, Cap, AccessProposal>(&mut executable, account, AccessProposal());

    destroy_access<Cap, AccessProposal>(&mut executable, AccessProposal());
    executable.destroy(AccessProposal());

    access
}

// === [ACTION] Public functions ===

public fun new_access<Outcome, Cap, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    witness: W,    
) {
    proposal.add_action(AccessAction<Cap> {}, witness);
}

public fun access<Config, Outcome, Cap, W: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    witness: W, 
): Access<Cap> {
    let _access_mut: &mut AccessAction<Cap> = executable.action_mut(account.addr(), witness);
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);
    
    Access<Cap> {}
}

public fun destroy_access<Cap, W: drop>(executable: &mut Executable, witness: W) {
    let AccessAction<Cap> {} = executable.remove_action(witness);
}

public fun delete_access_action<Outcome, Cap>(expired: Expired<Outcome>) {
    let AccessAction<Cap> { .. } = expired.remove_expired_action();
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}
