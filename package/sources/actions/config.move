/// This module allows to manage Multisig settings.
/// The action can be to add or remove members, to change the threshold or the name.
/// If one wants to update the weights of members, they must remove the members and add them back with new weights in the same proposal.
/// The new total weight must be lower than the threshold.
/// Teams can choose to use any version of the package and must explicitly migrate to the new version.

module kraken::config {
    use std::string::{Self, String};
    use sui::vec_map::{Self, VecMap};
    use kraken::multisig::{Multisig, Executable, Proposal};

    // === Errors ===

    const EThresholdTooHigh: u64 = 0;
    const ENotMember: u64 = 1;
    const EAlreadyMember: u64 = 2;
    const EThresholdNull: u64 = 3;
    const EMigrateNotExecuted: u64 = 4;
    const EVersionAlreadyUpdated: u64 = 5;
    const ENameAlreadySet: u64 = 6;
    const ENameNotSet: u64 = 7;
    const EMembersNotExecuted: u64 = 8;
    const EWeightsNotExecuted: u64 = 9;
    const ERolesNotExecuted: u64 = 10;

    // === Structs ===

    // delegated witness verifying a proposal is destroyed in the module where it was created
    public struct Witness has copy, drop {}

    // [ACTION] change the name
    public struct Name has store { 
        // new name
        name: String,
    }

    // [ACTION] add or remove members
    public struct Members has store {
        // addresses to remove
        to_remove: vector<address>,
        // addresses to add
        to_add: vector<address>,
    }

    // [ACTION] modify weights and threshold (total weigth)
    public struct Weights has store { 
        // new threshold, has to be <= to new total weight
        threshold: Option<u64>,
        // addresses to modify
        addresses: vector<address>,
        // new weights of the members 
        weights: vector<u64>,
    }

    // [ACTION] add or remove roles from chosen members
    public struct Roles has store { 
        // roles to add to each address
        to_add: VecMap<address, vector<String>>,
        // roles to remove from each address
        to_remove: VecMap<address, vector<String>>,
    }

    // [ACTION] update the version of the multisig
    public struct Migrate has store { 
        // the new version
        version: u64,
    }

    // === [PROPOSAL] Public functions ===

    // step 1: propose to change the name
    public fun propose_name(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        name: String,
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
        new_name(proposal_mut, name);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)

