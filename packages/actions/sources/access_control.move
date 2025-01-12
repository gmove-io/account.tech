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
    type_name,
    string::String
};
use account_protocol::{
    account::Account,
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

public struct Witness() has drop;

/// Dynamic Object Field key for the Cap
public struct CapKey<phantom Cap> has copy, drop, store {}

/// [ACTION] struct giving access to the Cap
public struct AccessAction<phantom Cap> has drop, store {}

/// This struct is created upon execution to ensure the cap is returned
public struct Borrow<phantom Cap> {
    account_addr: address
}

// === [COMMAND] Public functions ===

/// Only a member can lock a Cap, the Cap must have at least store ability
public fun lock_cap<Config, Cap: key + store>(
    auth: Auth,
    account: &mut Account<Config>,
    cap: Cap,
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(!has_lock<Config, Cap>(account), EAlreadyLocked);
    account.add_managed_object(CapKey<Cap> {}, cap, version::current());
}

public fun has_lock<Config, Cap>(
    account: &Account<Config>
): bool {
    account.has_managed_object(CapKey<Cap> {})
}

// === [PROPOSAL] Public functions ===

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun request_access<Config, Outcome: store, Cap>(
    auth: Auth,
    account: &mut Account<Config>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    outcome: Outcome,
) {
    assert!(has_lock<Config, Cap>(account), ENoLock);

    account.create_intent(
        auth,
        key, 
        description, 
        execution_time, 
        expiration_time, 
        outcome,
        AccessAction<Cap> {},
        version::current(),
        Witness(), 
        type_name::get<Cap>().into_string().to_string(), // the cap type is the witness role name 
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_access<Config, Cap: key + store>(
    executable: &mut Executable<AccessAction<Cap>>,
    account: &mut Account<Config>,
): (Borrow<Cap>, Cap) {
    assert!(has_lock<Config, Cap>(account), ENoLock);
    // check to be sure this cap type has been approved
    let _ = executable.action_mut(account.addr(), version::current(), Witness());
    let cap = account.remove_managed_object(CapKey<Cap> {}, version::current());
    
    (Borrow<Cap> { account_addr: account.addr() }, cap)
}

// step 5: return the cap to destroy Borrow, the action and executable
public fun complete_access<Config, Cap: key + store>(
    executable: Executable<AccessAction<Cap>>, 
    account: &mut Account<Config>,
    borrow: Borrow<Cap>, 
    cap: Cap
) {
    let Borrow<Cap> { account_addr } = borrow;
    assert!(account_addr == account.addr(), EWrongAccount);

    account.add_managed_object(CapKey<Cap> {}, cap, version::current());
    executable.destroy(version::current(), Witness());
}
