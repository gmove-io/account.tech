/// Package managers can lock UpgradeCaps in the account. Caps can't be unlocked, this is to enforce the policies.
/// Any rule can be defined for the upgrade lock. The module provide a timelock rule by default, based on execution time.
/// Upon locking, the user can define an optional timelock corresponding to the minimum delay between an upgrade proposal and its execution.
/// The account can decide to make the policy more restrictive or destroy the Cap, to make the package immutable.

module account_actions::upgrade_policies;

// === Imports ===

use std::{
    string::String,
    type_name::TypeName
};
use sui::{
    package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt},
    clock::Clock,
    dynamic_field as df,
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};
use account_actions::version;

// === Error ===

#[error]
const EPolicyShouldRestrict: vector<u8> = b"Policy should be restrictive";
#[error]
const EInvalidPolicy: vector<u8> = b"Invalid policy number";
#[error]
const ENoLock: vector<u8> = b"No lock with this name";
#[error]
const ELockAlreadyExists: vector<u8> = b"Lock with this name already exists";

// === Structs ===

/// Dynamic field key for the UpgradeLock
public struct UpgradeKey has copy, drop, store {
    // address of the package that issued the UpgradeCap
    package: address,
}
/// Dynamic field wrapper restricting access to an UpgradeCap, with optional timelock
public struct UpgradeLock has key, store {
    id: UID,
    // name of the package
    name: String,
    // the cap to lock
    upgrade_cap: UpgradeCap,
    // each package can define its own config
    // DF: config: C,
}

/// Dynamic field key for TimeLock
public struct TimeLockKey has copy, drop, store {}
/// Dynamic field timelock config for the UpgradeLock
public struct TimeLock has store {
    delay_ms: u64,
}

/// [PROPOSAL] upgrades a package
public struct UpgradeProposal() has copy, drop;
/// [PROPOSAL] restricts a locked UpgradeCap
public struct RestrictProposal() has copy, drop;

/// [ACTION] upgrades a package
public struct UpgradeAction has store {
    // address of the package and key of the DOF
    package: address,
    // digest of the package build we want to publish
    digest: vector<u8>,
}
/// [ACTION] restricts a locked UpgradeCap
public struct RestrictAction has store {
    // address of the package and key of the DOF
    package: address,
    // downgrades to this policy
    policy: u8,
}

// === [MEMBER] Public Functions ===

/// Creates a new UpgradeLock and returns it
public fun new_lock(
    upgrade_cap: UpgradeCap,
    name: String,
    ctx: &mut TxContext
): UpgradeLock {
    UpgradeLock { 
        id: object::new(ctx),
        name,
        upgrade_cap,
    }
}

/// Adds a rule with any config to the upgrade lock
public fun add_rule<K: copy + drop + store, R: store>(
    lock: &mut UpgradeLock,
    key: K,
    rule: R,
) {
    df::add(&mut lock.id, key, rule);
}

/// Checks if a rule exists
public fun has_rule<K: copy + drop + store>(
    lock: &UpgradeLock,
    key: K,
): bool {
    df::exists_(&lock.id, key)
}

public fun get_rule<K: copy + drop + store, R: store>(
    lock: &UpgradeLock,
    key: K,
): &R {
    df::borrow(&lock.id, key)
}

/// Attaches the UpgradeLock as a Dynamic Field to the account
public fun lock_cap<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    lock: UpgradeLock,
) {
    auth.verify(account.addr());
    let package = lock.upgrade_cap.package().to_address();
    assert!(!has_lock(account, package), ELockAlreadyExists);
    account.add_managed_asset(UpgradeKey { package }, lock, version::current());
}

/// Locks a cap with a timelock rule
public fun lock_cap_with_timelock<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
    delay_ms: u64,
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext
) {
    let mut lock = new_lock(upgrade_cap, name, ctx);
    add_rule(&mut lock, TimeLockKey {}, TimeLock { delay_ms });
    lock_cap(auth, account, lock);
}

public fun has_lock<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    package: address
): bool {
    account.has_managed_asset(UpgradeKey { package })
}

public fun borrow_lock<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    package: address
): &UpgradeLock {
    account.borrow_managed_asset(UpgradeKey { package }, version::current())
}

public fun upgrade_cap(lock: &UpgradeLock): &UpgradeCap {
    &lock.upgrade_cap
} 

public fun has_timelock(lock: &UpgradeLock): bool {
    lock.has_rule(TimeLockKey {})
}

public fun time_delay(lock: &UpgradeLock): u64 {
    let rule: &TimeLock = lock.get_rule(TimeLockKey {});
    rule.delay_ms
}

// === [PROPOSAL] Public Functions ===