    // step 3: execute the action and modify Multisig object
    public fun execute_name(
        mut executable: Executable,
        multisig: &mut Multisig, 
    ) {
        name(&mut executable, multisig, Witness {}, 0);
        destroy_name(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // step 1: propose to modify multisig rules (everything touching weights)
    // all vectors can be empty (if to_modify || weights are empty, the other one must be too)
    // a member can be added and modified in the same proposal
    // threshold has to be valid (reachable and different from 0)
    public fun propose_modify_rules(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        threshold: Option<u64>, 
        to_add: vector<address>, 
        to_remove: vector<address>,
        to_modify: vector<address>,
        weights: vector<u64>,
        ctx: &mut TxContext
    ) {
        verify_new_rules(multisig, threshold, to_add, to_remove, to_modify, weights);
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        // must execute add members before modify weights in case we add and modify the same member
        new_members(proposal_mut, to_add, to_remove);
        new_weights(proposal_mut, threshold, to_modify, weights);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)

    // step 3: execute the action and modify Multisig object
    public fun execute_modify_rules(
        mut executable: Executable,
        multisig: &mut Multisig, 
    ) {
        members(&mut executable, multisig, Witness {}, 0);
        destroy_members(&mut executable, Witness {});
        weights(&mut executable, multisig, Witness {}, 1);
        destroy_weights(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // step 1: propose to add or remove roles for members
    public fun propose_roles(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        add_to_addr: vector<address>, 
        roles_to_add: vector<vector<String>>, 
        remove_to_addr: vector<address>,
        roles_to_remove: vector<vector<String>>,
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
        new_roles(
            proposal_mut, 
            add_to_addr, 
            roles_to_add, 
            remove_to_addr, 
            roles_to_remove
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)

    // step 3: execute the action and modify Multisig object
    public fun execute_roles(
        mut executable: Executable,
        multisig: &mut Multisig, 
    ) {
        roles(&mut executable, multisig, Witness {}, 0);
        destroy_roles(&mut executable, Witness {});
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

    public fun new_name(proposal: &mut Proposal, name: String) {
        proposal.add_action(Name { name });
    }

    public fun name<W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let name_mut: &mut Name = executable.action_mut(witness, idx);
        assert!(!name_mut.name.is_empty(), ENameAlreadySet);
        multisig.set_name(name_mut.name);
        name_mut.name = string::utf8(b""); // reset to confirm execution
    }
        
    public fun destroy_name<W: copy + drop>(
        executable: &mut Executable,
        witness: W,
    ) {
        let Name { name } = executable.remove_action(witness);
        assert!(name.is_empty(), ENameNotSet);
    }

    public fun new_members(
        proposal: &mut Proposal,
        to_add: vector<address>,
        to_remove: vector<address>, 
    ) { 
        proposal.add_action(Members { to_remove, to_add });
    }    
    
    public fun members<W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let members_mut: &mut Members = executable.action_mut(witness, idx);

        multisig.remove_members(&mut members_mut.to_remove);
        multisig.add_members(&mut members_mut.to_add);
    }

    public fun destroy_members<W: copy + drop>(
        executable: &mut Executable, 
        witness: W
    ) {
        let Members { to_add, to_remove } = executable.remove_action(witness);
        assert!(
            to_remove.is_empty() && to_add.is_empty(),
            EMembersNotExecuted
        );
    }

    public fun new_weights(
        proposal: &mut Proposal,
        threshold: Option<u64>, 
        addresses: vector<address>, 
        weights: vector<u64>,
    ) { 
        proposal.add_action(Weights { threshold, addresses, weights });
    }    
    
    public fun weights<W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let weights_mut: &mut Weights = executable.action_mut(witness, idx);

        if (weights_mut.threshold.is_some()) {
            multisig.set_threshold(weights_mut.threshold.extract());
        };
        
        multisig.modify_weights(&mut weights_mut.addresses, &mut weights_mut.weights);
    }

    public fun destroy_weights<W: copy + drop>(
        executable: &mut Executable, 
        witness: W
    ) {
        let Weights { threshold, addresses, weights } = executable.remove_action(witness);

        assert!(
            threshold.is_none() &&
            addresses.is_empty() &&
            weights.is_empty(),
            EWeightsNotExecuted
        );
    }

    public fun new_roles(
        proposal: &mut Proposal,
        addr_to_add: vector<address>, 
        roles_to_add: vector<vector<String>>, 
        addr_to_remove: vector<address>,
        roles_to_remove: vector<vector<String>>,
    ) { 
        proposal.add_action(Roles { 
            to_add: vec_map::from_keys_values(addr_to_add, roles_to_add), 
            to_remove: vec_map::from_keys_values(addr_to_remove, roles_to_remove) 
        });
    }
    
    public fun roles<W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let roles_mut: &mut Roles = executable.action_mut(witness, idx);

        let (mut addr_to_add, mut roles_to_add) = roles_mut.to_add.into_keys_values();
        multisig.add_roles(&mut addr_to_add, &mut roles_to_add);
        roles_mut.to_add = vec_map::empty();
        let (mut addr_to_remove, mut roles_to_remove) = roles_mut.to_remove.into_keys_values();
        multisig.remove_roles(&mut addr_to_remove, &mut roles_to_remove);
        roles_mut.to_remove = vec_map::empty();
    }

    public fun destroy_roles<W: copy + drop>(
        executable: &mut Executable, 
        witness: W
    ) {
        let Roles { to_add, to_remove } = executable.remove_action(witness);
        assert!(
            to_remove.is_empty() &&
            to_add.is_empty(),
            ERolesNotExecuted
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

    public fun verify_new_rules(
        multisig: &Multisig,
        threshold: Option<u64>, 
        mut to_add: vector<address>, 
        mut to_remove: vector<address>, 
        mut to_modify: vector<address>,
        mut weights: vector<u64>,
    ) {
        // save addresses to add for check
        let add_addr = to_add;
        // verify proposed addresses match current list and save weight
        let mut added_weight = 0;
        while (!to_add.is_empty()) {
            let addr = to_add.pop_back();
            assert!(!multisig.is_member(&addr), EAlreadyMember);
            added_weight = added_weight + 1;
        };
        let mut removed_weight = 0;
        while (!to_remove.is_empty()) {
            let addr = to_remove.pop_back();
            assert!(multisig.is_member(&addr), ENotMember);
            removed_weight = removed_weight + multisig.member_weight(&addr);
        };
        let mut add_modified_weight = 0;
        let mut remove_modified_weight = 0;
        while (!to_modify.is_empty()) {
            let addr = to_modify.pop_back();
            assert!(multisig.is_member(&addr) || add_addr.contains(&addr), ENotMember);
            let new_weight = weights.pop_back();
            let weight = if (multisig.is_member(&addr)) {
                multisig.member_weight(&addr)
            } else { 1 };

            if (new_weight == weight) {
                continue
            } else if (new_weight > weight) {
                let delta = new_weight - weight;
                add_modified_weight = add_modified_weight + delta;
            } else {
                let delta = weight - new_weight;
                remove_modified_weight = remove_modified_weight - delta;
            };
        };

        let mut new_threshold = multisig.threshold();
        if (threshold.is_some()) {
            // if threshold null, anyone can propose
            assert!(*threshold.borrow() > 0, EThresholdNull);
            new_threshold = *threshold.borrow();
        };
        // verify threshold is reachable with new members 
        let new_total_weight = 
            multisig.total_weight() 
            + added_weight 
            - removed_weight
            + add_modified_weight
            - remove_modified_weight;
        assert!(new_total_weight >= new_threshold, EThresholdTooHigh);
    }
}

