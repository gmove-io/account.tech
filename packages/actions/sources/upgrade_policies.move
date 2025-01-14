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
    vec_map::{Self, VecMap},
};
use account_protocol::{
    account::Account,
    intents::{Intent, Expired},
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
#[error]
const EUpgradeTooEarly: vector<u8> = b"Upgrade too early";
#[error]
const ENoPackageDoesntExist: vector<u8> = b"No package with this name";

// === Structs ===

/// [COMMAND] witness defining the command to lock an UpgradeCap
public struct LockCommand() has drop;
/// [PROPOSAL] witness defining the proposal to upgrade a package
public struct UpgradeIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to restrict an UpgradeCap
public struct RestrictIntent() has copy, drop;

/// Dynamic Object Field key for the UpgradeLock
public struct UpgradeCapKey has copy, drop, store {
    // name of the package
    name: String,
}
/// Dynamic field key for the UpgradeLock
public struct UpgradeRulesKey has copy, drop, store {
    // name of the package
    name: String,
}
/// Dynamic field key for the UpgradeLock
public struct UpgradeIndexKey has copy, drop, store {}

/// Dynamic field wrapper restricting access to an UpgradeCap, with optional timelock
public struct UpgradeRules has store {
    // minimum delay between proposal and execution
    delay_ms: u64,
}

public struct UpgradeIndex has store {
    // map of package name to address
    packages_info: VecMap<String, address>,
}

/// [ACTION] upgrades a package
public struct UpgradeAction has store {
    // digest of the package build we want to publish
    digest: vector<u8>,
    // intent creation time + timelock
    upgrade_time: u64,
}
/// [ACTION] restricts a locked UpgradeCap
public struct RestrictAction has store {
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
    assert!(!has_cap(account, name), ELockAlreadyExists);

    if (!account.has_managed_struct(UpgradeIndexKey {}))
        account.add_managed_struct(UpgradeIndexKey {}, UpgradeIndex { packages_info: vec_map::empty() }, version::current());

    let upgrade_index_mut: &mut UpgradeIndex = account.borrow_managed_struct_mut(UpgradeIndexKey {}, version::current());
    upgrade_index_mut.packages_info.insert(name, cap.package().to_address());
    
    account.add_managed_object(UpgradeCapKey { name }, cap, version::current());
    account.add_managed_struct(UpgradeRulesKey { name }, UpgradeRules { delay_ms }, version::current());
}

public fun has_cap<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): bool {
    account.has_managed_object(UpgradeCapKey { name })
}

public fun get_cap_package<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): address {
    let cap: &UpgradeCap = account.borrow_managed_object(UpgradeCapKey { name }, version::current());
    cap.package().to_address()
} 

public fun get_cap_version<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): u64 {
    let cap: &UpgradeCap = account.borrow_managed_object(UpgradeCapKey { name }, version::current());
    cap.version()
} 

public fun get_cap_policy<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): u8 {
    let cap: &UpgradeCap = account.borrow_managed_object(UpgradeCapKey { name }, version::current());
    cap.policy()
} 

public fun get_time_delay<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): u64 {
    let rules: &UpgradeRules = account.borrow_managed_struct(UpgradeRulesKey { name }, version::current());
    rules.delay_ms
}

public fun get_packages_info<Config, Outcome>(
    account: &Account<Config, Outcome>
): &VecMap<String, address> {
    let index: &UpgradeIndex = account.borrow_managed_struct(UpgradeIndexKey {}, version::current());
    &index.packages_info
}

public fun is_package_managed<Config, Outcome>(
    account: &Account<Config, Outcome>,
    package_addr: address
): bool {
    let index: &UpgradeIndex = account.borrow_managed_struct(UpgradeIndexKey {}, version::current());
    let mut i = 0;
    while (i < index.packages_info.size()) {
        let (_, value) = index.packages_info.get_entry_by_idx(i);
        if (value == package_addr) return true;
        i = i + 1;
    };
    false
}

public fun get_package_addr<Config, Outcome>(
    account: &Account<Config, Outcome>,
    package_name: String
): address {
    let index: &UpgradeIndex = account.borrow_managed_struct(UpgradeIndexKey {}, version::current());
    *index.packages_info.get(&package_name)
}

public fun get_package_name<Config, Outcome>(
    account: &Account<Config, Outcome>,
    package_addr: address
): String {
    let index: &UpgradeIndex = account.borrow_managed_struct(UpgradeIndexKey {}, version::current());
    let (mut i, mut name) = (0, b"".to_string());
    loop {
        let (name, addr) = index.packages_info.get_entry_by_idx(i);
        if (addr == package_addr) break *name;
        
        i = i + 1;
        if (i == index.packages_info.size()) abort ENoPackageDoesntExist;
    };

    name
}

// === [PROPOSAL] Public Functions ===

