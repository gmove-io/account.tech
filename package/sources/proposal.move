module sui_multisig::proposal {
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

    public struct Multisig has key {
        id: UID,
        threshold: u64, // has to be <= members number
        members: VecSet<address>,
        proposals: VecMap<String, Proposal>, // key: String, value: Request
    }

    fun init(ctx: &mut TxContext) {
        let mut members = vec_set::empty();
        vec_set::insert(&mut members, tx_context::sender(ctx));

        transfer::share_object(
            Multisig { 
                id: object::new(ctx),
                threshold: 1,
                members,
                proposals: vec_map::empty(),
            }
        );
    }

    // === Public functions ===

    public fun clean_all(multisig: &mut Multisig, ctx: &mut TxContext) {
        let mut i = vec_map::size(&multisig.proposals);
        while (i > 0) {
            let (name, proposal) = vec_map::get_entry_by_idx(&multisig.proposals, i - 1);
            if (tx_context::epoch(ctx) - proposal.epoch >= 7) {
                let (_, proposal_obj) = vec_map::remove(&mut multisig.proposals, &*name);
                let Proposal { id, epoch: _, description: _, approved: _ } = proposal_obj;
                object::delete(id);
            };
            i = i - 1;
        } 
    }

    // === Multisig-only functions ===

    public fun create<T: store>(
        multisig: &mut Multisig, 
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

    public fun delete(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let (_, proposal_obj) = vec_map::remove(&mut multisig.proposals, &name);
        assert!(vec_set::size(&proposal_obj.approved) == 0, EProposalNotEmpty);
        
        let Proposal { id, epoch: _, description: _, approved: _ } = proposal_obj;
        object::delete(id);
    }

    public fun approve(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = vec_map::get_mut(&mut multisig.proposals, &name);
        vec_set::insert(&mut proposal.approved, tx_context::sender(ctx));
    }

    public fun remove_approval(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = vec_map::get_mut(&mut multisig.proposals, &name);
        vec_set::remove(&mut proposal.approved, &tx_context::sender(ctx));
    }

    public fun execute<T: store>(
        multisig: &mut Multisig, 
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

    fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
        assert!(
            vec_set::contains(&multisig.members, &tx_context::sender(ctx)), 
            ECallerIsNotMember
        );
    }

    // === Test functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }