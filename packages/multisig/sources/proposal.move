/// This is the core module managing Multisig and Proposals.
/// It provides the apis to create, approve and execute proposals with actions.
/// 
/// The flow is as follows:
///   1. A proposal is created by pushing actions into it. 
///      Actions are stacked from last to first, they must be executed then destroyed from last to first.
///   2. When the threshold is reached, a proposal can be executed. 
///      This returns an Executable hot potato constructed from certain fields of the approved Proposal. 
///      It is directly passed into action functions to enforce multisig approval for an action to be executed.
///   3. The module that created the proposal must destroy all of the actions and the Executable after execution 
///      by passing the same witness that was used for instanciation. 
///      This prevents the actions or the proposal to be stored instead of executed.

module kraken_multisig::proposal;

// === Imports ===

use std::string::String;
use sui::{
    vec_set::{Self, VecSet}, 
    bag::{Self, Bag},
};
use kraken_multisig::{
    auth::Auth,
    member::Member,
};

// === Errors ===

const EAlreadyApproved: u64 = 0;
const ENotApproved: u64 = 1;

// === Structs ===

// proposal owning a single action requested to be executed
// can be executed if length(approved) >= multisig.threshold
public struct Proposal has key, store {
    id: UID,
    // module that issued the proposal and must destroy it
    auth: Auth,
    // what this proposal aims to do, for informational purpose
    description: String,
    // the proposal can be deleted from this epoch
    expiration_epoch: u64,
    // proposer can add a timestamp_ms before which the proposal can't be executed
    // can be used to schedule actions via a backend
    execution_time: u64,
    // heterogenous array of actions to be executed from last to first
    actions: Bag,
    // total weight of all members that approved the proposal
    total_weight: u64,
    // sum of the weights of members who approved with the role
    role_weight: u64, 
    // who has approved the proposal
    approved: VecSet<address>,
}

// hot potato ensuring the action in the proposal is executed as it can't be stored
public struct Executable {
    // module that issued the proposal and must destroy it
    auth: Auth,
    // index of the next action to destroy, starts at 0
    next_to_destroy: u64,
    // actions to be executed in order
    actions: Bag,
}

// === Multisig-only functions ===

// create a new proposal for an action
// that must be constructed in another module
public(package) fun new(
    auth: Auth,
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
    ctx: &mut TxContext
): Proposal {
    Proposal { 
        id: object::new(ctx),
        auth,
        description,
        execution_time,
        expiration_epoch,
        actions: bag::new(ctx),
        total_weight: 0,
        role_weight: 0,
        approved: vec_set::empty(), 
    }
}

// insert action to the proposal bag, safe because proposal_mut is only accessible upon creation
public fun add_action<A: store>(proposal: &mut Proposal, action: A) {
    let idx = proposal.actions.length();
    proposal.actions.add(idx, action);
}

// increase the global threshold and the role threshold if the signer has one
public(package) fun approve(
    proposal: &mut Proposal, 
    member: &Member, 
    ctx: &mut TxContext
) {
    assert!(!proposal.has_approved(ctx.sender()), EAlreadyApproved);
    let role = proposal.auth().into_role();
    let has_role = member.has_role(&role);

    let weight = member.weight();
    proposal.approved.insert(ctx.sender()); // throws if already approved
    proposal.total_weight = proposal.total_weight + weight;
    if (has_role)
        proposal.role_weight = proposal.role_weight + weight;
}

// the signer removes his agreement
public(package) fun disapprove(
    proposal: &mut Proposal, 
    member: &Member, 
    ctx: &mut TxContext
) {
    assert!(proposal.has_approved(ctx.sender()), ENotApproved);
    let role = proposal.auth().into_role();
    let has_role = member.has_role(&role);

    let weight = member.weight();
    proposal.approved.remove(&ctx.sender()); // throws if already approved
    proposal.total_weight = proposal.total_weight - weight;
    if (has_role)
        proposal.role_weight = proposal.role_weight - weight;
}

public(package) fun destroy(proposal: Proposal): (Auth, Bag) {
    let Proposal { 
        id, 
        auth,
        actions,
        ..
    } = proposal;
    id.delete();

    (auth, actions)
}

// === View functions ===

public fun auth(proposal: &Proposal): &Auth {
    &proposal.auth
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

public fun actions_length(proposal: &Proposal): u64 {
    proposal.actions.length()
}

public fun total_weight(proposal: &Proposal): u64 {
    proposal.total_weight
}

public fun role_weight(proposal: &Proposal): u64 {
    proposal.role_weight
}

public fun approved(proposal: &Proposal): vector<address> {
    proposal.approved.into_keys()
}

public fun has_approved(proposal: &Proposal, addr: address): bool {
    proposal.approved.contains(&addr)
}
