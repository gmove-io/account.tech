/// Package managers can lock UpgradeCaps in the multisig. Caps can't be unlocked to enforce the policies.
/// Any rule can be defined for the upgrade lock. The module provide a timelock rule by default, based on execution time.
/// Upon locking, the user can define an optional timelock corresponding to the minimum delay between an upgrade proposal and its execution.
/// The multisig can decide to make the policy more restrictive or destroy the Cap, to make the package immutable.

module kraken_actions::upgrade_policies;

// === Imports ===

use std::string::String;
use sui::{
    package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt},
    clock::Clock,
    dynamic_field as df,
    event,
};
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
};

// === Error ===

const EPolicyShouldRestrict: u64 = 1;
const EInvalidPolicy: u64 = 2;
const EUpgradeNotExecuted: u64 = 3;
const ERestrictNotExecuted: u64 = 4;

// === Events ===

public struct Upgraded has copy, drop, store {
    package_id: ID,
    digest: vector<u8>,
}

public struct Restricted has copy, drop, store {
    package_id: ID,
    policy: u8,
}

// === Structs ===

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// df key for the UpgradeLock
public struct UpgradeKey has copy, drop, store { name: String }

// Wrapper restricting access to an UpgradeCap, with optional timelock
public struct UpgradeLock has key, store {
    id: UID,
    // the cap to lock
    upgrade_cap: UpgradeCap,
    // each package can define its own config
    // DF: config: C,
}

// df key for TimeLock
public struct TimeLockKey has copy, drop, store {}

// timelock config for the UpgradeLock
public struct TimeLock has store {
    delay_ms: u64,
}

// [ACTION]
public struct Upgrade has store {
    // digest of the package build we want to publish
    digest: vector<u8>,
}

// [ACTION]
public struct Restrict has store {
    // restrict upgrade to this policy
    policy: u8,
}

// === [MEMBER] Public Functions ===

public fun new_lock(
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext
): UpgradeLock {
    UpgradeLock { 
        id: object::new(ctx),
        upgrade_cap 
    }
}

// add a rule with any config to the upgrade lock
public fun add_rule<K: copy + drop + store, R: store>(
    lock: &mut UpgradeLock,
    key: K,
    rule: R,
) {
    df::add(&mut lock.id, key, rule);
}

// check if a rule exists
public fun has_rule<K: copy + drop + store>(
    lock: &UpgradeLock,
    key: K,
): bool {
    df::exists_(&lock.id, key)
}

public fun lock_cap(
    lock: UpgradeLock,
    multisig: &mut Multisig,
    name: String,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    multisig.add_managed_asset(Issuer {}, UpgradeKey { name }, lock);
}

// lock a cap with a timelock rule
public fun lock_cap_with_timelock(
    multisig: &mut Multisig,
    name: String,
    delay_ms: u64,
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext
) {
    let mut lock = new_lock(upgrade_cap, ctx);
    add_rule(&mut lock, TimeLockKey {}, TimeLock { delay_ms });
    lock.lock_cap(multisig, name, ctx);
}

public fun borrow_lock(multisig: &Multisig, name: String): &UpgradeLock {
    multisig.borrow_managed_asset(Issuer {}, UpgradeKey { name })
}

public fun borrow_lock_mut(multisig: &mut Multisig, name: String): &mut UpgradeLock {
    multisig.borrow_managed_asset_mut(Issuer {}, UpgradeKey { name })
}

public fun upgrade_cap(lock: &UpgradeLock): &UpgradeCap {
    &lock.upgrade_cap
} 

// === [PROPOSAL] Public Functions ===

