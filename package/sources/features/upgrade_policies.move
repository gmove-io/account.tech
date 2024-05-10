/// This module allows to propose a MoveCall action to be executed by a Multisig.
/// The MoveCall action is unwrapped from an approved proposal 
/// and its digest is verified against the actual transaction (digest) 
/// the proposal can request to borrow or withdraw some objects from the Multisig's account in the PTB
/// allowing to get a Cap to call the proposed function.

module sui_multisig::upgrade_policies {
    use std::string::String;
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer::Receiving;
    use sui::clock::{Self, Clock};
    use sui_multisig::multisig::Multisig;
    use sui_multisig::owned::{Self, Access};

    // === Error ===

    const EDigestDoesntMatch: u64 = 0;
    const EWrongUpgradeLock: u64 = 1;

    // === Structs ===

    // action to be held in a Proposal
    public struct Upgrade has store {
        // digest of the package build we want to publish
        digest: vector<u8>,
        // UpgradeLock to receive to access the UpgradeCap
        upgrade_lock: ID,
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

    // === Multisig functions ===

    public fun lock_cap(
        multisig: &mut Multisig,
        label: String,
        time_lock: u64,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let lock = UpgradeLock { 
            id: object::new(ctx), 
            label, 
            time_lock, 
            upgrade_cap 
        };
        transfer::transfer(lock, multisig.addr());
    }

    // step 1: propose an Upgrade by passing the digest of the package build
    // execution_time is automatically set to now + timelock
    public fun propose(
        multisig: &mut Multisig, 
        name: String,
        expiration_epoch: u64,
        description: String,
        digest: vector<u8>,
        upgrade_lock: Receiving<UpgradeLock>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let received = transfer::receive(multisig.uid_mut(), upgrade_lock);
        let action = Upgrade { digest, upgrade_lock: received.id.uid_to_inner() };

        multisig.create_proposal(
            action,
            name,
            clock.timestamp_ms() + received.time_lock,
            expiration_epoch,
            description,
            ctx
        );
        transfer::transfer(received, multisig.addr());
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy Upgrade and return the UpgradeTicket for upgrading
    public fun execute(
        multisig: &mut Multisig,
        action: Upgrade,
        upgrade_lock: Receiving<UpgradeLock>,
    ): UpgradeTicket {
        let Upgrade { digest, upgrade_lock: lock_id } = action;
        let mut received = transfer::receive(multisig.uid_mut(), upgrade_lock);
        assert!(received.id.uid_to_inner() == lock_id, EWrongUpgradeLock);

        let policy =received.upgrade_cap.policy();
        let ticket = package::authorize_upgrade(
            &mut received.upgrade_cap, 
            policy, 
            digest
        );

        transfer::transfer(received, multisig.addr());
        ticket
    }    

    // step 5: consume the receipt to complete the upgrade
    public fun complete(
        multisig: &mut Multisig,
        upgrade_lock: Receiving<UpgradeLock>,
        receipt: UpgradeReceipt,
    ) {
        let mut received = transfer::receive(multisig.uid_mut(), upgrade_lock);
        package::commit_upgrade(&mut received.upgrade_cap, receipt);
        transfer::transfer(received, multisig.addr());
    }
}

