/// Package managers can lock UpgradeCaps in the multisig. Caps can't be unlocked to enforce the policies.
/// Any rule can be defined for the upgrade lock. The module provide a timelock rule by default, based on execution time.
/// Upon locking, the user can define an optional timelock corresponding to the minimum delay between an upgrade proposal and its execution.
/// The multisig can decide to make the policy more restrictive or destroy the Cap, to make the package immutable.

module examples::upgrade_rule {
    use std::string::String;
    use sui::{
        package::UpgradeCap,
    };
    use kraken::{
        upgrade_policies::{Self, UpgradeLock},
        multisig::Multisig
    };

    // === Constants ===

    const MS_IN_DAY: u64 = 24 * 60 * 60 * 1000;
    const WEEKEND_UPGRADE_KEY: vector<u8> = b"WeekendUpgrade";

    // === Structs ===

    public struct Witness has drop {}

    // timelock config for the UpgradeLock
    public struct WeekendUpgrade has store {}

    // === [MEMBER] Public Functions ===

    // lock a cap with a timelock rule
    public fun lock_cap_with_weekend_upgrade(
        multisig: &Multisig,
        label: String,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        let mut lock = upgrade_policies::lock_cap(multisig, label, upgrade_cap, ctx);
        lock.add_rule(WEEKEND_UPGRADE_KEY, WeekendUpgrade {});
        lock.put_back_cap();
    }

    // === [PROPOSAL] Public Functions ===

    // step 1: propose an Upgrade by passing the digest of the package build
    // execution_time is automatically set to now + timelock
    // if timelock = 0, it means that upgrade can be executed at any time
    public fun propose_upgrade(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        digest: vector<u8>,
        lock: &UpgradeLock,
        ctx: &mut TxContext
    ) {
        // if there's a rule we enforce it
        if (lock.has_rule(WEEKEND_UPGRADE_KEY)) {
            assert!(weekend(execution_time));
        };

        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );

        upgrade_policies::new_upgrade(proposal_mut, digest, object::id(lock));
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy Upgrade and return the UpgradeTicket for upgrading (kraken::upgrade_policies::execute_upgrade)
    // step 5: consume the receipt to commit the upgrade (kraken::upgrade_policies::confirm_upgrade)

    // === Private functions ===

    fun weekend(timestamp: u64): bool {
        // how many since unix timestamp started
        let days = timestamp / MS_IN_DAY;
        // The unix epoch (1st Jan 1970) was a Thursday so shift days
        // since the epoch by 2 so that 0 = Saturday.
        if (((days + 2) % 7 == 0) || ((days + 3) % 7 == 0)) {
            true
        } else {
            false
        }
    }
}