// step 1: propose an UpgradeAction by passing the digest of the package build
// execution_time is automatically set to now + timelock
// if timelock = 0, it means that upgrade can be executed at any time
public fun propose_upgrade<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    expiration_time: u64,
    package: address,
    digest: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, package), ENoLock);
    let lock = borrow_lock(account, package);
    let delay = if (lock.has_timelock()) lock.time_delay() else 0;

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        UpgradeProposal(),
        b"".to_string(),
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_time,
        ctx
    );

    new_upgrade(&mut proposal, package, digest, UpgradeProposal());
    account.add_proposal(proposal, version::current(), UpgradeProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: destroy UpgradeAction and return the UpgradeTicket for upgrading
public fun execute_upgrade<Config, Outcome>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): (UpgradeTicket, UpgradeLock) {
    do_upgrade(executable, account, version::current(), UpgradeProposal())
}    

// step 5: consume the ticket to upgrade  

// step 6: consume the receipt to commit the upgrade
public fun complete_upgrade<Config, Outcome>(
    executable: Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
    lock: UpgradeLock,
) {
    confirm_upgrade(&executable, account, receipt, lock, version::current(), UpgradeProposal());
    executable.destroy(version::current(), UpgradeProposal());
}

// step 1: propose an UpgradeAction by passing the digest of the package build
// execution_time is automatically set to now + timelock
public fun propose_restrict<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    expiration_time: u64,
    package: address,
    policy: u8,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, package), ENoLock);
    let lock = borrow_lock(account, package);
    let delay = if (lock.has_timelock()) lock.time_delay() else 0;
    let current_policy = lock.upgrade_cap.policy();

    let mut proposal = account.create_proposal(
        auth, 
        outcome,
        version::current(),
        RestrictProposal(),
        b"".to_string(),
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_time,
        ctx
    );

    new_restrict(&mut proposal, package, current_policy, policy, RestrictProposal());
    account.add_proposal(proposal, version::current(), RestrictProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: restrict the upgrade policy
public fun execute_restrict<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    do_restrict(&mut executable, account, version::current(), RestrictProposal());
    executable.destroy(version::current(), RestrictProposal());
}

// === [ACTION] Public Functions ===

public fun new_upgrade<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    package: address,
    digest: vector<u8>, 
    witness: W
) {
    proposal.add_action(UpgradeAction { package, digest }, witness);
}    

public fun do_upgrade<Config, Outcome, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
): (UpgradeTicket, UpgradeLock) {
    let UpgradeAction { package, digest } = executable.action(account.addr(), version, witness);
    let mut lock: UpgradeLock = account.remove_managed_asset(UpgradeKey { package }, version);

    let policy = lock.upgrade_cap.policy();
    let ticket = lock.upgrade_cap.authorize_upgrade(policy, digest);

    (ticket, lock)
}    

public fun confirm_upgrade<Config, Outcome, W: copy + drop>(
    executable: &Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
    mut lock: UpgradeLock,
    version: TypeName,
    witness: W,
) {
    // same checks as in `executable.action()`
    executable.deps().assert_is_dep(version);
    executable.issuer().assert_is_constructor(witness);
    executable.issuer().assert_is_account(account.addr());

    let new_package = receipt.package().to_address();
    package::commit_upgrade(&mut lock.upgrade_cap, receipt);
    account.add_managed_asset(UpgradeKey { package: new_package }, lock, version);
}

public fun delete_upgrade_action<Outcome>(expired: &mut Expired<Outcome>) {
    let UpgradeAction { .. } = expired.remove_expired_action();
}

public fun new_restrict<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    package: address,
    current_policy: u8, 
    policy: u8, 
    witness: W
) {    
    assert!(policy > current_policy, EPolicyShouldRestrict);
    assert!(
        policy == package::additive_policy() ||
        policy == package::dep_only_policy() ||
        policy == 255, // make immutable
        EInvalidPolicy
    );

    proposal.add_action(RestrictAction { package, policy }, witness);
}    

public fun do_restrict<Config, Outcome, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
) {
    let RestrictAction { package, policy } = executable.action(account.addr(), version, witness);

    if (policy == package::additive_policy()) {
        let lock_mut: &mut UpgradeLock = account.borrow_managed_asset_mut(UpgradeKey { package }, version);
        lock_mut.upgrade_cap.only_additive_upgrades();
    } else if (policy == package::dep_only_policy()) {
        let lock_mut: &mut UpgradeLock = account.borrow_managed_asset_mut(UpgradeKey { package }, version);
        lock_mut.upgrade_cap.only_dep_upgrades();
    } else {
        let UpgradeLock { id, upgrade_cap, .. } = account.remove_managed_asset(UpgradeKey { package }, version);
        package::make_immutable(upgrade_cap);
        id.delete();
    };
}

public fun delete_restrict_action<Outcome>(expired: &mut Expired<Outcome>) {
    let RestrictAction { .. } = expired.remove_expired_action();
}
