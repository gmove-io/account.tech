/// Package managers can lock UpgradeCaps in the multisig. Caps can't be unlocked to enforce the policies.
/// Any rule can be defined for the upgrade lock. The module provide a timelock rule by default, based on execution time.
/// Upon locking, the user can define an optional timelock corresponding to the minimum delay between an upgrade proposal and its execution.
/// The multisig can decide to make the policy more restrictive or destroy the Cap, to make the package immutable.

module kraken::upgrade_policies;

// === Imports ===

use std::string::String;
use sui::{
    package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt},
    transfer::Receiving,
    clock::Clock,
    dynamic_field as df
};
use kraken::multisig::{Multisig, Executable, Proposal};

// === Error ===

const EWrongUpgradeLock: u64 = 1;
const EPolicyShouldRestrict: u64 = 2;
const EInvalidPolicy: u64 = 3;
const EUpgradeNotExecuted: u64 = 4;
const ERestrictNotExecuted: u64 = 5;

// === Constants ===

const TIMELOCK_KEY: vector<u8> = b"TimeLock";

// === Structs ===

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// [ACTION]
public struct Upgrade has store {
    // digest of the package build we want to publish
    digest: vector<u8>,
    // UpgradeLock to receive to access the UpgradeCap
    lock_id: ID,
}

// [ACTION]
public struct Restrict has store {
    // restrict upgrade to this policy
    policy: u8,
    // UpgradeLock to receive to access the UpgradeCap
    lock_id: ID,
}

// Wrapper restricting access to an UpgradeCap, with optional timelock
// doesn't have store because non-transferrable
public struct UpgradeLock has key {
    id: UID,
    // name or description of the cap
    label: String,
    // multisig owning the lock
    multisig_addr: address,
    // the cap to lock
    upgrade_cap: UpgradeCap,
    // each package can define its own config
    // DF: config: C,
}

// timelock config for the UpgradeLock
public struct TimeLock has store {
    delay_ms: u64,
}

// === [MEMBER] Public Functions ===

// must be sent to multisig with put_back_cap afterwards
public fun lock_cap(
    multisig: &Multisig,
    label: String,
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext
): UpgradeLock {
    multisig.assert_is_member(ctx);
    UpgradeLock { 
        id: object::new(ctx), 
        label, 
        multisig_addr: multisig.addr(),
        upgrade_cap 
    }
}

// add a rule with any config to the upgrade lock
public fun add_rule<R: store>(
    lock: &mut UpgradeLock,
    key: vector<u8>,
    rule: R,
) {
    df::add(&mut lock.id, key, rule);
}

// check if a rule exists
public fun has_rule(
    lock: &UpgradeLock,
    key: vector<u8>,
): bool {
    df::exists_(&lock.id, key)
}

// lock a cap with a timelock rule
public fun lock_cap_with_timelock(
    multisig: &Multisig,
    label: String,
    delay_ms: u64,
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext
) {
    let mut lock = lock_cap(multisig, label, upgrade_cap, ctx);
    add_rule(&mut lock, TIMELOCK_KEY, TimeLock { delay_ms });
    put_back_cap(lock);
}

// borrow the lock that can only be put back in the multisig because no store
public fun borrow_cap(
    multisig: &mut Multisig, 
    lock: Receiving<UpgradeLock>,
    ctx: &mut TxContext
): UpgradeLock {
    multisig.assert_is_member(ctx);
    transfer::receive(multisig.uid_mut(), lock)
}

// can only be returned here, except if make_immutable
public fun put_back_cap(lock: UpgradeLock) {
    let addr = lock.multisig_addr;
    transfer::transfer(lock, addr);
}

// === [PROPOSAL] Public Functions ===

// step 1: propose an Upgrade by passing the digest of the package build
// execution_time is automatically set to now + timelock
// if timelock = 0, it means that upgrade can be executed at any time
public fun propose_upgrade(
    multisig: &mut Multisig, 
    key: String,
    expiration_epoch: u64,
    description: String,
    digest: vector<u8>,
    lock: &UpgradeLock,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let delay = lock.get_time_delay();

    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_epoch,
        ctx
    );

    new_upgrade(proposal_mut, digest, object::id(lock));
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: destroy Upgrade and return the UpgradeTicket for upgrading
public fun execute_upgrade(
    mut executable: Executable,
    lock: &mut UpgradeLock,
): UpgradeTicket {
    let ticket = upgrade(&mut executable, lock, Issuer {}, 0);
    destroy_upgrade(&mut executable, Issuer {});
    executable.destroy(Issuer {});

    ticket 
}    

