/// This is the core module managing Multisig and Proposals.
/// It provides the apis to create, approve and execute proposals with actions.
/// 
/// Here is the flow:
///   1. A proposal is created by pushing actions into it. 
///      Actions are stacked from last to first, they must be executed then destroyed from last to first.
///   2. When the threshold is reached, a proposal can be executed. 
///      This returns an Executable hot potato constructed from certain fields of the approved Proposal. 
///      It is directly passed into action functions to enforce multisig approval for an action to be executed.
///   3. The module that created the proposal must destroy all of the actions and the Executable after execution 
///      by passing the same witness that was used for instanciation. 
///      This prevents the actions or the proposal to be stored instead of executed.

module kraken::multisig {
    use std::{
        string::String, 
        type_name::{Self, TypeName}
    };
    use sui::{
        clock::Clock, 
        vec_set::{Self, VecSet}, 
        vec_map::{Self, VecMap}, 
        bag::{Self, Bag}
    };

    // === Errors ===

    const ECallerIsNotMember: u64 = 0;
    const EThresholdNotReached: u64 = 1;
    const ECantBeExecutedYet: u64 = 2;
    const ENotIssuerModule: u64 = 3;
    const EHasntExpired: u64 = 4;
    const EWrongVersion: u64 = 5;
    const ENotMultisigExecutable: u64 = 6;

    // === Constants ===

    const VERSION: u64 = 1;

    // === Structs ===

    // shared object 
    public struct Multisig has key {
        id: UID,
        // version of the package this multisig is using
        version: u64,
        // human readable name to differentiate the multisigs
        name: String,
        // has to be always <= sum(members.weight)
        threshold: u64,
        // total weight of all members, if = members.length then all weights = 1
        total_weight: u64,
        // members of the multisig
        members: VecMap<address, Member>,
        // open proposals, key should be a unique descriptive name
        proposals: VecMap<String, Proposal>,
    }

    // struct for managing and displaying members
    public struct Member has store {
        // voting power of the member
        weight: u64,
        // ID of the member's account, none if he didn't join yet
        account_id: Option<ID>,
    }

    // proposal owning a single action requested to be executed
    // can be executed if length(approved) >= multisig.threshold
    public struct Proposal has key, store {
        id: UID,
        // module that issued the proposal and must destroy it
        module_witness: TypeName,
        // what this proposal aims to do, for informational purpose
        description: String,
        // the proposal can be deleted from this epoch
        expiration_epoch: u64,
        // proposer can add a timestamp_ms before which the proposal can't be executed
        // can be used to schedule actions via a backend
        execution_time: u64,
        // heterogenous vector of actions to be executed from last to first
        actions: Bag,
        // total weight of all members that approved the proposal
        approval_weight: u64,
        // who has approved the proposal
        approved: VecSet<address>,
    }

    // hot potato ensuring the action in the proposal is executed as it can't be stored
    public struct Executable {
        // multisig that executed the proposal
        multisig_addr: address,
        // module that issued the proposal and must destroy it
        module_witness: TypeName,
        // actions to be executed from last to first
        actions: Bag,
    }

    // Method Aliases

    public use fun destroy_executable as Executable.destroy;

    // === Public mutative functions ===

    // init and share a new Multisig object
    // creator is added by default with weight and threshold of 1
    public fun new(name: String, account_id: ID, ctx: &mut TxContext): Multisig {
        let mut members = vec_map::empty();
        members.insert(ctx.sender(), Member { weight: 1, account_id: option::some(account_id) });
        
        Multisig { 
            id: object::new(ctx),
            version: VERSION,
            name,
            threshold: 1,
            total_weight: 1,
            members,
            proposals: vec_map::empty(),
        }
    }

    // can be initialized by the creator before shared
    #[allow(lint(share_owned))]
    public fun share(multisig: Multisig) {
        transfer::share_object(multisig);
    }

    // === Multisig-only functions ===

