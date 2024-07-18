/// This module allows to manage Multisig settings.
/// The action can be to add or remove members, to change the threshold or the name.
/// If one wants to update the weights of members, they must remove the members and add them back with new weights in the same proposal.
/// The new total weight must be lower than the threshold.
/// Teams can choose to use any version of the package and must explicitly migrate to the new version.

module kraken::config {
    use std::string::String;
    use kraken::multisig::{Multisig, Executable, Proposal};

    // === Errors ===

    const EThresholdTooHigh: u64 = 0;
    const ENotMember: u64 = 1;
    const EAlreadyMember: u64 = 2;
    const EThresholdNull: u64 = 3;
    const EModifyNotExecuted: u64 = 4;
    const EMigrateNotExecuted: u64 = 5;
    const EVersionAlreadyUpdated: u64 = 6;

    // === Structs ===

    // delegated witness verifying a proposal is destroyed in the module where it was created
    public struct Witness has copy, drop {}

    // [ACTION] upgrade is separate for better ux
    public struct Modify has store { 
        // new name if any
        name: Option<String>,
        // new threshold, has to be <= to new total addresses
        threshold: Option<u64>,
        // addresses to remove, executed before adding new members
        to_remove: vector<address>,
        // addresses to add
        to_add: vector<address>,
        // weights of the members that will be added
        weights: vector<u64>,
    }

    // [ACTION] update the version of the multisig
    public struct Migrate has store { 
        // the new version
        version: u64,
    }

    // === [PROPOSAL] Public functions ===

    // a member can be removed and added to be updated
    // step 1: propose to modify multisig params
    public fun propose_modify(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        name: Option<String>,
        threshold: Option<u64>, 
        to_remove: vector<address>, 
        to_add: vector<address>, 
        weights: vector<u64>,
        ctx: &mut TxContext
    ) {
        verify_new_config(multisig, threshold, to_remove, to_add, weights);
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        new_modify(proposal_mut, name, threshold, to_remove, to_add, weights);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    
    // step 3: execute the action and modify Multisig object
    public fun execute_modify(
        mut executable: Executable,
        multisig: &mut Multisig, 
    ) {
        modify(&mut executable, multisig, Witness {}, 0);
        destroy_modify(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // step 1: propose to update the version
    public fun propose_migrate(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        version: u64,
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
        new_migrate(proposal_mut, version);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: execute the action and modify Multisig object
    public fun execute_migrate(
        mut executable: Executable,
        multisig: &mut Multisig, 
    ) {
        migrate(&mut executable, multisig, Witness {}, 0);
        destroy_migrate(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // === [ACTION] Public functions ===

    public fun new_modify(
        proposal: &mut Proposal,
        name: Option<String>,
        threshold: Option<u64>, 
        to_remove: vector<address>, 
        to_add: vector<address>, 
        weights: vector<u64>,
    ) { 
        proposal.add_action(Modify { name, threshold, to_add, weights, to_remove });
    }    
    
    public fun modify<W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let modify_mut: &mut Modify = executable.action_mut(witness, idx);

        if (modify_mut.name.is_some()) multisig.set_name(modify_mut.name.extract());
        if (modify_mut.threshold.is_some()) multisig.set_threshold(modify_mut.threshold.extract());
        multisig.remove_members(modify_mut.to_remove);
        multisig.add_members(modify_mut.to_add, modify_mut.weights);

        // @dev We need to reset the vectors here. Because add/remove members copy the vector<address>
        modify_mut.to_remove = vector[];
        modify_mut.to_add = vector[];
        modify_mut.weights = vector[];
    }

    public fun destroy_modify<W: copy + drop>(executable: &mut Executable, witness: W) {
        let Modify { name, threshold, to_remove, to_add, weights } = executable.remove_action(witness);

        assert!(name.is_none() &&
            threshold.is_none() &&
            to_remove.is_empty() &&
            to_add.is_empty() &&
            weights.is_empty(),
            EModifyNotExecuted
        );
    }

    public fun new_migrate(proposal: &mut Proposal, version: u64) {
        proposal.add_action(Migrate { version });
    }

    public fun migrate<W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let migrate_mut: &mut Migrate = executable.action_mut(witness, idx);
        assert!(migrate_mut.version != 0, EVersionAlreadyUpdated);
        multisig.set_version(migrate_mut.version);
        migrate_mut.version = 0; // reset to 0 to enforce exactly one execution
    }
        
    public fun destroy_migrate<W: copy + drop>(
        executable: &mut Executable,
        witness: W,
    ) {
        let Migrate { version } = executable.remove_action(witness);
        assert!(version == 0, EMigrateNotExecuted);
    }

    public fun verify_new_config(
        multisig: &Multisig,
        threshold: Option<u64>, 
        to_remove: vector<address>, 
        to_add: vector<address>, 
        weights: vector<u64>,
    ) {
        // verify proposed addresses match current list
        let (mut i, mut added_weight) = (0, 0);
        while (i < to_add.length()) {
            assert!(!multisig.is_member(&to_add[i]), EAlreadyMember);
            added_weight = added_weight + weights[i];
            i = i + 1;
        };
        let (mut j, mut removed_weight) = (0, 0);
        while (j < to_remove.length()) {
            assert!(multisig.is_member(&to_remove[j]), ENotMember);
            removed_weight = removed_weight + multisig.member_weight(&to_remove[j]);
            j = j + 1;
        };

        let new_threshold = if (threshold.is_some()) {
            // if threshold null, anyone can propose
            assert!(*threshold.borrow() > 0, EThresholdNull);
            *threshold.borrow()
        } else {
            multisig.threshold()
        };
        // verify threshold is reachable with new members 
        let new_total_weight = multisig.total_weight() + added_weight - removed_weight;
        assert!(new_total_weight >= new_threshold, EThresholdTooHigh);
    }
}

