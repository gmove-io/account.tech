/// This module defines a Multisig configuration for an Account.
/// It also defines a new Outcome type for the intents.
/// 
/// Config consists of members, roles and thresholds.
/// Members have a weight and can have multiple roles.
/// There is a global threshold and a threshold for each role.
/// 
/// Intent resolution is done by checking the global and role intent weight against the thresholds.
/// If any of the role or global thresholds is reached, the intent can be executed.

module account_multisig::multisig;

// === Imports ===

use std::string::String;
use sui::{
    vec_set::{Self, VecSet},
    vec_map::{Self, VecMap},
    clock::Clock,
};
use account_extensions::extensions::Extensions;
use account_protocol::{
    account::{Self, Account, Auth},
    executable::Executable,
    user::{Self, User},
};
use account_multisig::version;

// === Errors ===

const EMemberNotFound: u64 = 0;
const ECallerIsNotMember: u64 = 1;
const ERoleNotFound: u64 = 2;
const EThresholdNotReached: u64 = 3;
const ENotApproved: u64 = 4;
const EAlreadyApproved: u64 = 5;
const ENotMember: u64 = 6;
const EMembersNotSameLength: u64 = 7;
const ERolesNotSameLength: u64 = 8;
const EThresholdTooHigh: u64 = 9;
const EThresholdNull: u64 = 10;
const ERoleNotAdded: u64 = 11;

// === Structs ===

/// Config Witness.
public struct Witness() has drop;

/// Parent struct protecting the config.
public struct Multisig has copy, drop, store {
    // members and associated data
    members: vector<Member>,
    // global threshold
    global: u64,
    // role name with role threshold
    roles: vector<Role>,
}

/// Child struct for managing and displaying members.
public struct Member has copy, drop, store {
    addr: address,
    // voting power of the member
    weight: u64,
    // roles that have been attributed
    roles: VecSet<String>,
}

/// Child struct representing a role with a name and associated threshold.
public struct Role has copy, drop, store {
    // role name: witness + optional name
    name: String,
    // threshold for the role
    threshold: u64,
}

/// Outcome field for the Intents, validated upon execution.
public struct Approvals has copy, drop, store {
    // sum of the weights of members who approved the intent
    total_weight: u64,
    // sum of the weights of members who approved and have the role
    role_weight: u64, 
    // who has approved the intent
    approved: VecSet<address>,
}

// === Public functions ===

/// Init and returns a new Account object.
/// Creator is added by default with weight and global threshold of 1.
/// AccountProtocol and AccountMultisig are added as dependencies.
public fun new_account(
    extensions: &Extensions,
    ctx: &mut TxContext,
): Account<Multisig, Approvals> {
    let config = Multisig {
        members: vector[Member { 
            addr: ctx.sender(), 
            weight: 1, 
            roles: vec_set::empty() 
        }],
        global: 1,
        roles: vector[],
    };

    let (ap_addr, ap_version) = extensions.get_latest_for_name(b"AccountProtocol".to_string());
    let (ac_addr, ac_version) = extensions.get_latest_for_name(b"AccountMultisig".to_string());
    // add AccountProtocol and AccountMultisig, minimal dependencies for the Multisig Account to work
    account::new(
        extensions, 
        config, 
        false, // unverified deps not authorized by default
        vector[b"AccountProtocol".to_string(), b"AccountMultisig".to_string()], 
        vector[ap_addr, ac_addr], 
        vector[ap_version, ac_version], 
        ctx)
}

/// Authenticates the caller as a member of the multisig.
public fun authenticate(
    account: &Account<Multisig, Approvals>,
    ctx: &TxContext
): Auth {
    account.config().assert_is_member(ctx);
    account.new_auth(version::current(), Witness())
}

/// Creates a new outcome to initiate an intent.
public fun empty_outcome(): Approvals {
    Approvals {
        total_weight: 0,
        role_weight: 0,
        approved: vec_set::empty(),
    }
}

/// Approves an intent increasing the outcome weight and optionally the role weight.
public fun approve_intent(
    account: &mut Account<Multisig, Approvals>, 
    key: String,
    ctx: &TxContext
) {
    assert!(
        !account.intents().get(key).outcome().approved.contains(&ctx.sender()), 
        EAlreadyApproved
    );

    let role = account.intents().get(key).role();
    let member = account.config().member(ctx.sender());
    let has_role = member.has_role(role);

    let outcome_mut = account.intents_mut(version::current(), Witness()).get_mut(key).outcome_mut();
    outcome_mut.approved.insert(ctx.sender()); // throws if already approved
    outcome_mut.total_weight = outcome_mut.total_weight + member.weight;
    if (has_role)
        outcome_mut.role_weight = outcome_mut.role_weight + member.weight;
}

