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
#[error]
const EWrongUpgradeCap: vector<u8> = b"Wrong UpgradeCap for the UpgradeRules";

// === Structs ===

/// Dynamic Object Field key for the UpgradeLock
public struct UpgradeCapKey has copy, drop, store {
    // address of the package that issued the UpgradeCap
    package: address,
}
/// Dynamic field key for the UpgradeLock
public struct UpgradeRulesKey has copy, drop, store {
    // address of the package that issued the UpgradeCap
    package: address,
}
/// Dynamic field wrapper restricting access to an UpgradeCap, with optional timelock
public struct UpgradeRules has store {
    // id of the UpgradeCap
    cap_id: ID,
    // name of the package
    name: String,
    // minimum delay between proposal and execution
    delay_ms: u64,
}

/// [COMMAND] witness defining the command to lock an UpgradeCap
public struct LockCommand() has drop;
/// [PROPOSAL] witness defining the proposal to upgrade a package
public struct UpgradeProposal() has copy, drop;
/// [PROPOSAL] witness defining the proposal to restrict an UpgradeCap
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

// === [COMMAND] Public Functions ===

/// Attaches the UpgradeCap as a Dynamic Object Field to the account
public fun lock_cap<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    cap: UpgradeCap,
    name: String, // name of the package
    delay_ms: u64, // minimum delay between proposal and execution
) {
    auth.verify_with_role<LockCommand>(account.addr(), b"".to_string());
    let package = cap.package().to_address();
    let cap_id = object::id(&cap);
    assert!(!has_cap(account, package), ELockAlreadyExists);

    account.add_managed_object(UpgradeCapKey { package }, cap, version::current());
    account.add_managed_struct(UpgradeRulesKey { package }, UpgradeRules { cap_id, name, delay_ms }, version::current());
}

public fun has_cap<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    package: address
): bool {
    account.has_managed_object(UpgradeCapKey { package })
}

// ! is this risky?
public fun borrow_cap<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    package: address
): &UpgradeCap {
    account.borrow_managed_object(UpgradeCapKey { package }, version::current())
} 

public fun borrow_rules<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    package: address
): &UpgradeRules {
    account.borrow_managed_struct(UpgradeRulesKey { package }, version::current())
}

public fun cap_id(rules: &UpgradeRules): ID {
    rules.cap_id
}

public fun name(rules: &UpgradeRules): String {
    rules.name
}

public fun time_delay(rules: &UpgradeRules): u64 {
    rules.delay_ms
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
    assert!(has_cap(account, package), ENoLock);
    let delay = borrow_rules(account, package).delay_ms;

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
): (UpgradeTicket, UpgradeCap, UpgradeRules) {
    do_upgrade(executable, account, version::current(), UpgradeProposal())
}    

// step 5: consume the ticket to upgrade  

// step 6: consume the receipt to commit the upgrade
public fun complete_upgrade<Config, Outcome>(
    executable: Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
    cap: UpgradeCap,
    rules: UpgradeRules,
) {
    confirm_upgrade(&executable, account, receipt, cap, rules, version::current(), UpgradeProposal());
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
    assert!(has_cap(account, package), ENoLock);
    let current_policy = borrow_cap(account, package).policy();
    let delay = borrow_rules(account, package).delay_ms;

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
): (UpgradeTicket, UpgradeCap, UpgradeRules) {
    let UpgradeAction { package, digest } = executable.action(account.addr(), version, witness);
    
    let rules: UpgradeRules = account.remove_managed_struct(UpgradeRulesKey { package }, version);
    let mut cap: UpgradeCap = account.remove_managed_object(UpgradeCapKey { package }, version);

    let policy = cap.policy();
    let ticket = cap.authorize_upgrade(policy, digest);

    (ticket, cap, rules)
}    

public fun confirm_upgrade<Config, Outcome, W: copy + drop>(
    executable: &Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
    mut cap: UpgradeCap,
    rules: UpgradeRules,
    version: TypeName,
    witness: W,
) {
    assert!(object::id(&cap) == rules.cap_id, EWrongUpgradeCap);
    // same checks as in `executable.action()`
    executable.deps().assert_is_dep(version);
    executable.issuer().assert_is_constructor(witness);
    executable.issuer().assert_is_account(account.addr());

    let new_package = receipt.package().to_address();
    package::commit_upgrade(&mut cap, receipt);

    account.add_managed_object(UpgradeCapKey { package: new_package }, cap, version);
    account.add_managed_struct(UpgradeRulesKey { package: new_package }, rules, version);
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
        let cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { package }, version);
        cap_mut.only_additive_upgrades();
    } else if (policy == package::dep_only_policy()) {
        let cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { package }, version);
        cap_mut.only_dep_upgrades();
    } else {
        let cap: UpgradeCap = account.remove_managed_object(UpgradeCapKey { package }, version);
        package::make_immutable(cap);
    };
}

public fun delete_restrict_action<Outcome>(expired: &mut Expired<Outcome>) {
    let RestrictAction { .. } = expired.remove_expired_action();
}
