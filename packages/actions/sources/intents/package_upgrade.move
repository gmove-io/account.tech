module account_actions::package_upgrade_intents;

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
    package_upgrade,
    version,
};

// === Errors ===

const EInvalidExecutionTime: u64 = 0;

// === Structs ===

/// Intent Witness defining the intent to upgrade a package.
public struct UpgradePackageIntent() has copy, drop;
/// Intent Witness defining the intent to restrict an UpgradeCap.
public struct RestrictPolicyIntent() has copy, drop;

// === Public Functions ===

/// Creates an UpgradePackageIntent and adds it to an Account.
public fun request_upgrade_package<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String, 
    description: String,
    execution_time: u64,
    expiration_time: u64,
    package_name: String,
    digest: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(execution_time >= clock.timestamp_ms() + package_upgrade::get_time_delay(account, package_name), EInvalidExecutionTime);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        package_name,
        outcome,
        version::current(),
        UpgradePackageIntent(),
        ctx
    );

    package_upgrade::new_upgrade(
        &mut intent, account, package_name, digest, clock, version::current(), UpgradePackageIntent()
    );
    account.add_intent(intent, version::current(), UpgradePackageIntent());
}

/// Executes an UpgradePackageIntent, returns the UpgradeTicket for upgrading.
public fun execute_upgrade_package<Config, Outcome>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    clock: &Clock,
): UpgradeTicket {
    package_upgrade::do_upgrade(executable, account, clock, version::current(), UpgradePackageIntent())
}    

/// Need to consume the ticket to upgrade the package before completing the intent.

/// Consumes the receipt to commit the upgrade.
public fun complete_upgrade_package<Config, Outcome>(
    executable: Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
) {
    package_upgrade::confirm_upgrade(&executable, account, receipt, version::current(), UpgradePackageIntent());
    account.confirm_execution(executable, version::current(), UpgradePackageIntent());
}

/// Creates a RestrictPolicyIntent and adds it to an Account.
public fun request_restrict_policy<Config, Outcome>(
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
    
    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        package_name,
        outcome,
        version::current(),
        RestrictPolicyIntent(),
        ctx
    );

    package_upgrade::new_restrict(
        &mut intent, account, package_name, policy, version::current(), RestrictPolicyIntent()
    );
    account.add_intent(intent, version::current(), RestrictPolicyIntent());
}

/// Restricts the upgrade policy.
public fun execute_restrict_policy<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    package_upgrade::do_restrict(&mut executable, account, version::current(), RestrictPolicyIntent());
    account.confirm_execution(executable, version::current(), RestrictPolicyIntent());
}