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
    intents::{Intent, Expired},
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

/// [COMMAND] witness defining the lock cap command, and associated role
public struct LockCommand() has drop;
/// [PROPOSAL] witness defining the access cap proposal, and associated role
public struct AccessIntent() has copy, drop;

/// Dynamic Object Field key for the Cap
public struct CapKey<phantom Cap> has copy, drop, store {}

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
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);

    let mut intent = account.create_intent(
        auth,
        key, 
        description, 
        execution_times, 
        expiration_time, 
        outcome,
        version::current(),
        AccessIntent(), 
        type_to_name<Cap>(), // the cap type is the witness role name 
        ctx
    );

    new_access<Outcome, Cap, AccessIntent>(&mut intent, AccessIntent());
    account.add_intent(intent, version::current(), AccessIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_access<Config, Outcome, Cap: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): (Borrow<Cap>, Cap) {
    do_access(executable, account, version::current(), AccessIntent())
}

// step 5: return the cap to destroy Borrow, the action and executable
public fun complete_access<Config, Outcome, Cap: key + store>(
    executable: Executable, 
    account: &mut Account<Config, Outcome>,
    borrow: Borrow<Cap>, 
    cap: Cap
) {
    return_cap(account, borrow, cap, version::current());
    account.confirm_execution(executable, version::current(), AccessIntent());
}

// === [ACTION] Public functions ===

public fun new_access<Outcome, Cap, W: drop>(
    intent: &mut Intent<Outcome>, 
    witness: W,    
) {
    intent.add_action(AccessAction<Cap> {}, witness);
}

public fun do_access<Config, Outcome, Cap: key + store, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W, 
): (Borrow<Cap>, Cap) {
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);
    // check to be sure this cap type has been approved
    let AccessAction<Cap> {} = account.process_action(executable, version, witness);
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

public fun delete_access<Cap>(
    expired: &mut Expired, 
    idx: u64,
) {
    let AccessAction<Cap> { .. } = expired.actions_mut().remove(idx);
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}
