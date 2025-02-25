/// This module shows how to create a custom intent from pre-existing actions.
/// Upgrade and Restrict are part of the AccountActions package.
/// Here we use them to compose a new intent.
/// 
/// This intent represents a "one last upgrade".
/// An enforceable promise from the team to the users making the package immutable after some final adjustments.

module account_examples::upgrade_and_restrict;

use std::string::String;
use sui::{
    package::{UpgradeTicket, UpgradeReceipt},
    clock::Clock,
};
use account_protocol::{
    executable::Executable,
    account::{Account, Auth},
};
use account_multisig::multisig::{Multisig, Approvals};
use account_actions::package_upgrade;
use account_examples::version;

// === Structs ===

/// Intent witness
public struct FinalUpgradeIntent() has copy, drop;


// === Public Functions ===

/// step 1: propose an Upgrade by passing the digest of the package build
public fun request_final_upgrade(
    auth: Auth,
    outcome: Approvals,
    multisig: &mut Account<Multisig, Approvals>, 
    key: String,
    execution_time: u64,
    expiration_time: u64,
    description: String,
    package_name: String,
    digest: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    multisig.verify(auth);

    let mut intent = multisig.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        FinalUpgradeIntent(),
        ctx
    );
    // first we would like to upgrade
    package_upgrade::new_upgrade(&mut intent, multisig, package_name, digest, clock, version::current(), FinalUpgradeIntent());
    // then we would like to make the package immutable (destroy the upgrade cap)
    package_upgrade::new_restrict(&mut intent, multisig, package_name, 255, version::current(), FinalUpgradeIntent());
    // add the intent to the multisig
    multisig.add_intent(intent, version::current(), FinalUpgradeIntent());
}

/// step 2: multiple members have to approve the intent (account_multisig::multisig::approve_intent)
/// step 3: execute the intent and return the Executable (account_multisig::multisig::execute_intent)

/// step 4: destroy Upgrade and return the UpgradeTicket for upgrading
public fun execute_upgrade(
    executable: &mut Executable,
    multisig: &mut Account<Multisig, Approvals>,
    clock: &Clock,
): UpgradeTicket {
    package_upgrade::do_upgrade(executable, multisig, clock, version::current(), FinalUpgradeIntent())
} 

/// Need to consume the ticket to upgrade the package before completing the intent.

/// step 5: consume the receipt to commit the upgrade
public fun complete_upgrade(
    executable: Executable,
    multisig: &mut Account<Multisig, Approvals>,
    receipt: UpgradeReceipt,
) {
    package_upgrade::confirm_upgrade(&executable, multisig, receipt, version::current(), FinalUpgradeIntent());
    multisig.confirm_execution(executable, version::current(), FinalUpgradeIntent());
}

/// step 6: restrict the upgrade policy (destroy the upgrade cap)
public fun execute_restrict(
    mut executable: Executable,
    multisig: &mut Account<Multisig, Approvals>,
) {
    package_upgrade::do_restrict(&mut executable, multisig, version::current(), FinalUpgradeIntent());
    multisig.confirm_execution(executable, version::current(), FinalUpgradeIntent());
}

/// step 7: destroy the intent to get the Expired hot potato as there is no execution left
/// and delete the actions from Expired in their own module 
