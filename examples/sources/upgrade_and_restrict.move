/// This module shows how to create a custom proposal from pre-existing actions.
/// Upgrade and Restrict are part of the kraken package.
/// Here we use them to compose a new proposal.
/// 
/// This proposal could be useful to promise the team or the users a last upgrade then making the package immutable.

module examples::upgrade_and_restrict {
    use std::string::String;
    use sui::package::UpgradeTicket;
    use kraken::{
        upgrade_policies::{Self, UpgradeLock},
        multisig::{Multisig, Executable},
    };

    // === Structs ===

    public struct Witness has drop {}

    // timelock config for the UpgradeLock
    public struct WeekendUpgrade has store {}

    // === [MEMBER] Public Functions ===

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
        policy: u8,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        // first we would like to upgrade
        upgrade_policies::new_upgrade(proposal_mut, digest, object::id(lock));
        // then we would like to restrict the policy
        upgrade_policies::new_restrict(proposal_mut, lock, policy);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy Upgrade and return the UpgradeTicket for upgrading
    public fun execute_upgrade(
        executable: &mut Executable,
        lock: &mut UpgradeLock,
    ): UpgradeTicket {
        // here the index is 0 because it's the first action in the proposal
        upgrade_policies::upgrade(executable, lock, Witness {}, 0) 
    } 

    // step 5: consume the receipt to commit the upgrade (kraken::upgrade_policies::confirm_upgrade)

    // step 6: restrict the upgrade policy
    public fun execute_restrict(
        executable: &mut Executable,
        multisig: &mut Multisig,
        lock: UpgradeLock,
    ) {
        // here the index is 1 because it's the second action in the proposal
        upgrade_policies::restrict(executable, multisig, lock, Witness {}, 1);
    }

    // step 7: destroy all the actions and the executable
    public fun complete_upgrade_and_restrict(
        mut executable: Executable,
    ) {
        upgrade_policies::destroy_upgrade(&mut executable, Witness {});
        upgrade_policies::destroy_restrict(&mut executable, Witness {});
        executable.destroy(Witness {});
    }
}

