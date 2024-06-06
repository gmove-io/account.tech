/// Package manager can lock UpgradeCaps in the multisig. Caps can't be unlocked.
/// Upon locking, the user defines a optional timelock corresponding to 
/// the minimum delay between an upgrade proposal and its execution.
/// The multisig can decide to make the policy more restrictive or destroy the Cap.

module kraken::upgrade_policies {
    use std::string::String;
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer::Receiving;
    use sui::clock::Clock;
    use kraken::multisig::{Multisig, Executable};

    // === Error ===

    const EWrongUpgradeLock: u64 = 1;
    const EPolicyShouldRestrict: u64 = 2;
    const EInvalidPolicy: u64 = 3;

    // === Structs ===

    public struct Witness has drop {}

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
        // enforced minimal duration in ms between proposal and upgrade (can be 0)
        time_lock: u64,
        // the cap to lock
        upgrade_cap: UpgradeCap,
    }

    // === [PROPOSALS] Public Functions ===

    public fun lock_cap(
        multisig: &Multisig,
        label: String,
        time_lock: u64,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ): ID {
        multisig.assert_is_member(ctx);
        let lock = UpgradeLock { 
            id: object::new(ctx), 
            label, 
            time_lock, 
            upgrade_cap 
        };

        let id = object::id(&lock);
        transfer::transfer(lock, multisig.addr());

        id
    }

    // step 1: propose an Upgrade by passing the digest of the package build
    // execution_time is automatically set to now + timelock
    public fun propose_upgrade(
        multisig: &mut Multisig, 
        key: String,
        expiration_epoch: u64,
        description: String,
        digest: vector<u8>,
        upgrade_lock: Receiving<UpgradeLock>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let received = transfer::receive(multisig.uid_mut(), upgrade_lock);

        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            clock.timestamp_ms() + received.time_lock,
            expiration_epoch,
            description,
            ctx
        );
        proposal_mut.push_action(new_upgrade(digest, received.id.uid_to_inner()));

        transfer::transfer(received, multisig.addr());
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy Upgrade and return the UpgradeTicket for upgrading
    public fun execute_upgrade(
        executable: Executable,
        multisig: &mut Multisig,
        upgrade_lock: Receiving<UpgradeLock>,
    ): (UpgradeTicket, UpgradeLock) {
        let upgrade: Upgrade = executable.pop_action(Witness {});
        let (digest, lock_id) = upgrade.destroy_upgrade();
        executable.destroy_executable(Witness {});
        
        let mut received = transfer::receive(multisig.uid_mut(), upgrade_lock);
        assert!(received.id.uid_to_inner() == lock_id, EWrongUpgradeLock);

        let policy = received.upgrade_cap.policy();
        let ticket = package::authorize_upgrade(
            &mut received.upgrade_cap, 
            policy, 
            digest
        );

        (ticket, received)
    }    

    // step 5: consume the receipt to complete the upgrade
    public fun complete_upgrade(
        multisig: &Multisig,
        mut upgrade_lock: UpgradeLock,
        receipt: UpgradeReceipt,
    ) {
        package::commit_upgrade(&mut upgrade_lock.upgrade_cap, receipt);
        transfer::transfer(upgrade_lock, multisig.addr());
    }

    // step 1: propose an Upgrade by passing the digest of the package build
    // execution_time is automatically set to now + timelock
    public fun propose_restrict(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        policy: u8,
        upgrade_lock: Receiving<UpgradeLock>,
        ctx: &mut TxContext
    ) {
        let received = transfer::receive(multisig.uid_mut(), upgrade_lock);
        let current_policy = received.upgrade_cap.policy();
        assert!(policy > current_policy, EPolicyShouldRestrict);
        assert!(
            policy == package::additive_policy() ||
            policy == package::dep_only_policy() ||
            policy == 255, // make immutable
            EInvalidPolicy
        );

        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        proposal_mut.push_action(new_restrict(policy, received.id.uid_to_inner()));

        transfer::transfer(received, multisig.addr());
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy Upgrade and return the UpgradeTicket for upgrading
    public fun execute_restrict(
        executable: &mut Executable,
        multisig: &mut Multisig,
        upgrade_lock: Receiving<UpgradeLock>,
    ) {
        let action: Restrict = executable.pop_action(Witness {});
        let (policy, lock_id) = destroy_restrict(action);
        let mut received = transfer::receive(multisig.uid_mut(), upgrade_lock);
        assert!(received.id.uid_to_inner() == lock_id, EWrongUpgradeLock);

        if (policy == package::additive_policy()) {
            received.upgrade_cap.only_additive_upgrades();
            transfer::transfer(received, multisig.addr());
        } else if (policy == package::dep_only_policy()) {
            received.upgrade_cap.only_dep_upgrades();
            transfer::transfer(received, multisig.addr());
        } else {
            let UpgradeLock { id, label: _, time_lock: _, upgrade_cap } = received;
            package::make_immutable(upgrade_cap);
            id.delete();
        };
    }

    // [ACTIONS] Public Functions ===

    public fun new_upgrade(digest: vector<u8>, lock_id: ID): Upgrade {
        Upgrade { digest, lock_id }
    }

    public fun destroy_upgrade(upgrade: Upgrade): (vector<u8>, ID) {
        let Upgrade { digest, lock_id } = upgrade;
        (digest, lock_id)
    }

    public fun new_restrict(policy: u8, lock_id: ID): Restrict {
        Restrict { policy, lock_id }
    }

    public fun destroy_restrict(restrict: Restrict): (u8, ID) {
        let Restrict { policy, lock_id } = restrict;
        (policy, lock_id)
    }

    // === Test Functions ===

    #[test_only]
    public fun upgrade_cap(lock: &UpgradeLock): &UpgradeCap {
        &lock.upgrade_cap
    }
}

