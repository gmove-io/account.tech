/// This is the core module managing Multisig and Proposals.
/// Various actions to be executed by the Multisig can be attached to a Proposal.
/// The proposals have to be approved by at least the threshold number of members.

module kraken::multisig {
    use std::string::String;
    use std::type_name::{Self, TypeName};
    use sui::clock::Clock;
    use sui::dynamic_field as df;
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};

    // === Errors ===

    const ECallerIsNotMember: u64 = 0;
    const EThresholdNotReached: u64 = 1;
    const EProposalNotEmpty: u64 = 2;
    const ECantBeExecutedYet: u64 = 3;
    const ENotIssuerModule: u64 = 4;

    // === Structs ===

    // shared object 
    public struct Multisig has key {
        id: UID,
        // human readable name to differentiate the multisigs
        name: String,
        // has to be always <= length(members)
        threshold: u64,
        // members of the multisig
        members: VecSet<address>,
        // open proposals, key should be a unique descriptive name
        proposals: VecMap<String, Proposal>,
    }

    // proposal owning a single action requested to be executed
    // can be executed if length(approved) >= multisig.threshold
    public struct Proposal has key, store {
        id: UID,
        // what this proposal aims to do, for informational purpose
        description: String,
        // the proposal can be deleted from this epoch
        expiration_epoch: u64,
        // proposer can add a timestamp_ms before which the proposal can't be executed
        // can be used to schedule actions via a backend
        execution_time: u64,
        // who has approved the proposal
        approved: VecSet<address>,
        // module that issued the proposal and must destroy it
        issuer: TypeName,
    }

    // key for the inner action struct of a proposal
    public struct ActionKey has copy, drop, store {}
    // key for the associated access action 
    public struct AccessKey has copy, drop, store {}

    // hot potato ensuring the action in the proposal is executed as it can't be stored
    public struct Executable {
        multisig_addr: address,
        proposal: Proposal,
    }

    // === Public mutative functions ===

    // init and share a new Multisig object
    public fun new(name: String, ctx: &mut TxContext): Multisig {
        Multisig { 
            id: object::new(ctx),
            name,
            threshold: 1,
            members: vec_set::singleton(ctx.sender()),
            proposals: vec_map::empty(),
        }
    }

    #[allow(lint(share_owned))]
    public fun share(multisig: Multisig) {
        transfer::share_object(multisig);
    }

    // anyone can clean expired proposals
    public fun clean_proposals(multisig: &mut Multisig, ctx: &mut TxContext) {
        let mut i = multisig.proposals.size();
        while (i > 0) {
            let (key, proposal) = multisig.proposals.get_entry_by_idx(i - 1);
            if (ctx.epoch() >= proposal.expiration_epoch) {
                let (_, proposal) = multisig.proposals.remove(&*key);
                let Proposal { 
                    id, 
                    description: _, 
                    expiration_epoch: _, 
                    execution_time: _, 
                    approved: _,
                    issuer: _
                } = proposal;
                id.delete();
            };
            i = i - 1;
        } 
    }

    // === Multisig-only functions ===

    // create a new proposal for an action
    // that must be constructed in another module
    public fun create_proposal<Issuer: drop>(
        multisig: &mut Multisig, 
        _: Issuer, // module's witness
        key: String, // proposal key
        execution_time: u64, // timestamp in ms
        expiration_epoch: u64,
        description: String,
        ctx: &mut TxContext
    ): &mut Proposal {
        assert_is_member(multisig, ctx);

        let mut proposal = Proposal { 
            id: object::new(ctx),
            description,
            execution_time,
            expiration_epoch,
            approved: vec_set::empty(), 
            issuer: type_name::get<Issuer>(),
        };

        multisig.proposals.insert(key, proposal);
        multisig.proposals.get_mut(&key)
    }

    public fun add_action<A: store>(proposal: &mut Proposal, action: A) {
        df::add(&mut proposal.id, ActionKey {}, action);
    }

    public fun add_access<Access: store>(proposal: &mut Proposal, access: Access) {
        df::add(&mut proposal.id, AccessKey {}, access);
    }

    // remove a proposal that hasn't been approved yet
    // prevents malicious members to delete proposals that are still open
    public fun delete_proposal(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let (_, proposal) = multisig.proposals.remove(&key);
        assert!(proposal.approved.size() == 0, EProposalNotEmpty);
        
        let Proposal { 
            id, 
            expiration_epoch: _, 
            execution_time: _, 
            description: _, 
            approved: _,
            issuer: _
        } = proposal;
        id.delete();
    }

    // the signer agrees with the proposal
    public fun approve_proposal(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = multisig.proposals.get_mut(&key);
        proposal.approved.insert(ctx.sender()); // throws if already approved
    }

    // the signer removes his agreement
    public fun remove_approval(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = multisig.proposals.get_mut(&key);
        proposal.approved.remove(&ctx.sender());
    }

    // return the action if the number of signers is >= threshold
    public fun execute_proposal(
        multisig: &mut Multisig, 
        key: String, 
        clock: &Clock,
        ctx: &mut TxContext
    ): Executable {
        assert_is_member(multisig, ctx);

        let (_, proposal) = multisig.proposals.remove(&key);
        assert!(proposal.approved.size() >= multisig.threshold, EThresholdNotReached);
        assert!(clock.timestamp_ms() >= proposal.execution_time, ECantBeExecutedYet);

        Executable { multisig_addr: multisig.id.uid_to_inner().id_to_address(), proposal }
    }

    public fun action_mut<A: store>(executable: &mut Executable): &mut A {
        df::borrow_mut(&mut executable.proposal.id, ActionKey {})
    }

    public fun access_mut<Access: store>(executable: &mut Executable): &mut Access {
        df::borrow_mut(&mut executable.proposal.id, AccessKey {})
    }

    public fun destroy_proposal<Issuer: drop, A: store, Access: store>(
        executable: Executable, 
        _: Issuer
    ): (A, Access) {
        let Executable { multisig_addr: _, proposal } = executable;
        let Proposal { 
            id, 
            description: _, 
            expiration_epoch: _, 
            execution_time: _, 
            approved: _,
            issuer
        } = proposal;
        assert!(issuer == type_name::get<Issuer>(), ENotIssuerModule);
        
        let action = df::remove(&mut id, ActionKey {});
        let access = df::remove(&mut id, AccessKey {});
        id.delete();

        (action, access)
    }

    // === View functions ===

    public fun name(multisig: &Multisig): String {
        multisig.name
    }

    public fun threshold(multisig: &Multisig): u64 {
        multisig.threshold
    }

    public fun members(multisig: &Multisig): vector<address> {
        multisig.members.into_keys()
    }

    public fun addr(multisig: &Multisig): address {
        multisig.id.uid_to_inner().id_to_address()
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

    public fun executable_multisig_addr(executable: &Executable): address {
        executable.multisig_addr
    }

    // === Package functions ===

    // callable only in management.move, if the proposal has been accepted
    public(package) fun set_name(multisig: &mut Multisig, name: String) {
        multisig.name = name;
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun set_threshold(multisig: &mut Multisig, threshold: u64) {
        multisig.threshold = threshold;
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun add_members(multisig: &mut Multisig, mut addresses: vector<address>) {
        while (addresses.length() > 0) {
            let addr = addresses.pop_back();
            multisig.members.insert(addr);
        }
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun remove_members(multisig: &mut Multisig, mut addresses: vector<address>) {
        while (addresses.length() > 0) {
            let addr = addresses.pop_back();
            multisig.members.remove(&addr);
        }
    }

    public(package) fun uid_mut(multisig: &mut Multisig): &mut UID {
        &mut multisig.id
    }

    public(package) fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
        assert!(multisig.members.contains(&ctx.sender()), ECallerIsNotMember);
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

