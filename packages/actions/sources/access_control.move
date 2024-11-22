/// Developers can restrict access to functions in their own package with a Cap that can be locked into the Smart Account. 
/// The Cap can be borrowed upon approval and used in other move calls within the same ptb before being returned.
/// 
/// The Cap pattern uses the object type as a proof of access, the object ID is never checked.
/// Therefore, only one Cap of a given type can be locked into the Smart Account.
/// And any Cap of that type can be returned to the Smart Account after being borrowed.
/// 
/// A good practice to follow is to use a different Cap type for each function that needs to be restricted.
/// This way, the Cap borrowed can't be misused in another function, by the person executing the proposal.
/// 
/// e.g.
/// 
/// public struct AdminCap has key, store {}
/// 
/// public fun foo(_: &AdminCap) { ... }

module account_actions::access_control;

// === Imports ===

use std::{
    type_name::{Self, TypeName},
    string::String
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};
use account_actions::version;

// === Errors ===

#[error]
const ENoLock: vector<u8> = b"No Lock for this Cap type";
#[error]
const EAlreadyLocked: vector<u8> = b"A Cap is already locked for this type";
#[error]
const EWrongAccount: vector<u8> = b"This Cap has not been borrowed from this acccount";

// === Structs ===    

/// Dynamic Object Field key for the Cap
public struct CapKey<phantom Cap> has copy, drop, store {}

/// [COMMAND] witness defining the lock cap command, and associated role
public struct LockCommand() has drop;
/// [PROPOSAL] witness defining the access cap proposal, and associated role
public struct AccessProposal() has copy, drop;

/// [ACTION] struct giving access to the Cap
public struct AccessAction<phantom Cap> has store {}

/// This struct is created upon approval to ensure the cap is returned
public struct Borrow<phantom Cap> {
    account_addr: address
}

// === [COMMAND] Public functions ===

/// Only a member can lock a Cap, the Cap must have at least store ability
public fun lock_cap<Config, Outcome, Cap: key + store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    cap: Cap,
) {
    auth.verify_with_role<LockCommand>(account.addr(), b"".to_string());
    assert!(!has_lock<Config, Outcome, Cap>(account), EAlreadyLocked);
    account.add_managed_object(CapKey<Cap> {}, cap, version::current());
}

public fun has_lock<Config, Outcome, Cap>(
    account: &Account<Config, Outcome>
): bool {
    account.has_managed_object(CapKey<Cap> {})
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
    expiration_time: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        AccessProposal(), 
        type_to_name<Cap>(), // the cap type is the witness role name 
        key, 
        description, 
        execution_time, 
        expiration_time, 
        ctx
    );

    new_access<Outcome, Cap, AccessProposal>(&mut proposal, AccessProposal());
    account.add_proposal(proposal, version::current(), AccessProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_access<Config, Outcome, Cap: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): (Borrow<Cap>, Cap) {
    do_access(executable, account, version::current(), AccessProposal())
}

// step 5: return the cap to destroy Borrow, the action and executable
public fun complete_access<Config, Outcome, Cap: key + store>(
    executable: Executable, 
    account: &mut Account<Config, Outcome>,
    borrow: Borrow<Cap>, 
    cap: Cap
) {
    return_cap(account, borrow, cap, version::current());
    executable.destroy(version::current(), AccessProposal());
}

// === [ACTION] Public functions ===

public fun new_access<Outcome, Cap, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    witness: W,    
) {
    proposal.add_action(AccessAction<Cap> {}, witness);
}

public fun do_access<Config, Outcome, Cap: key + store, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W, 
): (Borrow<Cap>, Cap) {
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);
    // check to be sure this cap type has been approved
    let AccessAction<Cap> {} = executable.action(account.addr(), version, witness);
    let cap = account.remove_managed_object(CapKey<Cap> {}, version);
    
    (Borrow<Cap> { account_addr: account.addr() }, cap)
}

public fun return_cap<Config, Outcome, Cap: key + store>(
    account: &mut Account<Config, Outcome>,
    borrow: Borrow<Cap>,
    cap: Cap,
    version: TypeName,
) {
    let Borrow<Cap> { account_addr } = borrow;
    assert!(account_addr == account.addr(), EWrongAccount);

    account.add_managed_object(CapKey<Cap> {}, cap, version);
}

public fun delete_access_action<Outcome, Cap>(expired: &mut Expired<Outcome>) {
    let AccessAction<Cap> { .. } = expired.remove_expired_action();
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}
