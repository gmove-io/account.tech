/// Package managers can lock UpgradeCaps in the account. Caps can't be unlocked, this is to enforce the policies.
/// Any rule can be defined for the upgrade lock. The module provide a timelock rule by default, based on execution time.
/// Upon locking, the user can define an optional timelock corresponding to the minimum delay between an upgrade proposal and its execution.
/// The account can decide to make the policy more restrictive or destroy the Cap, to make the package immutable.

module account_actions::upgrade_policies;

// === Imports ===

use std::string::String;
use sui::{
    package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt},
    clock::Clock,
    vec_map::{Self, VecMap},
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::version;

// === Error ===

#[error]
const EPolicyShouldRestrict: vector<u8> = b"Policy should be restrictive";
#[error]
const EInvalidPolicy: vector<u8> = b"Invalid policy number";
#[error]
const ELockAlreadyExists: vector<u8> = b"Lock with this name already exists";
#[error]
const EUpgradeTooEarly: vector<u8> = b"Upgrade too early";
#[error]
const ENoPackageDoesntExist: vector<u8> = b"No package with this name";

// === Structs ===

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
    account.verify(auth);
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
    if (!account.has_managed_struct(UpgradeIndexKey {})) return false;
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
    let (mut i, mut package_name) = (0, b"".to_string());
    loop {
        let (name, addr) = index.packages_info.get_entry_by_idx(i);
        package_name = *name;
        if (addr == package_addr) break package_name;
        
        i = i + 1;
        if (i == index.packages_info.size()) abort ENoPackageDoesntExist;
    };
    
    package_name
}

// === [ACTION] Public Functions ===

public fun new_upgrade<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>,
    digest: vector<u8>, 
    clock: &Clock,
    version_witness: VersionWitness,
    intent_witness: IW
) {
    let name = intent.role_managed_name();
    let upgrade_time = clock.timestamp_ms() + get_time_delay(account, name);

    account.add_action(intent, UpgradeAction { digest, upgrade_time }, version_witness, intent_witness);
}    

public fun do_upgrade<Config, Outcome, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    clock: &Clock,
    version_witness: VersionWitness,
    intent_witness: IW,
): UpgradeTicket {
    let name = executable.managed_name();
    let action: &UpgradeAction = account.process_action(executable, version_witness, intent_witness);
    let (digest, upgrade_time) = (action.digest, action.upgrade_time);
    assert!(upgrade_time <= clock.timestamp_ms(), EUpgradeTooEarly);

    let cap: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version_witness);
    let policy = cap.policy();

    cap.authorize_upgrade(policy, digest)
}    

public fun confirm_upgrade<Config, Outcome, IW: copy + drop>(
    executable: &Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    // same checks as in `executable.action()`
    account.deps().check(version_witness);
    executable.issuer().assert_is_intent(intent_witness);
    executable.issuer().assert_is_account(account.addr());

    let name = executable.managed_name();
    let cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version_witness);
    cap_mut.commit_upgrade(receipt);
    let new_package_addr = cap_mut.package().to_address();

    // update the index with the new package address
    let index_mut: &mut UpgradeIndex = account.borrow_managed_struct_mut(UpgradeIndexKey {}, version_witness);
    *index_mut.packages_info.get_mut(&name) = new_package_addr;
}

public fun delete_upgrade(expired: &mut Expired) {
    let UpgradeAction { .. } = expired.remove_action();
}

public fun new_restrict<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>,
    current_policy: u8, 
    policy: u8, 
    version_witness: VersionWitness,
    intent_witness: IW
) {    
    assert!(policy > current_policy, EPolicyShouldRestrict);
    assert!(
        policy == package::additive_policy() ||
        policy == package::dep_only_policy() ||
        policy == 255, // make immutable
        EInvalidPolicy
    );

    account.add_action(intent, RestrictAction { policy }, version_witness, intent_witness);
}    

public fun do_restrict<Config, Outcome, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let name = executable.managed_name();
    let action: &RestrictAction = account.process_action(executable, version_witness, intent_witness);

    if (action.policy == package::additive_policy()) {
        let cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version_witness);
        cap_mut.only_additive_upgrades();
    } else if (action.policy == package::dep_only_policy()) {
        let cap_mut: &mut UpgradeCap = account.borrow_managed_object_mut(UpgradeCapKey { name }, version_witness);
        cap_mut.only_dep_upgrades();
    } else {
        let cap: UpgradeCap = account.remove_managed_object(UpgradeCapKey { name }, version_witness);
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