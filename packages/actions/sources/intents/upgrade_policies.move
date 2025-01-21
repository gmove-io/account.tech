module account_actions::upgrade_policies_intents;

// === Imports ===

use std::string::String;
use sui::{
    package::{UpgradeTicket, UpgradeReceipt},
    clock::Clock,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
};
use account_actions::{
    upgrade_policies,
    version,
};

// === Error ===

#[error]
const ENoLock: vector<u8> = b"No lock with this name";

// === Structs ===

/// [PROPOSAL] witness defining the proposal to upgrade a package
public struct UpgradeIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to restrict an UpgradeCap
public struct RestrictIntent() has copy, drop;

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
    account.verify(auth);
    assert!(upgrade_policies::has_cap(account, package_name), ENoLock);
    let execution_time = clock.timestamp_ms() + upgrade_policies::get_time_delay(account, package_name);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        package_name,
        outcome,
        version::current(),
        UpgradeIntent(),
        ctx
    );

    upgrade_policies::new_upgrade(
        &mut intent, account, digest, clock, version::current(), UpgradeIntent()
    );
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
    upgrade_policies::do_upgrade(executable, account, clock, version::current(), UpgradeIntent())
}    

// step 5: consume the ticket to upgrade  

// step 6: consume the receipt to commit the upgrade
public fun complete_upgrade<Config, Outcome>(
    executable: Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
) {
    upgrade_policies::confirm_upgrade(&executable, account, receipt, version::current(), UpgradeIntent());
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
    account.verify(auth);
    assert!(upgrade_policies::has_cap(account, package_name), ENoLock);
    let current_policy = upgrade_policies::get_cap_policy(account, package_name);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        package_name,
        outcome,
        version::current(),
        RestrictIntent(),
        ctx
    );

    upgrade_policies::new_restrict(
        &mut intent, account, current_policy, policy, version::current(), RestrictIntent()
    );
    account.add_intent(intent, version::current(), RestrictIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: restrict the upgrade policy
public fun execute_restrict<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    upgrade_policies::do_restrict(&mut executable, account, version::current(), RestrictIntent());
    account.confirm_execution(executable, version::current(), RestrictIntent());
}