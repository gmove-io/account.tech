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

module kraken::multisig;

// === Imports ===

use std::string::String;
use sui::{
    clock::Clock, 
    vec_set::{Self, VecSet}, 
    vec_map::{Self, VecMap}, 
    bag::{Self, Bag},
    dynamic_field as df,
};
use kraken::{
    utils,
    auth::{Self, Auth},
};

// === Aliases ===

use fun utils::map_set_or as VecMap.set_or;

// === Errors ===

const ECallerIsNotMember: u64 = 0;
const EThresholdNotReached: u64 = 1;
const ECantBeExecutedYet: u64 = 2;
const EHasntExpired: u64 = 3;
const EWrongVersion: u64 = 4;
const EProposalNotFound: u64 = 5;
const EMemberNotFound: u64 = 6;

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
    // role -> threshold, no role is "global" (index == 0)
    thresholds: VecMap<String, u64>,
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
    // roles that have been attributed
    roles: VecSet<String>,
}

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

// === Public mutative functions ===

// init and share a new Multisig object
// creator is added by default with weight and threshold of 1
public fun new(name: String, account_id: ID, ctx: &mut TxContext): Multisig {
    let members = vec_map::from_keys_values(
        vector[ctx.sender()], 
        vector[Member { 
            weight: 1, 
            account_id: option::some(account_id), 
            roles: vec_set::from_keys(vector[b"global".to_string()]) 
        }]
    );      
    
    Multisig { 
        id: object::new(ctx),
        version: VERSION,
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
    multisig.assert_version();

    let proposal = Proposal { 
        id: object::new(ctx),
        auth: auth::construct(auth_issuer, auth_name, multisig.addr()),
        description,
        execution_time,
        expiration_epoch,
        actions: bag::new(ctx),
        total_weight: 0,
        role_weight: 0,
        approved: vec_set::empty(), 
    };

    multisig.proposals.insert(key, proposal);
    multisig.proposals.get_mut(&key)
}

// insert action to the proposal bag, safe because proposal_mut is only accessible upon creation
public fun add_action<A: store>(proposal: &mut Proposal, action: A) {
    let idx = proposal.actions.length();
    proposal.actions.add(idx, action);
}

// increase the global threshold and the role threshold if the signer has one
public fun approve_proposal(
    multisig: &mut Multisig, 
    key: String, 
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    multisig.assert_version();
    assert!(multisig.proposals.contains(&key), EProposalNotFound);

    let addr = ctx.sender();
    let role = multisig.proposal(&key).auth().into_role();
    let has_role = multisig.member(&addr).has_role(&role);

    let proposal = multisig.proposals.get_mut(&key);
    let weight = multisig.members.get(&addr).weight;
    proposal.approved.insert(addr); // throws if already approved
    proposal.total_weight = proposal.total_weight + weight;
    if (has_role)
        proposal.role_weight = proposal.role_weight + weight;
}

// the signer removes his agreement
public fun remove_approval(
    multisig: &mut Multisig, 
    key: String, 
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    multisig.assert_version();
    assert!(multisig.proposals.contains(&key), EProposalNotFound);

    let role = multisig.proposal(&key).auth().into_role();
    let has_role = multisig.member(&ctx.sender()).has_role(&role);

    let proposal = multisig.proposals.get_mut(&key);
    let weight = multisig.members.get(&ctx.sender()).weight;
    proposal.approved.remove(&ctx.sender()); // throws if already approved
    proposal.total_weight = proposal.total_weight - weight;
    if (has_role)
        proposal.role_weight = proposal.role_weight - weight;
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
        auth,
        execution_time,
        actions,
        total_weight,
        role_weight,
        ..
    } = proposal;
    
    id.delete();
    let role = auth.into_role();
    let has_role = multisig.member(&ctx.sender()).has_role(&role);

    assert!(clock.timestamp_ms() >= execution_time, ECantBeExecutedYet);
    assert!(
        total_weight >= multisig.threshold(b"global".to_string()) ||
        if (has_role) role_weight >= multisig.threshold(role) else false, 
        EThresholdNotReached
    );

    Executable { 
        auth,
        next_to_destroy: 0,
        actions
    }
}

public fun action_mut<I: drop, A: store>(
    executable: &mut Executable, 
    auth_issuer: I,
    multisig_addr: address,
): &mut A {
    executable.auth.assert_is_issuer(auth_issuer);
    executable.auth.assert_is_multisig(multisig_addr);

    let idx = executable.action_index<A>();
    executable.actions.borrow_mut(idx)
}

// need to destroy all actions before destroying the executable
public fun remove_action<I: drop, A: store>(
    executable: &mut Executable, 
    auth_issuer: I,
): A {
    executable.auth.assert_is_issuer(auth_issuer);

    let next = executable.next_to_destroy;
    executable.next_to_destroy = next + 1;

    executable.actions.remove(next)
}

// to complete the execution
public use fun destroy_executable as Executable.destroy;
public fun destroy_executable<I: drop>(
    executable: Executable, 
    auth_issuer: I
) {
    let Executable { 
        auth, 
        actions,
        ..
    } = executable;
    
    auth.assert_is_issuer(auth_issuer);
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
        expiration_epoch,
        actions,
        ..
    } = proposal;

    id.delete();
    assert!(expiration_epoch <= ctx.epoch(), EHasntExpired);

    actions
}

// === View functions ===

// Multisig accessors
public fun addr(multisig: &Multisig): address {
    multisig.id.uid_to_inner().id_to_address()
}

public fun version(multisig: &Multisig): u64 {
    multisig.version
}

