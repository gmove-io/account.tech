/// This is the core module managing Multisig.
/// It provides the apis to create, approve and execute proposals with actions.
/// 
/// The flow is as follows:
///   1. A proposal is created by pushing actions into it. 
///      Actions are stacked from first to last, they must be executed then destroyed in the same order.
///   2. When the threshold is reached, a proposal can be executed. 
///      This returns an Executable hot potato constructed from certain fields of the approved Proposal. 
///      It is directly passed into action functions to enforce multisig approval for an action to be executed.
///   3. The module that created the proposal must destroy all of the actions and the Executable after execution 
///      by passing the same witness that was used for instanciation. 
///      This prevents the actions or the proposal to be stored instead of executed.

module kraken_multisig::multisig;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    clock::Clock, 
    dynamic_field as df,
    bag::Bag,
};
use kraken_multisig::{
    auth,
    deps::{Self, Deps},
    thresholds::{Self, Thresholds},
    members::{Self, Members, Member},
    proposals::{Self, Proposals, Proposal},
    executable::{Self, Executable},
};
use kraken_extensions::extensions::Extensions;

// === Errors ===

const ECantBeExecutedYet: u64 = 0;
const ECallerIsNotMember: u64 = 1;

// === Constants ===

const VERSION: u64 = 1;

// === Structs ===

/// Shared object 
public struct Multisig has key {
    id: UID,
    // human readable name to differentiate the multisigs
    name: String,
    // ids and versions of the packages this multisig is using
    // idx 0: kraken_multisig, idx 1: kraken_actions
    deps: Deps,
    // members of the multisig
    members: Members,
    // manage global threshold and role -> threshold
    thresholds: Thresholds,
    // open proposals, key should be a unique descriptive name
    proposals: Proposals,
}

// === Public mutative functions ===

/// Init and returns a new Multisig object
/// Creator is added by default with weight and global threshold of 1
public fun new(
    extensions: &Extensions,
    name: String, 
    account_id: ID, 
    ctx: &mut TxContext
): Multisig {
    let mut members = members::new();
    members.add(ctx.sender(), 1, option::some(account_id), vector[]);
    
    Multisig { 
        id: object::new(ctx),
        name,
        deps: deps::new(extensions),
        thresholds: thresholds::new(1),
        members,
        proposals: proposals::new(),
    }
}

/// Must be initialized by the creator before being shared
#[allow(lint(share_owned))]
public fun share(multisig: Multisig) {
    transfer::share_object(multisig);
}

// === Multisig-only functions ===

/// Creates a new proposal that must be constructed in another module
public fun create_proposal<W: drop>(
    multisig: &mut Multisig, 
    witness: W, // module's auth witness
    auth_name: String, // module's auth name
    key: String, // proposal key
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64, // epoch when we can delete the proposal
    ctx: &mut TxContext
): &mut Proposal {
    multisig.assert_is_member(ctx);
    let auth = auth::construct(witness, auth_name, multisig.addr());
    multisig.deps.assert_version(&auth, VERSION);

    let proposal = proposals::new_proposal(
        auth,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    multisig.proposals.add(proposal);
    // returns the proposal mutably for the caller to push actions into it
    multisig.proposals.get_mut(key)
}

/// Increases the global threshold and the role threshold if the signer has the one from the proposal
public fun approve_proposal(
    multisig: &mut Multisig, 
    key: String, 
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);

    let proposal = multisig.proposals.get_mut(key);
    // asserts that it uses the right KrakenMultisig package version
    multisig.deps.assert_version(proposal.auth(), VERSION);
    let member = multisig.members.get(ctx.sender()); 
    proposal.approve(member, ctx);
}

/// The signer removes his agreement
public fun remove_approval(
    multisig: &mut Multisig, 
    key: String, 
    ctx: &mut TxContext
) {
    let proposal = multisig.proposals.get_mut(key);
    multisig.deps.assert_version(proposal.auth(), VERSION);
    let member = multisig.members.get(ctx.sender()); 
    proposal.disapprove(member, ctx);
}

/// Returns an executable if the number of signers is >= (global || role) threshold
/// Anyone can execute a proposal, this allows to automate the execution of proposals
public fun execute_proposal(
    multisig: &mut Multisig, 
    key: String, 
    clock: &Clock,
): Executable {
    let proposal = multisig.proposals.get(key);
    assert!(clock.timestamp_ms() >= proposal.execution_time(), ECantBeExecutedYet);
    multisig.thresholds.assert_reached(proposal);

    let (auth, actions) = multisig.proposals.remove(key);
    multisig.deps.assert_version(&auth, VERSION);

    executable::new(auth, actions)
}