/// Disapproves an intent decreasing the outcome weight and optionally the role weight.
public fun disapprove_intent(
    account: &mut Account<Multisig, Approvals>, 
    key: String,
    ctx: &TxContext
) {
    assert!(
        account.intents().get(key).outcome().approved.contains(&ctx.sender()), 
        ENotApproved
    );
    
    let role = account.intents().get(key).role();
    let member = account.config().member(ctx.sender());
    let has_role = member.has_role(role);

    let outcome_mut = account.intents_mut(version::current(), Witness()).get_mut(key).outcome_mut();
    outcome_mut.approved.remove(&ctx.sender()); // throws if already approved
    outcome_mut.total_weight = if (outcome_mut.total_weight < member.weight) 0 else outcome_mut.total_weight - member.weight;
    if (has_role)
        outcome_mut.role_weight = if (outcome_mut.role_weight < member.weight) 0 else outcome_mut.role_weight - member.weight;
}

/// Returns an executable if the number of signers is >= (global || role) threshold.
/// Anyone can execute an intent, this allows to automate the execution of intents.
public fun execute_intent(
    account: &mut Account<Multisig, Approvals>, 
    key: String, 
    clock: &Clock,
): Executable {
    let (executable, outcome) = account.execute_intent(key, clock, version::current(), Witness());
    outcome.validate(account.config(), account.intents().get(key).role());

    executable
}

/// Inserts account_id in User, aborts if already joined.
public fun join(user: &mut User, account: &Account<Multisig, Approvals>, ctx: &mut TxContext) {
    account.config().assert_is_member(ctx);
    user.add_account(account, Witness());
}

/// Removes account_id from User, aborts if not joined.
public fun leave(user: &mut User, account: &Account<Multisig, Approvals>) {
    user.remove_account(account, Witness());
}

/// Invites can be sent by a Multisig member when added to the Multisig.
public fun send_invite(account: &Account<Multisig, Approvals>, recipient: address, ctx: &mut TxContext) {
    // user inviting must be member
    account.config().assert_is_member(ctx);
    // invited user must be member
    assert!(account.config().is_member(recipient), ENotMember);

    user::send_invite(account, recipient, Witness(), ctx);
}

// === Accessors ===

/// Returns the addresses of the members.
public fun addresses(multisig: &Multisig): vector<address> {
    multisig.members.map_ref!(|member| member.addr)
}

/// Returns the member associated with the address.
public fun member(multisig: &Multisig, addr: address): Member {
    let idx = multisig.get_member_idx(addr);
    multisig.members[idx]
}

/// Returns a mutable reference to the member associated with the address.
/// safe because mutable Multisig access is protected by the Account.
public fun member_mut(multisig: &mut Multisig, addr: address): &mut Member {
    let idx = multisig.get_member_idx(addr);
    &mut multisig.members[idx]
}

/// Returns the index of the member associated with the address.
public fun get_member_idx(multisig: &Multisig, addr: address): u64 {
    let opt = multisig.members.find_index!(|member| member.addr == addr);
    assert!(opt.is_some(), EMemberNotFound);
    opt.destroy_some()
}

/// Returns true if the address is a member.
public fun is_member(multisig: &Multisig, addr: address): bool {
    multisig.members.any!(|member| member.addr == addr)
}

/// Asserts that the caller is a member.
public fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
    assert!(multisig.is_member(ctx.sender()), ECallerIsNotMember);
}

/// Returns the weight of the member.
public fun weight(member: &Member): u64 {
    member.weight
}

/// Returns the roles of the member.
public fun roles(member: &Member): vector<String> {
    *member.roles.keys()
}

/// Returns true if the member has the role.
public fun has_role(member: &Member, role: String): bool {
    member.roles.contains(&role)
}

/// Returns the global threshold.
public fun get_global_threshold(multisig: &Multisig): u64 {
    multisig.global
}

/// Returns the threshold of the role.
public fun get_role_threshold(multisig: &Multisig, name: String): u64 {
    let idx = multisig.get_role_idx(name);
    multisig.roles[idx].threshold
}

