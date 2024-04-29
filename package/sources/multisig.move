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

    public struct ProposalKey has copy, drop, store {}

    public struct Proposal has key, store {
        id: UID,
        // proposals can be deleted after 7d
        epoch: u64,
        // what this proposal aims to do, for informational purpose
        description: String,
        // who has approved the proposal
        approved: VecSet<address>,
    }

    // shared object accessible within the module where it has been instatiated
    public struct Multisig<phantom W> has key {
        id: UID,
        // after how many epochs proposals expire
        expiration: u64,
        // proposals can be executed is len(approved) >= threshold
        // has to be always <= length(members)
        threshold: u64,
        // members of the multisig
        members: VecSet<address>,
        // open proposals, key should be a unique descriptive name
        proposals: VecMap<String, Proposal>,
    }

    // === Public functions ===

    // init a new Multisig shared object
    public fun new<W: drop>(_: W, expiration: u64, ctx: &mut TxContext) {
        let mut members = vec_set::empty();
        vec_set::insert(&mut members, tx_context::sender(ctx));

        transfer::share_object(
            Multisig<W> { 
                id: object::new(ctx),
                expiration,
                threshold: 1,
                members,
                proposals: vec_map::empty(),
            }
        );
    }

    public fun clean_proposals<W: drop>(multisig: &mut Multisig<W>, ctx: &mut TxContext) {
        let mut i = vec_map::size(&multisig.proposals);
        while (i > 0) {
            let (name, proposal) = vec_map::get_entry_by_idx(&multisig.proposals, i - 1);
            if (tx_context::epoch(ctx) - proposal.epoch >= multisig.expiration) {
                let (_, proposal_obj) = vec_map::remove(&mut multisig.proposals, &*name);
                let Proposal { id, epoch: _, description: _, approved: _ } = proposal_obj;
                object::delete(id);
            };
            i = i - 1;
        } 
    }

    // === Multisig-only functions ===

    // create a new proposal using an inner proposal type
    // that must be constructed from a friend module
    public fun create_proposal<W: drop, T: store>(
        multisig: &mut Multisig<W>, 
        inner: T,
        name: String, 
        description: String,
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let mut proposal = Proposal { 
            id: object::new(ctx),
            epoch: tx_context::epoch(ctx), 
            description,
            approved: vec_set::empty(), 
        };

        df::add(&mut proposal.id, ProposalKey {}, inner);

        vec_map::insert(&mut multisig.proposals, name, proposal);
    }

    // remove a proposal that hasn't been approved yet
    // to prevent malicious members to delete proposals that are still open
    public fun delete_proposal<W: drop>(
        multisig: &mut Multisig<W>, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let (_, proposal) = vec_map::remove(&mut multisig.proposals, &name);
        assert!(vec_set::size(&proposal.approved) == 0, EProposalNotEmpty);
        
        let Proposal { id, epoch: _, description: _, approved: _ } = proposal;
        object::delete(id);
    }

    // the signer agrees to the proposal
    public fun approve_proposal<W: drop>(
        multisig: &mut Multisig<W>, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = vec_map::get_mut(&mut multisig.proposals, &name);
        vec_set::insert(&mut proposal.approved, tx_context::sender(ctx));
    }

    // the signer removes his agreement
    public fun remove_approval<W: drop>(
        multisig: &mut Multisig<W>, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = vec_map::get_mut(&mut multisig.proposals, &name);
        vec_set::remove(&mut proposal.approved, &tx_context::sender(ctx));
    }

    // return the inner proposal if the number of signers is >= threshold
    public fun execute_proposal<W: drop, T: store>(
        multisig: &mut Multisig<W>, 
        name: String, 
        ctx: &mut TxContext
    ): T {
        assert_is_member(multisig, ctx);

        let (_, proposal) = vec_map::remove(&mut multisig.proposals, &name);
        assert!(vec_set::size(&proposal.approved) >= multisig.threshold, EThresholdNotReached);

        let Proposal { mut id, epoch: _, description:_, approved: _ } = proposal;
        let inner = df::remove(&mut id, ProposalKey {});
        object::delete(id);

        inner
    }

    // === Private functions ===

    fun assert_is_member<W: drop>(multisig: &Multisig<W>, ctx: &TxContext) {
        assert!(
            vec_set::contains(&multisig.members, &tx_context::sender(ctx)), 
            ECallerIsNotMember
        );
    }
}