/// Removes a proposal if it has expired
/// Needs to delete each action in the bag within their own module
public fun delete_proposal(
    multisig: &mut Multisig, 
    key: String, 
    ctx: &mut TxContext
): Bag {
    let (auth, actions) = multisig.proposals.delete(key, ctx);
    multisig.deps.assert_version(&auth, VERSION);

    actions
}

// === View functions ===

public fun addr(multisig: &Multisig): address {
    multisig.id.uid_to_inner().id_to_address()
}

public fun name(multisig: &Multisig): String {
    multisig.name
}

public fun deps(multisig: &Multisig): &Deps {
    &multisig.deps
}

public fun members(multisig: &Multisig): &Members {
    &multisig.members
}

public fun member(multisig: &Multisig, addr: address): &Member {
    multisig.members.get(addr)
}

public fun thresholds(multisig: &Multisig): &Thresholds {
    &multisig.thresholds
}

public fun proposals(multisig: &Multisig): &Proposals {
    &multisig.proposals
}

public fun proposal(multisig: &Multisig, key: String): &Proposal {
    multisig.proposals.get(key)
}

public fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
    assert!(multisig.members.is_member(ctx.sender()), ECallerIsNotMember);
}

// === Deps-only functions ===

/// Managed assets:
/// Those are objects attached as dynamic fields to the multisig object

public fun add_managed_asset<K: copy + drop + store, A: store, W: copy + drop>(
    multisig: &mut Multisig, 
    witness: W,
    key: K, 
    asset: A,
) {
    multisig.deps.assert_dep(witness);
    df::add(&mut multisig.id, key, asset);
}

public fun borrow_managed_asset<K: copy + drop + store, A: store, W: copy + drop>(
    multisig: &Multisig, 
    witness: W,
    key: K, 
): &A {
    multisig.deps.assert_dep(witness);
    df::borrow(&multisig.id, key)
}

public fun borrow_managed_asset_mut<K: copy + drop + store, A: store, W: copy + drop>(
    multisig: &mut Multisig, 
    witness: W,
    key: K, 
): &mut A {
    multisig.deps.assert_dep(witness);
    df::borrow_mut(&mut multisig.id, key)
}

public fun remove_managed_asset<K: copy + drop + store, A: store, W: copy + drop>(
    multisig: &mut Multisig, 
    witness: W,
    key: K, 
): A {
    multisig.deps.assert_dep(witness);
    df::remove(&mut multisig.id, key)
}

public fun has_managed_asset<K: copy + drop + store>(
    multisig: &Multisig, 
    key: K, 
): bool {
    df::exists_(&multisig.id, key)
}

// === Core Deps only functions ===

/// Owned objects:
/// Those are objects owned by the multisig

public fun receive<T: key + store, W: copy + drop>(
    multisig: &mut Multisig, 
    witness: W,
    receiving: Receiving<T>,
): T {
    multisig.deps.assert_core_dep(witness);
    transfer::public_receive(&mut multisig.id, receiving)
}

/// Fields:
/// Those are the fields of the multisig object

public fun name_mut<W: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    witness: W,
): &mut String {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(witness);
    &mut multisig.name
}

public fun deps_mut<W: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    witness: W,
): &mut Deps {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(witness);
    &mut multisig.deps
}

public fun thresholds_mut<W: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    witness: W,
): &mut Thresholds {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(witness);
    &mut multisig.thresholds
}

public fun members_mut<W: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    witness: W,
): &mut Members {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(witness);
    &mut multisig.members
}

// === Package functions ===

/// Only accessible from account module
public(package) fun member_mut(
    multisig: &mut Multisig, 
    addr: address,
): &mut Member {
    multisig.members.get_mut(addr)
}

// === Test functions ===

#[test_only]
public fun deps_mut_for_testing(
    multisig: &mut Multisig, 
): &mut Deps {
    &mut multisig.deps
}

#[test_only]
public fun name_mut_for_testing(
    multisig: &mut Multisig, 
): &mut String {
    &mut multisig.name
}

#[test_only]
public fun thresholds_mut_for_testing(
    multisig: &mut Multisig, 
): &mut Thresholds {
    &mut multisig.thresholds
}

#[test_only]
public fun members_mut_for_testing(
    multisig: &mut Multisig, 
): &mut Members {
    &mut multisig.members
}

#[test_only]
public fun member_mut_for_testing(
    multisig: &mut Multisig, 
    addr: address,
): &mut Member {
    multisig.members.get_mut(addr)
}