/// Returns the index of the role.
public fun get_role_idx(multisig: &Multisig, name: String): u64 {
    let opt = multisig.roles.find_index!(|role| role.name == name);
    assert!(opt.is_some(), ERoleNotFound);
    opt.destroy_some()
}

/// Returns true if the role exists in the multisig.
public fun role_exists(multisig: &Multisig, name: String): bool {
    multisig.roles.any!(|role| role.name == name)
}

/// Returns the total weight of the outcome.
public fun total_weight(outcome: &Approvals): u64 {
    outcome.total_weight
}

/// Returns the role weight of the outcome.
public fun role_weight(outcome: &Approvals): u64 {
    outcome.role_weight
}

/// Returns the addresses of the members who approved the outcome.
public fun approved(outcome: &Approvals): vector<address> {
    *outcome.approved.keys()
}

// === Package functions ===

/// Creates a new Multisig configuration, verifying thresholds can be reached.
public(package) fun new_config(
    members_addrs: vector<address>,
    members_weights: vector<u64>,
    mut members_roles: vector<vector<String>>,
    global_threshold: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
): Multisig {
    verify_new_rules(members_addrs, members_weights, members_roles, global_threshold, role_names, role_thresholds);

    let mut members = vector[];
    let mut roles = vector[];

    members_addrs.zip_do!(members_weights, |addr, weight| {
        members.push_back(Member {
            addr,
            weight,
            roles: vec_set::from_keys(members_roles.remove(0)),
        });
    });

    role_names.zip_do!(role_thresholds, |role, threshold| {
        roles.push_back(Role { name: role, threshold });
    });

    Multisig { members, global: global_threshold, roles }
}

/// Returns a mutable reference to the Multisig configuration.
public(package) fun config_mut(account: &mut Account<Multisig, Approvals>): &mut Multisig {
    account.config_mut(version::current(), Witness())
}

// === Private functions ===

fun verify_new_rules(
    // members 
    addresses: vector<address>,
    weights: vector<u64>,
    roles: vector<vector<String>>,
    // thresholds 
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
) {
    let total_weight = weights.fold!(0, |acc, weight| acc + weight);    
    assert!(addresses.length() == weights.length() && addresses.length() == roles.length(), EMembersNotSameLength);
    assert!(role_names.length() == role_thresholds.length(), ERolesNotSameLength);
    assert!(total_weight >= global, EThresholdTooHigh);
    assert!(global != 0, EThresholdNull);

    let mut weights_for_role: VecMap<String, u64> = vec_map::empty();
    weights.zip_do!(roles, |weight, roles_for_addr| {
        roles_for_addr.do!(|role| {
            if (weights_for_role.contains(&role)) {
                *weights_for_role.get_mut(&role) = weight;
            } else {
                weights_for_role.insert(role, weight);
            }
        });
    });

    while (!weights_for_role.is_empty()) {
        let (role, weight) = weights_for_role.pop();
        let (role_exists, idx) = role_names.index_of(&role);
        assert!(role_exists, ERoleNotAdded);
        assert!(weight >= role_thresholds[idx], EThresholdTooHigh);
    };
}

fun validate(
    outcome: Approvals, 
    multisig: &Multisig,
    role: String,
) {
    let Approvals { total_weight, role_weight, .. } = outcome;

    assert!(
        total_weight >= multisig.global ||
        (multisig.role_exists(role) && role_weight >= multisig.get_role_threshold(role)), 
        EThresholdNotReached
    );
}

// === Test functions ===

#[test_only]
public fun config_witness(): Witness {
    Witness()
}

#[test_only]
public fun add_member(
    multisig: &mut Multisig,
    addr: address,
) {
    multisig.members.push_back(Member { addr, weight: 1, roles: vec_set::empty() });
}

#[test_only]
public fun remove_member(
    multisig: &mut Multisig,
    addr: address,
) {
    let idx = multisig.get_member_idx(addr);
    multisig.members.remove(idx);
}

#[test_only]
public fun set_weight(
    member: &mut Member,
    weight: u64,
) {
    member.weight = weight;
}

#[test_only]
public fun add_role_to_multisig(
    multisig: &mut Multisig,
    name: String,
    threshold: u64,
) {
    multisig.roles.push_back(Role { name, threshold });
}

#[test_only]
public fun add_role_to_member(
    member: &mut Member,
    role: String,
) {
    member.roles.insert(role);
}

#[test_only]
public fun remove_role_from_member(
    member: &mut Member,
    role: String,
) {
    member.roles.remove(&role);
}