// step 1: propose an Upgrade by passing the digest of the package build
// execution_time is automatically set to now + timelock
// if timelock = 0, it means that upgrade can be executed at any time
public fun propose_upgrade(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    expiration_epoch: u64,
    name: String,
    digest: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let lock = borrow_lock(multisig, name);
    let delay = lock.time_delay();

    let proposal_mut = multisig.create_proposal(
        Issuer {},
        name,
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_epoch,
        ctx
    );

    new_upgrade(proposal_mut, digest);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: destroy Upgrade and return the UpgradeTicket for upgrading
public fun execute_upgrade(
    executable: &mut Executable,
    multisig: &mut Multisig,
): UpgradeTicket {
    upgrade(executable, multisig, Issuer {})
}    

// step 5: consume the receipt to commit the upgrade
public fun confirm_upgrade(
    mut executable: Executable,
    multisig: &mut Multisig,
    receipt: UpgradeReceipt,
) {
    let name = executable.auth().name();
    let lock_mut = borrow_lock_mut(multisig, name);
    package::commit_upgrade(&mut lock_mut.upgrade_cap, receipt);
    
    destroy_upgrade(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// step 1: propose an Upgrade by passing the digest of the package build
// execution_time is automatically set to now + timelock
public fun propose_restrict(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    expiration_epoch: u64,
    name: String,
    policy: u8,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let lock = borrow_lock(multisig, name);
    let delay = lock.time_delay();
    let current_policy = lock.upgrade_cap.policy();

    let proposal_mut = multisig.create_proposal(
        Issuer {},
        name,
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_epoch,
        ctx
    );
    new_restrict(proposal_mut, current_policy, policy);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: restrict the upgrade policy
public fun execute_restrict(
    mut executable: Executable,
    multisig: &mut Multisig,
) {
    restrict(&mut executable, multisig, Issuer {});
    destroy_restrict(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// [ACTION] Public Functions ===

public fun new_upgrade(proposal: &mut Proposal, digest: vector<u8>) {
    proposal.add_action(Upgrade { digest });
}    

public fun upgrade<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    issuer: I,
): UpgradeTicket {
    let name = executable.auth().name();
    let upgrade_mut: &mut Upgrade = executable.action_mut(issuer, multisig.addr());
    let lock_mut = borrow_lock_mut(multisig, name);

    event::emit(Upgraded {
        package_id: lock_mut.upgrade_cap.package(),
        digest: upgrade_mut.digest,
    });

    let policy = lock_mut.upgrade_cap.policy();
    let ticket = lock_mut.upgrade_cap.authorize_upgrade(policy, upgrade_mut.digest);
    // consume digest to ensure this function has been called exactly once
    upgrade_mut.digest = vector::empty();

    ticket
}    

public fun destroy_upgrade<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Upgrade { digest, .. } = executable.remove_action(issuer);
    assert!(digest.is_empty(), EUpgradeNotExecuted);
}

public fun new_restrict(proposal: &mut Proposal, current_policy: u8, policy: u8) {    
    assert!(policy > current_policy, EPolicyShouldRestrict);
    assert!(
        policy == package::additive_policy() ||
        policy == package::dep_only_policy() ||
        policy == 255, // make immutable
        EInvalidPolicy
    );

    proposal.add_action(Restrict { policy });
}    

public fun restrict<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    issuer: I,
) {
    let name = executable.auth().name();
    let restrict_mut: &mut Restrict = executable.action_mut(issuer, multisig.addr());

    let (package_id, policy) = if (restrict_mut.policy == package::additive_policy()) {
        let lock_mut: &mut UpgradeLock = multisig.borrow_managed_asset_mut(Issuer {}, UpgradeKey { name });
        lock_mut.upgrade_cap.only_additive_upgrades();
        (lock_mut.upgrade_cap.package(), restrict_mut.policy)
    } else if (restrict_mut.policy == package::dep_only_policy()) {
        let lock_mut: &mut UpgradeLock = multisig.borrow_managed_asset_mut(Issuer {}, UpgradeKey { name });
        lock_mut.upgrade_cap.only_dep_upgrades();
        (lock_mut.upgrade_cap.package(), restrict_mut.policy)
    } else {
        let lock: UpgradeLock = multisig.remove_managed_asset(Issuer {}, UpgradeKey { name });
        let (package_id, policy) = (lock.upgrade_cap.package(), restrict_mut.policy);
        let UpgradeLock { id, upgrade_cap } = lock;
        package::make_immutable(upgrade_cap);
        id.delete();
        (package_id, policy)
    };

    event::emit(Restricted {
        package_id,
        policy,
    });
    // consume policy to ensure this function has been called exactly once
    restrict_mut.policy = 0;
}

public fun destroy_restrict<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Restrict { policy, .. } = executable.remove_action(issuer);
    assert!(policy == 0, ERestrictNotExecuted);
}

fun time_delay(lock: &UpgradeLock): u64 {
    if (lock.has_rule(TimeLockKey {})) {
        let timelock: &TimeLock = df::borrow(&lock.id, TimeLockKey {});
        timelock.delay_ms
    } else {
        0
    }
}
