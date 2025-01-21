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

use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
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

/// [ACTION] struct giving access to the Cap
public struct AccessAction<phantom Cap> has store {}

/// This struct is created upon approval to ensure the cap is returned
public struct Borrow<phantom Cap> {
    account_addr: address
}

// === Public functions ===

/// Only a member can lock a Cap, the Cap must have at least store ability
public fun lock_cap<Config, Outcome, Cap: key + store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    cap: Cap,
) {
    account.verify(auth);
    assert!(!has_lock<Config, Outcome, Cap>(account), EAlreadyLocked);
    account.add_managed_object(CapKey<Cap> {}, cap, version::current());
}

public fun has_lock<Config, Outcome, Cap>(
    account: &Account<Config, Outcome>
): bool {
    account.has_managed_object(CapKey<Cap> {})
}

// must be called in intent modules

public fun new_access<Config, Outcome, Cap, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW,    
) {
    account.add_action(intent, AccessAction<Cap> {}, version_witness, intent_witness);
}

public fun do_access<Config, Outcome, Cap: key + store, IW: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW, 
): (Borrow<Cap>, Cap) {
    assert!(has_lock<Config, Outcome, Cap>(account), ENoLock);
    // check to be sure this cap type has been approved
    let AccessAction<Cap> {} = account.process_action(executable, version_witness, intent_witness);
    let cap = account.remove_managed_object(CapKey<Cap> {}, version_witness);
    
    (Borrow<Cap> { account_addr: account.addr() }, cap)
}

public fun return_cap<Config, Outcome, Cap: key + store>(
    account: &mut Account<Config, Outcome>,
    borrow: Borrow<Cap>,
    cap: Cap,
    version_witness: VersionWitness,
) {
    let Borrow<Cap> { account_addr } = borrow;
    assert!(account_addr == account.addr(), EWrongAccount);

    account.add_managed_object(CapKey<Cap> {}, cap, version_witness);
}

public fun delete_access<Cap>(expired: &mut Expired) {
    let AccessAction<Cap> { .. } = expired.remove_action();
}