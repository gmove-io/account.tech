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

    // shared object accessible within the module where it has been instatiated
    public struct Multisig has key {
        id: UID,
        // proposals can be executed is len(approved) >= threshold
        // has to be always <= length(members)
        threshold: u64,
        // multisig cap to authorize actions for a package
        // members of the multisig
        members: VecSet<address>,
        // open proposals, key should be a unique descriptive name
        proposals: VecMap<String, Proposal>,
    }

    // proposal owning a single action requested to be executed
    public struct Proposal has key, store {
        id: UID,
        // proposals can be deleted from this epoch
        expiration: u64,
        // what this proposal aims to do, for informational purpose
        description: String,
        // who has approved the proposal
        approved: VecSet<address>,
    }

    public struct ProposalKey has copy, drop, store {}

    // === Public functions ===

    // init a new Multisig shared object
    public fun new(ctx: &mut TxContext) {
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

    public fun clean_proposals(multisig: &mut Multisig, ctx: &mut TxContext) {
        let mut i = vec_map::size(&multisig.proposals);
        while (i > 0) {
            let (name, proposal) = vec_map::get_entry_by_idx(&multisig.proposals, i - 1);
            if (tx_context::epoch(ctx) >= proposal.expiration) {
                let (_, proposal) = vec_map::remove(&mut multisig.proposals, &*name);
                let Proposal { id, expiration: _, description: _, approved: _ } = proposal;
                object::delete(id);
            };
            i = i - 1;
        } 
    }

    // === Multisig-only functions ===

    // create a new proposal using an inner proposal type
    // that must be constructed from a friend module
    public fun create_proposal<T: store>(
        multisig: &mut Multisig, 
        inner: T,
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

        df::add(&mut proposal.id, ProposalKey {}, inner);

        vec_map::insert(&mut multisig.proposals, name, proposal);
    }

    // remove a proposal that hasn't been approved yet
    // to prevent malicious members to delete proposals that are still open
    public fun delete_proposal(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let (_, proposal) = vec_map::remove(&mut multisig.proposals, &name);
        assert!(vec_set::size(&proposal.approved) == 0, EProposalNotEmpty);
        
        let Proposal { id, expiration: _, description: _, approved: _ } = proposal;
        object::delete(id);
    }

    // the signer agrees to the proposal
    public fun approve_proposal(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = vec_map::get_mut(&mut multisig.proposals, &name);
        vec_set::insert(&mut proposal.approved, tx_context::sender(ctx));
    }

    // the signer removes his agreement
    public fun remove_approval(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = vec_map::get_mut(&mut multisig.proposals, &name);
        vec_set::remove(&mut proposal.approved, &tx_context::sender(ctx));
    }

    // return the inner proposal if the number of signers is >= threshold
    public fun execute_proposal<T: store>(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ): T {
        assert_is_member(multisig, ctx);

        let (_, proposal) = vec_map::remove(&mut multisig.proposals, &name);
        assert!(vec_set::size(&proposal.approved) >= multisig.threshold, EThresholdNotReached);

        let Proposal { mut id, expiration: _, description:_, approved: _ } = proposal;
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
}