    // create a new proposal for an action
    // that must be constructed in another module
    public fun create_proposal<Witness: drop>(
        multisig: &mut Multisig, 
        _: Witness, // module's witness
        key: String, // proposal key
        execution_time: u64, // timestamp in ms
        expiration_epoch: u64,
        description: String,
        ctx: &mut TxContext
    ): &mut Proposal {
        multisig.assert_is_member(ctx);
        multisig.assert_version();

        let proposal = Proposal { 
            id: object::new(ctx),
            module_witness: type_name::get<Witness>(),
            description,
            execution_time,
            expiration_epoch,
            actions: bag::new(ctx),
            approval_weight: 0,
            approved: vec_set::empty(), 
        };

        multisig.proposals.insert(key, proposal);
        multisig.proposals.get_mut(&key)
    }

    // push_back action to the proposal bag
    public fun push_action<A: store>(proposal: &mut Proposal, action: A) {
        let idx = proposal.actions.length();
        proposal.actions.add(idx, action);
    }

    // the signer agrees with the proposal
    public fun approve_proposal(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        multisig.assert_version();

        let proposal = multisig.proposals.get_mut(&key);
        proposal.approved.insert(ctx.sender()); // throws if already approved
        proposal.approval_weight = 
            proposal.approval_weight + multisig.members.get(&ctx.sender()).weight;
    }

    // the signer removes his agreement
    public fun remove_approval(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        multisig.assert_version();

        let proposal = multisig.proposals.get_mut(&key);
        proposal.approved.remove(&ctx.sender());
        proposal.approval_weight = 
            proposal.approval_weight - multisig.members.get(&ctx.sender()).weight;
    }

    // return an executable if the number of signers is >= threshold
    public fun execute_proposal(
        multisig: &mut Multisig, 
        key: String, 
        clock: &Clock,
        ctx: &mut TxContext
    ): Executable {
        multisig.assert_is_member(ctx);
        multisig.assert_version();

        let (_, proposal) = multisig.proposals.remove(&key);
        let Proposal { 
            id, 
            module_witness,
            description: _, 
            expiration_epoch: _, 
            execution_time,
            actions,
            approval_weight,
            approved: _,
        } = proposal;
        id.delete();

        assert!(approval_weight >= multisig.threshold, EThresholdNotReached);
        assert!(clock.timestamp_ms() >= execution_time, ECantBeExecutedYet);

        Executable { 
            multisig_addr: multisig.id.uid_to_inner().id_to_address(), 
            module_witness: module_witness,
            actions: actions
        }
    }

    public fun action_mut<Witness: drop, A: store>(
        executable: &mut Executable, 
        _: Witness,
        idx: u64
    ): &mut A {
        executable.actions.borrow_mut(idx)
    }

    // need to destroy all actions before destroying the executable
    public fun pop_action<Witness: drop, A: store>(
        executable: &mut Executable, 
        _: Witness
    ): A {
        assert!(executable.module_witness == type_name::get<Witness>(), ENotIssuerModule);
        let idx = executable.actions.length() - 1;
        executable.actions.remove(idx)
    }

    // to complete the execution

    public fun destroy_executable<Witness: drop>(
        executable: Executable, 
        _: Witness
    ) {
        let Executable { 
            multisig_addr: _, 
            module_witness, 
            actions 
        } = executable;
        assert!(module_witness == type_name::get<Witness>(), ENotIssuerModule);
        actions.destroy_empty();
    }

    // removes a proposal if it has expired
    public fun delete_proposal(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ): Bag {
        multisig.assert_version();
        let (_, proposal) = multisig.proposals.remove(&key);

        let Proposal { 
            id, 
            module_witness: _,
            expiration_epoch, 
            execution_time: _, 
            description: _, 
            actions,
            approval_weight: _,
            approved: _,
        } = proposal;

        id.delete();
        assert!(expiration_epoch <= ctx.epoch(), EHasntExpired);

        actions
    }

    // === View functions ===

    public fun assert_version(multisig: &Multisig) {
        assert!(multisig.version == VERSION, EWrongVersion);
    }

    public fun addr(multisig: &Multisig): address {
        multisig.id.uid_to_inner().id_to_address()
    }

    public fun name(multisig: &Multisig): String {
        multisig.name
    }

    public fun threshold(multisig: &Multisig): u64 {
        multisig.threshold
    }

    public fun total_weight(multisig: &Multisig): u64 {
        multisig.total_weight
    }

    public fun member_addresses(multisig: &Multisig): vector<address> {
        multisig.members.keys()
    }

    public fun member_weight(multisig: &Multisig, addr: address): u64 {
        let member = multisig.members.get(&addr);
        member.weight
    }
    
    public fun is_member(multisig: &Multisig, addr: address): bool {
        multisig.members.contains(&addr)
    }
    
    public fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
        assert!(multisig.members.contains(&ctx.sender()), ECallerIsNotMember);
    }

    public fun member_account_id(multisig: &Multisig, addr: address): Option<ID> {
        let member = multisig.members.get(&addr);
        member.account_id
    }

    public fun num_of_proposals(multisig: &Multisig): u64 {
        multisig.proposals.size()
    }

    public fun proposal(multisig: &Multisig, key: &String): &Proposal {
        multisig.proposals.get(key)
    }

    public fun description(proposal: &Proposal): String {
        proposal.description
    }

    public fun expiration_epoch(proposal: &Proposal): u64 {
        proposal.expiration_epoch
    }

    public fun execution_time(proposal: &Proposal): u64 {
        proposal.execution_time
    }

    public fun approved(proposal: &Proposal): vector<address> {
        proposal.approved.into_keys()
    }

    public use fun executable_multisig_addr as Executable.multisig_addr;
    public fun executable_multisig_addr(executable: &Executable): address {
        executable.multisig_addr
    }

    public use fun assert_multisig_executed as Multisig.assert_executed;
    public fun assert_multisig_executed(multisig: &Multisig, executable: &Executable) {
        assert!(multisig.addr() == executable.multisig_addr, ENotMultisigExecutable);
    }

    public use fun executable_last_action_idx as Executable.last_action_idx;
    public fun executable_last_action_idx(executable: &Executable): u64 {
        executable.actions.length() - 1
    }

    // === Package functions ===

    // callable only in config.move, if the proposal has been accepted
    public(package) fun set_version(multisig: &mut Multisig, version: u64) {
        multisig.version = version;
    }

    // callable only in config.move, if the proposal has been accepted
    public(package) fun set_name(multisig: &mut Multisig, name: String) {
        multisig.name = name;
    }

    // callable only in config.move, if the proposal has been accepted
    public(package) fun set_threshold(multisig: &mut Multisig, threshold: u64) {
        multisig.threshold = threshold;
    }

    // callable only in config.move, if the proposal has been accepted
    public(package) fun add_members(
        multisig: &mut Multisig, 
        mut addresses: vector<address>, 
        mut weights: vector<u64>
    ) {
        while (addresses.length() > 0) {
            let addr = addresses.pop_back();
            let weight = weights.pop_back();
            multisig.members.insert(
                addr, 
                Member { weight, account_id: option::none() }
            );
        }
    }

    // callable only in config.move, if the proposal has been accepted
    public(package) fun remove_members(multisig: &mut Multisig, mut addresses: vector<address>) {
        while (addresses.length() > 0) {
            let addr = addresses.pop_back();
            let (_, member) = multisig.members.remove(&addr);
            let Member { weight: _, account_id: _ } = member;
        }
    }

    // for adding account id to members, from account.move
    public(package) fun register_account_id(multisig: &mut Multisig, id: ID, ctx: &TxContext) {
        let member = multisig.members.get_mut(&ctx.sender());
        member.account_id.swap_or_fill(id);
    }

    // for removing account id from members, from account.move
    public(package) fun unregister_account_id(multisig: &mut Multisig, ctx: &TxContext): ID {
        let member = multisig.members.get_mut(&ctx.sender());
        member.account_id.extract()
    }

    public(package) fun uid_mut(multisig: &mut Multisig): &mut UID {
        &mut multisig.id
    }

    // === Test functions ===

    #[test_only]
    public fun assert_multisig_data_numbers(
        multisig: &Multisig,
        threshold: u64,
        members: u64,
        proposals: u64
    ) {
        assert!(multisig.threshold == threshold, 100);
        assert!(multisig.members.size() == members, 100);
        assert!(multisig.proposals.size() == proposals, 100);
    }
}