// step 5: consume the receipt to commit the upgrade
public fun confirm_upgrade(
    upgrade_lock: &mut UpgradeLock,
    receipt: UpgradeReceipt,
) {
    package::commit_upgrade(&mut upgrade_lock.upgrade_cap, receipt);
}

// step 1: propose an Upgrade by passing the digest of the package build
// execution_time is automatically set to now + timelock
public fun propose_restrict(
    multisig: &mut Multisig, 
    key: String,
    expiration_epoch: u64,
    description: String,
    policy: u8,
    lock: &UpgradeLock,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let delay = lock.get_time_delay();

    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_epoch,
        ctx
    );
    new_restrict(proposal_mut, lock, policy);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: restrict the upgrade policy
public fun execute_restrict(
    mut executable: Executable,
    multisig: &mut Multisig,
    lock: UpgradeLock,
) {
    restrict(&mut executable, multisig, lock, Issuer {}, 0);
    destroy_restrict(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// [ACTION] Public Functions ===

public fun new_upgrade(proposal: &mut Proposal, digest: vector<u8>, lock_id: ID) {
    proposal.add_action(Upgrade { digest, lock_id });
}    

public fun upgrade<I: copy + drop>(
    executable: &mut Executable,
    lock: &mut UpgradeLock,
    issuer: I,
    idx: u64,
): UpgradeTicket {
    let upgrade_mut: &mut Upgrade = executable.action_mut(issuer, idx);
    assert!(object::id(lock) == upgrade_mut.lock_id, EWrongUpgradeLock);

    let policy = lock.upgrade_cap.policy();
    let ticket = lock.upgrade_cap.authorize_upgrade(policy, upgrade_mut.digest);
    // consume digest to ensure this function has been called exactly once
    upgrade_mut.digest = vector::empty();

    ticket
}    

public fun destroy_upgrade<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Upgrade { digest, lock_id: _ } = executable.remove_action(issuer);
    assert!(digest.is_empty(), EUpgradeNotExecuted);
}

public fun new_restrict(proposal: &mut Proposal, lock: &UpgradeLock, policy: u8) {
    let current_policy = lock.upgrade_cap.policy();
    assert!(policy > current_policy, EPolicyShouldRestrict);
    assert!(
        policy == package::additive_policy() ||
        policy == package::dep_only_policy() ||
        policy == 255, // make immutable
        EInvalidPolicy
    );

    proposal.add_action(Restrict { policy, lock_id: object::id(lock) });
}    

public fun restrict<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    mut lock: UpgradeLock,
    issuer: I,
    idx: u64,
) {
    multisig.assert_executed(executable);
    
    let restrict_mut: &mut Restrict = executable.action_mut(issuer, idx);
    assert!(object::id(&lock) == restrict_mut.lock_id, EWrongUpgradeLock);

    if (restrict_mut.policy == package::additive_policy()) {
        lock.upgrade_cap.only_additive_upgrades();
        transfer::transfer(lock, multisig.addr());
    } else if (restrict_mut.policy == package::dep_only_policy()) {
        lock.upgrade_cap.only_dep_upgrades();
        transfer::transfer(lock, multisig.addr());
    } else {
        let UpgradeLock { id, label: _, multisig_addr: _, upgrade_cap } = lock;
        package::make_immutable(upgrade_cap);
        id.delete();
    };
    // consume policy to ensure this function has been called exactly once
    restrict_mut.policy = 0;
}

public fun destroy_restrict<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Restrict { policy, lock_id: _ } = executable.remove_action(issuer);
    assert!(policy == 0, ERestrictNotExecuted);
}

fun get_time_delay(lock: &UpgradeLock): u64 {
    if (lock.has_rule(TIMELOCK_KEY)) {
        let timelock: &TimeLock = df::borrow(&lock.id, TIMELOCK_KEY);
        timelock.delay_ms
    } else {
        0
    }
}