// step 1: propose an UpgradeAction by passing the digest of the package build
// execution_time is automatically set to now + timelock
// if timelock = 0, it means that upgrade can be executed at any time
public fun request_upgrade<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    expiration_time: u64,
    package_name: String,
    digest: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(has_cap(account, package_name), ENoLock);
    let execution_time = clock.timestamp_ms() + get_time_delay(account, package_name);

    let mut intent = account.create_intent(
        auth,
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        UpgradeIntent(),
        package_name,
        ctx
    );

    new_upgrade(&mut intent, digest, account, clock, UpgradeIntent());
    account.add_intent(intent, version::current(), UpgradeIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: destroy UpgradeAction and return the UpgradeTicket for upgrading
public fun execute_upgrade<Config, Outcome>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    clock: &Clock,
): UpgradeTicket {
    do_upgrade(executable, account, clock, version::current(), UpgradeIntent())
}    

// step 5: consume the ticket to upgrade  

// step 6: consume the receipt to commit the upgrade
public fun complete_upgrade<Config, Outcome>(
    executable: Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
) {
    confirm_upgrade(&executable, account, receipt, version::current(), UpgradeIntent());
    account.confirm_execution(executable, version::current(), UpgradeIntent());
}

// step 1: propose an UpgradeAction by passing the digest of the package build
// execution_time is automatically set to now + timelock
public fun request_restrict<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    package_name: String,
    policy: u8,
    ctx: &mut TxContext
) {
    assert!(has_cap(account, package_name), ENoLock);
    let current_policy = get_cap_policy(account, package_name);

    let mut intent = account.create_intent(
        auth, 
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        RestrictIntent(),
        package_name,
        ctx
    );

    new_restrict(&mut intent, current_policy, policy, RestrictIntent());
    account.add_intent(intent, version::current(), RestrictIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: restrict the upgrade policy
public fun execute_restrict<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    do_restrict(&mut executable, account, version::current(), RestrictIntent());
    account.confirm_execution(executable, version::current(), RestrictIntent());
}

// === [ACTION] Public Functions ===

public fun new_upgrade<Config, Outcome, W: drop>(
    intent: &mut Intent<Outcome>, 
    digest: vector<u8>, 
    account: &Account<Config, Outcome>,
    clock: &Clock,
    witness: W
) {
    let name = intent.issuer().role_name();
    let upgrade_time = clock.timestamp_ms() + get_time_delay(account, name);

    intent.add_action(UpgradeAction { digest, upgrade_time }, witness);
}    

public fun do_upgrade<Config, Outcome, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    clock: &Clock,
    version: TypeName,
    witness: W,
): UpgradeTicket {
    let action: &UpgradeAction = account.process_action(executable, version, witness);
    assert!(action.upgrade_time <= clock.timestamp_ms(), EUpgradeTooEarly);
    let name = executable.issuer().role_name();

    let mut cap: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version);
    let policy = cap.policy();

    cap.authorize_upgrade(policy, action.digest)
}    

public fun confirm_upgrade<Config, Outcome, W: copy + drop>(
    executable: &Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
    version: TypeName,
    witness: W,
) {
    // same checks as in `executable.action()`
    account.deps().assert_is_dep(version);
    executable.issuer().assert_is_constructor(witness);
    executable.issuer().assert_is_account(account.addr());

    let name = executable.issuer().role_name();
    let mut cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version);
    cap_mut.commit_upgrade(receipt);

    // update the index with the new package address
    let index_mut: &mut UpgradeIndex = account.borrow_managed_struct_mut(UpgradeIndexKey {}, version);
    *index_mut.packages_info.get_mut(&name) = cap_mut.package().to_address();
}

public fun delete_upgrade(expired: &mut Expired) {
    let UpgradeAction { .. } = expired.remove_action();
}

public fun new_restrict<Outcome, W: drop>(
    intent: &mut Intent<Outcome>, 
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

    intent.add_action(RestrictAction { policy }, witness);
}    

public fun do_restrict<Config, Outcome, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
) {
    let action: &RestrictAction = account.process_action(executable, version, witness);
    let name = executable.issuer().role_name();

    if (action.policy == package::additive_policy()) {
        let cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version);
        cap_mut.only_additive_upgrades();
    } else if (action.policy == package::dep_only_policy()) {
        let cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version);
        cap_mut.only_dep_upgrades();
    } else {
        let cap: UpgradeCap = account.remove_managed_object(UpgradeCapKey { name }, version);
        package::make_immutable(cap);
    };
}

public fun delete_restrict(expired: &mut Expired) {
    let RestrictAction { .. } = expired.remove_action();
}

// === Package Funtions ===

public(package) fun borrow_cap<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    package_addr: address
): &UpgradeCap {
    let name = get_package_name(account, package_addr);
    account.borrow_managed_object(UpgradeCapKey { name }, version::current())
}