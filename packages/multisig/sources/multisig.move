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
    utils,
    auth,
    deps::{Self, Deps},
    member::{Self, Member},
    proposal::{Self, Proposal},
    executable::{Self, Executable},
};

// === Aliases ===

use fun utils::map_set_or as VecMap.set_or;

// === Errors ===

const ECallerIsNotMember: u64 = 0;
const EThresholdNotReached: u64 = 1;
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
    // versions of the packages this multisig is using
    // idx 0: kraken_multisig, idx 1: kraken_actions
    deps: Deps,
    // human readable name to differentiate the multisigs
    name: String,
    // role -> threshold, no role is "global" (index == 0)
    thresholds: VecMap<String, u64>,
    // members of the multisig
    members: VecMap<address, Member>,
    // open proposals, key should be a unique descriptive name
    proposals: VecMap<String, Proposal>,
}

// === Public mutative functions ===

// init and share a new Multisig object
// creator is added by default with weight and threshold of 1
public fun new(
    name: String, 
    account_id: ID, 
    dep_packages: vector<String>,
    dep_versions: vector<u64>,
    ctx: &mut TxContext
): Multisig {
    let members = vec_map::from_keys_values(
        vector[ctx.sender()], 
        vector[member::new(1, option::some(account_id), vector[b"global".to_string()])]
    );      
    
    Multisig { 
        id: object::new(ctx),
        deps: deps::from_keys_values(dep_packages, dep_versions),
        name,
        thresholds: vec_map::from_keys_values(vector[b"global".to_string()], vector[1]),
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
    auth_issuer: I, // module's auth issuer
    auth_name: String, // module's auth name
    key: String, // proposal key
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
    ctx: &mut TxContext
): &mut Proposal {
    multisig.assert_is_member(ctx);
    let auth = auth::construct(auth_issuer, auth_name, multisig.addr());
    auth.assert_version(&multisig.deps, VERSION);

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
    proposal.auth().assert_version(&multisig.deps, VERSION);
    let member = multisig.member(&ctx.sender()); // protected - enforce being member
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
    proposal.auth().assert_version(&multisig.deps, VERSION);
    let member = multisig.member(&ctx.sender()); // protected - enforce being member
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

    let (auth, actions) = proposal.destroy();
    let role = auth.into_role();
    auth.assert_version(&multisig.deps, VERSION);
    assert!(
        proposal.total_weight() >= multisig.threshold(b"global".to_string()) ||
        proposal.role_weight() >= multisig.threshold(role), 
        EThresholdNotReached
    );

    executable::new(auth, actions)
}

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

public fun thresholds(multisig: &Multisig): VecMap<String, u64> {
    multisig.thresholds
}

public fun threshold(multisig: &Multisig, role: String): u64 {
    *multisig.thresholds.get(&role)
}

public fun get_weights_for_roles(multisig: &Multisig): VecMap<String, u64> {
    let mut members_weights_map: VecMap<address, u64> = vec_map::empty();
    multisig.member_addresses().do!(|addr| {
        members_weights_map.insert(addr, multisig.member(&addr).weight());
    });
    
    let mut roles_weights_map: VecMap<String, u64> = vec_map::empty();
    multisig.member_addresses().do!(|addr| {
        let weight = members_weights_map[&addr];
        multisig.member(&addr).roles().do!(|role| {
            roles_weights_map.set_or!(role, weight, |current| {
                *current = *current + weight;
            });
        });
    });

    roles_weights_map
}

public fun member_addresses(multisig: &Multisig): vector<address> {
    multisig.members.keys()
}

public fun is_member(multisig: &Multisig, addr: &address): bool {
    multisig.members.contains(addr)
}

public fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
    assert!(multisig.members.contains(&ctx.sender()), ECallerIsNotMember);
}

public fun member(multisig: &Multisig, addr: &address): &Member {
    multisig.members.get(addr)
}

// the caller must be member to return a reference to his Member
public fun member_mut(multisig: &mut Multisig, ctx: &TxContext): &mut Member {
    let addr = ctx.sender();
    assert!(multisig.members.contains(&addr), EMemberNotFound);
    multisig.members.get_mut(&addr)
}

