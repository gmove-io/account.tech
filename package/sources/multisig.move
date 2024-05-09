/// This is the core module managing Multisig and Proposals.
/// Various actions to be executed by the Multisig can be attached to a Proposal.
/// The proposals have to be approved by at least the threshold number of members.

module sui_multisig::multisig {
    use std::string::String;
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_field as df;

    // === Errors ===

    const ECallerIsNotMember: u64 = 0;
    const EThresholdNotReached: u64 = 1;
    const EProposalNotEmpty: u64 = 2;

    // === Structs ===

    // shared object 
    public struct Multisig has key {
        id: UID,
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
        // proposals can be deleted from this epoch
        expiration: u64,
        // what this proposal aims to do, for informational purpose
        description: String,
        // who has approved the proposal
        approved: VecSet<address>,
    }

    // key for the inner action struct of a proposal
    public struct ActionKey has copy, drop, store {}

    // === Public mutative functions ===

    // init and share a new Multisig object
    public fun new(ctx: &mut TxContext) {
        let mut members = vec_set::empty();
        members.insert(tx_context::sender(ctx));

        transfer::share_object(
            Multisig { 
                id: object::new(ctx),
                threshold: 1,
                members,
                proposals: vec_map::empty(),
            }
        );
    }

    // anyone can clean expired proposals
    public fun clean_proposals(multisig: &mut Multisig, ctx: &mut TxContext) {
        let mut i = multisig.proposals.size();
        while (i > 0) {
            let (name, proposal) = multisig.proposals.get_entry_by_idx(i - 1);
            if (ctx.epoch() >= proposal.expiration) {
                let (_, proposal) = multisig.proposals.remove(&*name);
                let Proposal { id, expiration: _, description: _, approved: _ } = proposal;
                id.delete();
            };
            i = i - 1;
        } 
    }

    // === Public views ===

    public fun members(multisig: &Multisig): vector<address> {
        multisig.members.into_keys()
    }

    public fun member_exists(multisig: &Multisig, address: &address): bool {
        multisig.members.contains(address)
    }

    // === Multisig-only functions ===

    // create a new proposal for an action
    // that must be constructed in another module
    public fun create_proposal<T: store>(
        multisig: &mut Multisig, 
        action: T,
        name: String, 
        expiration: u64,
        description: String,
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let mut proposal = Proposal { 
            id: object::new(ctx),
            expiration,
            description,
            approved: vec_set::empty(), 
        };

        df::add(&mut proposal.id, ActionKey {}, action);

        multisig.proposals.insert(name, proposal);
    }

    // remove a proposal that hasn't been approved yet
    // prevents malicious members to delete proposals that are still open
    public fun delete_proposal(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let (_, proposal) = multisig.proposals.remove(&name);
        assert!(proposal.approved.size() == 0, EProposalNotEmpty);
        
        let Proposal { id, expiration: _, description: _, approved: _ } = proposal;
        id.delete();
    }

    // the signer agrees with the proposal
    public fun approve_proposal(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = multisig.proposals.get_mut(&name);
        proposal.approved.insert(ctx.sender()); // throws if already approved
    }

    // the signer removes his agreement
    public fun remove_approval(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = multisig.proposals.get_mut(&name);
        proposal.approved.remove(&ctx.sender());
    }

    // return the action if the number of signers is >= threshold
    public fun execute_proposal<T: store>(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ): T {
        assert_is_member(multisig, ctx);

        let (_, proposal) = multisig.proposals.remove(&name);
        assert_threshold_reached(multisig, &proposal);

        let Proposal { mut id, expiration: _, description:_, approved: _ } = proposal;
        let action = df::remove(&mut id, ActionKey {});
        id.delete();

        action
    }

    // === Package functions ===

    public(package) fun uid_mut(multisig: &mut Multisig): &mut UID {
        &mut multisig.id
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun set_threshold(multisig: &mut Multisig, threshold: u64) {
        multisig.threshold = threshold;
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun add_members(multisig: &mut Multisig, mut addresses: vector<address>) {
        while (addresses.length() > 0) {
            let addr = vector::pop_back(&mut addresses);
            vec_set::insert(&mut multisig.members, addr);
        }
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun remove_members(multisig: &mut Multisig, mut addresses: vector<address>) {
        while (addresses.length() > 0) {
            let addr = vector::pop_back(&mut addresses);
            vec_set::remove(&mut multisig.members, &addr);
        }
    }

    // === Private functions ===

    fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
        assert!(multisig.members.contains(&ctx.sender()), ECallerIsNotMember);
    }

    fun assert_threshold_reached(multisig: &Multisig, proposal: &Proposal) {
        assert!(proposal.approved.size() >= multisig.threshold, EThresholdNotReached);
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

