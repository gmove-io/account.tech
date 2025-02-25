/// Developers can restrict access to functions in their own package with a Cap that can be locked into an Account. 
/// The Cap can be borrowed upon approval and used in other move calls within the same ptb before being returned.
/// 
/// The Cap pattern uses the object type as a proof of access, the object ID is never checked.
/// Therefore, only one Cap of a given type can be locked into the Smart Account.
/// And any Cap of that type can be returned to the Smart Account after being borrowed.
/// 
/// A good practice to follow is to use a different Cap type for each function that needs to be restricted.
/// This way, the Cap borrowed can't be misused in another function, by the person executing the intent.
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

const ENoLock: u64 = 0;
const EAlreadyLocked: u64 = 1;
const EWrongAccount: u64 = 2;

// === Structs ===    

/// Dynamic Object Field key for the Cap.
public struct CapKey<phantom Cap> has copy, drop, store {}

/// Action giving access to the Cap.
public struct BorrowAction<phantom Cap> has store {}

/// This hot potato is created upon approval to ensure the cap is returned.
public struct Borrowed<phantom Cap> {
    account_addr: address
}

// === Public functions ===

/// Authenticated user can lock a Cap, the Cap must have at least store ability.
public fun lock_cap<Config, Outcome, Cap: key + store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    cap: Cap,
) {
    account.verify(auth);
    assert!(!has_lock<_, _, Cap>(account), EAlreadyLocked);
    account.add_managed_asset(CapKey<Cap> {}, cap, version::current());
}

/// Checks if there is a Cap locked for a given type.
public fun has_lock<Config, Outcome, Cap>(
    account: &Account<Config, Outcome>
): bool {
    account.has_managed_asset(CapKey<Cap> {})
}

// Intent functions

/// Creates a BorrowAction and adds it to an intent.
public fun new_borrow<Config, Outcome, Cap, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW,    
) {
    account.add_action(intent, BorrowAction<Cap> {}, version_witness, intent_witness);
}

/// Processes a BorrowAction and returns a Borrowed hot potato and the Cap.
public fun do_borrow<Config, Outcome, Cap: key + store, IW: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW, 
): (Borrowed<Cap>, Cap) {
    assert!(has_lock<_, _, Cap>(account), ENoLock);
    // check to be sure this cap type has been approved
    let _action: &BorrowAction<Cap> = account.process_action(executable, version_witness, intent_witness);
    let cap = account.remove_managed_asset(CapKey<Cap> {}, version_witness);
    
    (Borrowed<Cap> { account_addr: account.addr() }, cap)
}

/// Returns a Cap to the Account and destroys the hot potato.
public fun return_borrowed<Config, Outcome, Cap: key + store>(
    account: &mut Account<Config, Outcome>,
    borrow: Borrowed<Cap>,
    cap: Cap,
    version_witness: VersionWitness,
) {
    let Borrowed<Cap> { account_addr } = borrow;
    assert!(account_addr == account.addr(), EWrongAccount);

    account.add_managed_asset(CapKey<Cap> {}, cap, version_witness);
}

/// Deletes a BorrowAction from an expired intent.
public fun delete_borrow<Cap>(expired: &mut Expired) {
    let BorrowAction<Cap> { .. } = expired.remove_action();
}