public fun assert_version(multisig: &Multisig) {
    assert!(multisig.version == VERSION, EWrongVersion);
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

// Member accessors
public fun member(multisig: &Multisig, addr: &address): &Member {
    multisig.members.get(addr)
}

public fun weight(member: &Member): u64 {
    member.weight
}

public fun account_id(member: &Member): Option<ID> {
    member.account_id
}

public fun roles(member: &Member): vector<String> {
    *member.roles.keys()
}

public fun has_role(member: &Member, role: &String): bool {
    member.roles.contains(role)
}

// Proposal accessors
public fun proposal(multisig: &Multisig, key: &String): &Proposal {
    multisig.proposals.get(key)
}

public use fun proposal_auth as Proposal.auth;
public fun proposal_auth(proposal: &Proposal): &Auth {
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

public use fun proposal_actions_length as Proposal.actions_length;
public fun proposal_actions_length(proposal: &Proposal): u64 {
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

// Executable accessors
public use fun executable_auth as Executable.auth;
public fun executable_auth(executable: &Executable): &Auth {
    &executable.auth
}

public use fun executable_actions_length as Executable.actions_length;
public fun executable_actions_length(executable: &Executable): u64 {
    executable.actions.length()
}

public use fun executable_action as Executable.action;
public fun executable_action<A: store>(executable: &Executable, idx: u64): &A {
    executable.actions.borrow(idx)
}

public use fun executable_action_index as Executable.action_index;
public fun executable_action_index<A: store>(executable: &Executable): u64 {
    let length = executable.actions.length();
    let mut idx = executable.next_to_destroy;

    loop {
        if (
            idx == length || // returns length if action not found
            executable.actions.contains_with_type<u64, A>(idx)
        ) break idx;
        idx = idx + 1;
    };

    idx
}

// === Package functions ===

// managed assets
public(package) fun add_managed_asset<K: copy + drop + store, A: store>(
    multisig: &mut Multisig, 
    key: K, 
    asset: A
) {
    df::add(&mut multisig.id, key, asset);
}

public(package) fun borrow_managed_asset<K: copy + drop + store, A: store>(
    multisig: &Multisig, 
    key: K, 
): &A {
    df::borrow(&multisig.id, key)
}

public(package) fun borrow_managed_asset_mut<K: copy + drop + store, A: store>(
    multisig: &mut Multisig, 
    key: K, 
): &mut A {
    df::borrow_mut(&mut multisig.id, key)
}

public(package) fun remove_managed_asset<K: copy + drop + store, A: store>(
    multisig: &mut Multisig, 
    key: K, 
): A {
    df::remove(&mut multisig.id, key)
}

// callable only in config.move, if the proposal has been accepted
public(package) fun set_version(multisig: &mut Multisig, version: u64) {
    multisig.version = version;
}

// callable only in config.move, if the proposal has been accepted
public(package) fun set_name(multisig: &mut Multisig, name: String) {
    multisig.name = name;
}

// callable only in config.move, if the proposal has been accepted
public(package) fun set_threshold(
    multisig: &mut Multisig, 
    role: String, 
    threshold: u64
) {
    multisig.thresholds.set_or!(role, threshold, |current| {
        *current = threshold;
    });
}

// callable only in config.move, if the proposal has been accepted
public(package) fun add_members(
    multisig: &mut Multisig, 
    addresses: &mut vector<address>, 
) {
    while (addresses.length() > 0) {
        let addr = addresses.pop_back();
        multisig.members.insert(
            addr, 
            Member { 
                weight: 1, 
                account_id: option::none(), 
                roles: vec_set::from_keys(vector[b"global".to_string()])
            }
        );
    };
}

// callable only in config.move, if the proposal has been accepted
public(package) fun remove_members(
    multisig: &mut Multisig, 
    addresses: &mut vector<address>
) {
    while (addresses.length() > 0) {
        let addr = addresses.pop_back();
        let (_, member) = multisig.members.remove(&addr);
        let Member { .. } = member;
    };
}

// callable only in config.move, if the proposal has been accepted
public(package) fun modify_weight(
    multisig: &mut Multisig, 
    addr: address,
    weight: u64,
) {
    multisig.members[&addr].weight = weight;
}

// callable only in config.move, if the proposal has been accepted
public(package) fun add_roles(
    multisig: &mut Multisig, 
    addr: address, 
    mut roles: vector<String>,
) {
    let member = multisig.members.get_mut(&addr);
    while (!roles.is_empty()) {
        let role = roles.pop_back();
        member.roles.insert(role);
    };
}

// callable only in config.move, if the proposal has been accepted
public(package) fun remove_roles(
    multisig: &mut Multisig, 
    addr: address,
    mut roles: vector<String>,
) {
    let member = multisig.members.get_mut(&addr);
    while (!roles.is_empty()) {
        let role = roles.pop_back();
        member.roles.remove(&role);
    };
}

// for adding account id to members, from account.move
public(package) fun register_account_id(multisig: &mut Multisig, id: ID, ctx: &TxContext) {
    assert!(multisig.members.contains(&ctx.sender()), EMemberNotFound);
    let member = multisig.members.get_mut(&ctx.sender());
    member.account_id.swap_or_fill(id);
}

// for removing account id from members, from account.move
public(package) fun unregister_account_id(multisig: &mut Multisig, ctx: &TxContext): ID {
    assert!(multisig.members.contains(&ctx.sender()), EMemberNotFound);
    let member = multisig.members.get_mut(&ctx.sender());
    member.account_id.extract()
}

public(package) fun uid_mut(multisig: &mut Multisig): &mut UID {
    &mut multisig.id
}

public(package) fun uid(multisig: &Multisig): &UID {
    &multisig.id
}

// === Test functions ===

#[test_only]
public fun proposals_length(multisig: &Multisig): u64 {
    multisig.proposals.size()
}

