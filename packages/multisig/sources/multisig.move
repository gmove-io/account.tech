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

module kraken_multisig::multisig;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    clock::Clock, 
    vec_map::{Self, VecMap}, 
    dynamic_field as df,
};
use kraken_multisig::{
    auth,
    deps::{Self, Deps},
    thresholds::{Self, Thresholds},
    members::{Self, Members, Member},
    proposal::{Self, Proposal},
    executable::{Self, Executable},
};

// === Errors ===

const ECallerIsNotMember: u64 = 0;
const ECantBeExecutedYet: u64 = 2;
const EHasntExpired: u64 = 3;
const EMemberNotFound: u64 = 4;
const EProposalNotFound: u64 = 5;

// === Constants ===

const VERSION: u64 = 1;

// === Structs ===

// shared object 
public struct Multisig has key {
    id: UID,
    // ids and versions of the packages this multisig is using
    // idx 0: kraken_multisig, idx 1: kraken_actions
    deps: Deps,
    // human readable name to differentiate the multisigs
    name: String,
    // members of the multisig
    members: Members,
    // manage global threshold and role -> threshold
    thresholds: Thresholds,
    // open proposals, key should be a unique descriptive name
    proposals: VecMap<String, Proposal>,
}

// === Public mutative functions ===

// init and share a new Multisig object
// creator is added by default with weight and threshold of 1
public fun new(
    name: String, 
    account_id: ID, 
    dep_packages: vector<address>,
    dep_versions: vector<u64>,
    dep_names: vector<String>,
    ctx: &mut TxContext
): Multisig {
    let mut members = members::new();
    members.add(members::new_member(ctx.sender(), 1, option::some(account_id), vector[]));
    
    Multisig { 
        id: object::new(ctx),
        deps: deps::from_vecs(dep_packages, dep_versions, dep_names),
        name,
        thresholds: thresholds::new(1),
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
public fun create_proposal<I: drop>(
    multisig: &mut Multisig, 
    issuer: I, // module's auth issuer
    auth_name: String, // module's auth name
    key: String, // proposal key
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
    ctx: &mut TxContext
): &mut Proposal {
    multisig.assert_is_member(ctx);
    let auth = auth::construct(issuer, auth_name, multisig.addr());
    multisig.deps.assert_version(&auth, VERSION);

    let proposal = proposal::new(
        auth,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    multisig.proposals.insert(key, proposal);
    multisig.proposals.get_mut(&key)
}

// increase the global threshold and the role threshold if the signer has one
public fun approve_proposal(
    multisig: &mut Multisig, 
    key: String, 
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    assert!(multisig.proposals.contains(&key), EProposalNotFound);

    let proposal = multisig.proposals.get_mut(&key);
    multisig.deps.assert_version(proposal.auth(), VERSION);
    let member = multisig.members.get(ctx.sender()); 
    proposal.approve(member, ctx);
}

// the signer removes his agreement
public fun remove_approval(
    multisig: &mut Multisig, 
    key: String, 
    ctx: &mut TxContext
) {
    assert!(multisig.proposals.contains(&key), EProposalNotFound);

    let proposal = multisig.proposals.get_mut(&key);
    multisig.deps.assert_version(proposal.auth(), VERSION);
    let member = multisig.members.get(ctx.sender()); 
    proposal.disapprove(member, ctx);
}

// return an executable if the number of signers is >= threshold
public fun execute_proposal(
    multisig: &mut Multisig, 
    key: String, 
    clock: &Clock,
): Executable {
    // multisig.assert_is_member(ctx); remove to be able to automate it

    let (_, proposal) = multisig.proposals.remove(&key);
    assert!(clock.timestamp_ms() >= proposal.execution_time(), ECantBeExecutedYet);
    multisig.thresholds.assert_reached(&proposal);

    let (auth, actions) = proposal.destroy();
    multisig.deps.assert_version(&auth, VERSION);

    executable::new(auth, actions)
}

// TODO: manage actions in bag (drop?)
// removes a proposal if it has expired
// public fun delete_proposal(
//     multisig: &mut Multisig, 
//     key: String, 
//     ctx: &mut TxContext
// ): Bag {
//     let (_, proposal) = multisig.proposals.remove(&key);
//     assert!(proposal.expiration_epoch() <= ctx.epoch(), EHasntExpired);
//     let (auth, actions) = proposal.destroy();
//     multisig.deps.assert_version(&auth, VERSION);

//     actions
// }

// === View functions ===

public fun addr(multisig: &Multisig): address {
    multisig.id.uid_to_inner().id_to_address()
}

public fun deps(multisig: &Multisig): &Deps {
    &multisig.deps
}

public fun name(multisig: &Multisig): String {
    multisig.name
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

public fun proposal(multisig: &Multisig, key: &String): &Proposal {
    multisig.proposals.get(key)
}

public fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
    assert!(multisig.members.is_member(ctx.sender()), ECallerIsNotMember);
}

public fun get_weights_for_roles(multisig: &Multisig): VecMap<String, u64> {
    let mut members_weights_map: VecMap<address, u64> = vec_map::empty();
    multisig.members.addresses().do!(|addr| {
        members_weights_map.insert(addr, multisig.member(addr).weight());
    });
    
    let mut roles_weights_map: VecMap<String, u64> = vec_map::empty();
    multisig.members.addresses().do!(|addr| {
        let weight = members_weights_map[&addr];
        multisig.member(addr).roles().do!(|role| {
            if (roles_weights_map.contains(&role)) {
                roles_weights_map.insert(role, weight);
            } else {
                *roles_weights_map.get_mut(&role) = weight;
            }
        });
    });

    roles_weights_map
}

// === Deps-only functions ===

// owned objects
public fun receive<T: key + store, I: copy + drop>(
    multisig: &mut Multisig, 
    issuer: I,
    receiving: Receiving<T>,
): T {
    multisig.deps.assert_core_dep(issuer);
    transfer::public_receive(&mut multisig.id, receiving)
}

// managed assets
public fun add_managed_asset<K: copy + drop + store, A: store, I: copy + drop>(
    multisig: &mut Multisig, 
    issuer: I,
    key: K, 
    asset: A,
) {
    multisig.deps.assert_core_dep(issuer);
    df::add(&mut multisig.id, key, asset);
}

public fun has_managed_asset<K: copy + drop + store>(
    multisig: &Multisig, 
    key: K, 
): bool {
    df::exists_(&multisig.id, key)
}

public fun borrow_managed_asset<K: copy + drop + store, A: store, I: copy + drop>(
    multisig: &Multisig, 
    issuer: I,
    key: K, 
): &A {
    multisig.deps.assert_core_dep(issuer);
    df::borrow(&multisig.id, key)
}

public fun borrow_managed_asset_mut<K: copy + drop + store, A: store, I: copy + drop>(
    multisig: &mut Multisig, 
    issuer: I,
    key: K, 
): &mut A {
    multisig.deps.assert_core_dep(issuer);
    df::borrow_mut(&mut multisig.id, key)
}

public fun remove_managed_asset<K: copy + drop + store, A: store, I: copy + drop>(
    multisig: &mut Multisig, 
    issuer: I,
    key: K, 
): A {
    multisig.deps.assert_core_dep(issuer);
    df::remove(&mut multisig.id, key)
}

// fields
public fun deps_mut<I: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    issuer: I,
): &mut Deps {
    executable.auth().assert_is_issuer(issuer);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(issuer);
    &mut multisig.deps
}

public fun name_mut<I: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    issuer: I,
): &mut String {
    executable.auth().assert_is_issuer(issuer);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(issuer);
    &mut multisig.name
}

public fun thresholds_mut<I: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    issuer: I,
): &mut Thresholds {
    executable.auth().assert_is_issuer(issuer);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(issuer);
    &mut multisig.thresholds
}

public fun members_mut<I: copy + drop>(
    multisig: &mut Multisig, 
    executable: &Executable,
    issuer: I,
): &mut Members {
    executable.auth().assert_is_issuer(issuer);
    executable.auth().assert_is_multisig(multisig.addr());
    multisig.deps.assert_core_dep(issuer);
    &mut multisig.members
}

// === Package functions ===

// only accessible from account module
public(package) fun member_mut(
    multisig: &mut Multisig, 
    addr: address,
): &mut Member {
    multisig.members.get_mut(addr)
}

// === Test functions ===

#[test_only]
public fun proposals_length(multisig: &Multisig): u64 {
    multisig.proposals.size()
}