public fun proposal(multisig: &Multisig, key: &String): &Proposal {
    multisig.proposals.get(key)
}

// === Deps-only functions ===

// owned objects
public fun receive<T: key + store, I: copy + drop>(
    multisig: &mut Multisig, 
    receiving: Receiving<T>,
    issuer: I,
): T {
    multisig.deps.assert_core_dep(issuer);
    transfer::public_receive(&mut multisig.id, receiving)
}

// managed assets
public fun add_managed_asset<K: copy + drop + store, A: store, I: copy + drop>(
    multisig: &mut Multisig, 
    key: K, 
    asset: A,
    issuer: I,
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
    key: K, 
    issuer: I,
): &A {
    multisig.deps.assert_core_dep(issuer);
    df::borrow(&multisig.id, key)
}

public fun borrow_managed_asset_mut<K: copy + drop + store, A: store, I: copy + drop>(
    multisig: &mut Multisig, 
    key: K, 
    issuer: I,
): &mut A {
    multisig.deps.assert_core_dep(issuer);
    df::borrow_mut(&mut multisig.id, key)
}

public fun remove_managed_asset<K: copy + drop + store, A: store, I: copy + drop>(
    multisig: &mut Multisig, 
    key: K, 
    issuer: I,
): A {
    multisig.deps.assert_core_dep(issuer);
    df::remove(&mut multisig.id, key)
}

// callable only in config.move, if the proposal has been accepted
public fun set_name<I: copy + drop>(
    multisig: &mut Multisig, 
    name: String, 
    issuer: I
) {
    multisig.deps.assert_core_dep(issuer);
    multisig.name = name;
}

// callable only in config.move, if the proposal has been accepted
public fun set_threshold<I: copy + drop>(
    multisig: &mut Multisig, 
    role: String, 
    threshold: u64,
    issuer: I,
) {
    multisig.deps.assert_core_dep(issuer);
    multisig.thresholds.set_or!(role, threshold, |current| {
        *current = threshold;
    });
}

// callable only in config.move, if the proposal has been accepted
public fun add_members<I: copy + drop>(
    multisig: &mut Multisig, 
    addresses: &mut vector<address>, 
    issuer: I,
) {
    multisig.deps.assert_core_dep(issuer);
    while (addresses.length() > 0) {
        let addr = addresses.pop_back();
        multisig.members.insert(
            addr, 
            member::new(
                1, 
                option::none(), 
                vector[b"global".to_string()]
            )
        );
    };
}

// callable only in config.move, if the proposal has been accepted
public fun remove_members<I: copy + drop>(
    multisig: &mut Multisig, 
    addresses: &mut vector<address>,
    issuer: I,
) {
    multisig.deps.assert_core_dep(issuer);
    while (addresses.length() > 0) {
        let addr = addresses.pop_back();
        let (_, member) = multisig.members.remove(&addr);
        member.delete();
    };
}

// callable only in config.move, if the proposal has been accepted
public fun modify_weight<I: copy + drop>(
    multisig: &mut Multisig, 
    addr: address,
    weight: u64,
    issuer: I,
) {
    multisig.deps.assert_core_dep(issuer);
    multisig.members[&addr].modify_weight(weight);
}

// callable only in config.move, if the proposal has been accepted
public fun add_roles<I: copy + drop>(
    multisig: &mut Multisig, 
    addr: address, 
    mut roles: vector<String>,
    issuer: I,
) {
    multisig.deps.assert_core_dep(issuer);
    multisig.members.get_mut(&addr).add_roles(roles);
}

// callable only in config.move, if the proposal has been accepted
public fun remove_roles<I: copy + drop>(
    multisig: &mut Multisig, 
    addr: address,
    mut roles: vector<String>,
    issuer: I,
) {
    multisig.deps.assert_core_dep(issuer);
    multisig.members.get_mut(&addr).remove_roles(roles);
}

// === Test functions ===

#[test_only]
public fun proposals_length(multisig: &Multisig): u64 {
    multisig.proposals.size()
}

