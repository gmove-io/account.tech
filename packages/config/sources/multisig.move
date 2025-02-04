
module account_config::multisig;

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
    intents::Expired,
};
use account_config::{
    version,
    user::User,
};

// === Errors ===

#[error]
const EMemberNotFound: vector<u8> = b"No member for this address";
#[error]
const ECallerIsNotMember: vector<u8> = b"Caller is not member";
#[error]
const ERoleNotFound: vector<u8> = b"Role not found";
#[error]
const EThresholdNotReached: vector<u8> = b"Threshold not reached";
#[error]
const ENotApproved: vector<u8> = b"Caller has not approved";
#[error]
const ERoleNotAdded: vector<u8> = b"Role not added so member cannot have it";
#[error]
const EThresholdTooHigh: vector<u8> = b"Threshold is too high";
#[error]
const EThresholdNull: vector<u8> = b"The global threshold cannot be null";
#[error]
const EMembersNotSameLength: vector<u8> = b"Members and roles vectors are not the same length";
#[error]
const ERolesNotSameLength: vector<u8> = b"The role vectors are not the same length";
#[error]
const EAlreadyApproved: vector<u8> = b"Proposal is already approved by the caller";
#[error]
const ENotMember: vector<u8> = b"User is not a member of the account";

// === Structs ===

public struct Witness() has drop;
/// [PROPOSAL] modifies the members and thresholds of the account
public struct ConfigMultisigIntent() has copy, drop;

/// [ACTION] wraps a Multisig struct into an action
public struct ConfigMultisigAction has drop, store {
    config: Multisig,
}

/// Parent struct protecting the config
public struct Multisig has copy, drop, store {
    // members and associated data
    members: vector<Member>,
    // global threshold
    global: u64,
    // role name with role threshold
    roles: vector<Role>,
}

/// Child struct for managing and displaying members
public struct Member has copy, drop, store {
    addr: address,
    // voting power of the member
    weight: u64,
    // roles that have been attributed
    roles: VecSet<String>,
}

/// Child struct representing a role with a name and its threshold
public struct Role has copy, drop, store {
    // role name: witness + optional name
    name: String,
    // threshold for the role
    threshold: u64,
}

/// Outcome field for the Proposals, must be validated before destruction
public struct Approvals has copy, drop, store {
    // total weight of all members that approved the proposal
    total_weight: u64,
    // sum of the weights of members who approved and have the role
    role_weight: u64, 
    // who has approved the proposal
    approved: VecSet<address>,
}

/// Invite object issued by an Account to a user
public struct Invite has key { 
    id: UID, 
    // Account that issued the invite
    account_addr: address,
}

// === Public functions ===

/// Init and returns a new Account object
/// Creator is added by default with weight and global threshold of 1
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

    account::new(extensions, config, false, ctx)
}

/// Authenticates the caller as a member of the multisig 
public fun authenticate(
    account: &Account<Multisig, Approvals>,
    ctx: &TxContext
): Auth {
    account.config().assert_is_member(ctx);
    account.new_auth(Witness())
}

/// Creates a new outcome to initiate a proposal
public fun empty_outcome(): Approvals {
    Approvals {
        total_weight: 0,
        role_weight: 0,
        approved: vec_set::empty(),
    }
}

/// We assert that all Proposals with the same key have the same outcome state
/// Approves all proposals with the same key
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

/// We assert that all Proposals with the same key have the same outcome state
/// Approves all proposals with the same key
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

/// Returns an executable if the number of signers is >= (global || role) threshold
/// Anyone can execute a proposal, this allows to automate the execution of proposals
public fun execute_intent(
    account: &mut Account<Multisig, Approvals>, 
    key: String, 
    clock: &Clock,
): Executable {
    let (executable, outcome) = account.execute_intent(key, clock, version::current(), Witness());
    outcome.validate(account.config(), account.intents().get(key).role());

    executable
}

public fun destroy_empty_intent(
    account: &mut Account<Multisig, Approvals>, 
    key: String, 
): Expired {
    account.destroy_empty_intent(key)
}

/// Removes a proposal if it has expired
/// Needs to delete each action in the bag within their own module
public fun delete_expired_intent(
    account: &mut Account<Multisig, Approvals>, 
    key: String, 
    clock: &Clock,
): Expired {
    account.delete_expired_intent(key, clock)
}

/// Inserts account_id in User, aborts if already joined
public fun join(user: &mut User, account: &mut Account<Multisig, Approvals>) {
    user.add_account(account.addr(), b"multisig".to_string());
}

/// Removes account_id from User, aborts if not joined
public fun leave(user: &mut User, account: &mut Account<Multisig, Approvals>) {
    user.remove_account(account.addr(), b"multisig".to_string());
}

/// Invites can be sent by an Account member (upon Account creation for instance)
public fun send_invite(account: &Account<Multisig, Approvals>, recipient: address, ctx: &mut TxContext) {
    // user inviting must be member
    account.config().assert_is_member(ctx);
    // invited user must be member
    assert!(account.config().is_member(recipient), ENotMember);

    transfer::transfer(Invite { 
        id: object::new(ctx), 
        account_addr: account.addr() 
    }, recipient);
}

/// Invited user can register the Account in his User account
public fun accept_invite(user: &mut User, invite: Invite) {
    let Invite { id, account_addr } = invite;
    id.delete();
    user.add_account(account_addr, b"multisig".to_string());
}

/// Deletes the invite object
public fun refuse_invite(invite: Invite) {
    let Invite { id, .. } = invite;
    id.delete();
}

// === [PROPOSAL] Public functions ===

/// No actions are defined as changing the config isn't supposed to be composable for security reasons

// step 1: propose to modify account rules (everything touching weights)
// threshold has to be valid (reachable and different from 0 for global)
public fun request_config_multisig(
    auth: Auth,
    outcome: Approvals,
    account: &mut Account<Multisig, Approvals>, 
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    // members 
    addresses: vector<address>,
    weights: vector<u64>,
    mut roles: vector<vector<String>>,
    // thresholds 
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    // verify new rules are valid
    verify_new_rules(addresses, weights, roles, global, role_names, role_thresholds);

    let mut intent = account.create_intent(
        key,
        description,
        execution_times,
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        ConfigMultisigIntent(),
        ctx
    );
    // must modify members before modifying thresholds to ensure they are reachable

    let mut config = Multisig { members: vector[], global: 0, roles: vector[] };
    addresses.zip_do!(weights, |addr, weight| {
        config.members.push_back(Member {
            addr,
            weight,
            roles: vec_set::from_keys(roles.remove(0)),
        });
    });

    config.global = global;
    role_names.zip_do!(role_thresholds, |role, threshold| {
        config.roles.push_back(Role { name: role, threshold });
    });

    account.add_action(&mut intent, ConfigMultisigAction { config }, version::current(), ConfigMultisigIntent());
    account.add_intent(intent, version::current(), ConfigMultisigIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)

// step 3: execute the action and modify Account Multisig
public fun execute_config_multisig(
    mut executable: Executable,
    account: &mut Account<Multisig, Approvals>, 
) {
    let action: &ConfigMultisigAction = account.process_action(&mut executable, version::current(), ConfigMultisigIntent());
    *account.config_mut(version::current(), Witness()) = action.config;
    account.confirm_execution(executable, version::current(), ConfigMultisigIntent());
}

public fun delete_config_multisig(expired: &mut Expired) {
    let ConfigMultisigAction { .. } = expired.remove_action();
}

// === Accessors ===

public fun addresses(multisig: &Multisig): vector<address> {
    multisig.members.map_ref!(|member| member.addr)
}

public fun member(multisig: &Multisig, addr: address): Member {
    let idx = multisig.get_member_idx(addr);
    multisig.members[idx]
}

public fun member_mut(multisig: &mut Multisig, addr: address): &mut Member {
    let idx = multisig.get_member_idx(addr);
    &mut multisig.members[idx]
}

public fun get_member_idx(multisig: &Multisig, addr: address): u64 {
    let opt = multisig.members.find_index!(|member| member.addr == addr);
    assert!(opt.is_some(), EMemberNotFound);
    opt.destroy_some()
}

public fun is_member(multisig: &Multisig, addr: address): bool {
    multisig.members.any!(|member| member.addr == addr)
}

public fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
    assert!(multisig.is_member(ctx.sender()), ECallerIsNotMember);
}

// member functions
public fun weight(member: &Member): u64 {
    member.weight
}

public fun roles(member: &Member): vector<String> {
    *member.roles.keys()
}

public fun has_role(member: &Member, role: String): bool {
    member.roles.contains(&role)
}

// roles functions
public fun get_global_threshold(multisig: &Multisig): u64 {
    multisig.global
}

public fun get_role_threshold(multisig: &Multisig, name: String): u64 {
    let idx = multisig.get_role_idx(name);
    multisig.roles[idx].threshold
}

public fun get_role_idx(multisig: &Multisig, name: String): u64 {
    let opt = multisig.roles.find_index!(|role| role.name == name);
    assert!(opt.is_some(), ERoleNotFound);
    opt.destroy_some()
}

public fun role_exists(multisig: &Multisig, name: String): bool {
    multisig.roles.any!(|role| role.name == name)
}

// outcome functions
public fun total_weight(outcome: &Approvals): u64 {
    outcome.total_weight
}

public fun role_weight(outcome: &Approvals): u64 {
    outcome.role_weight
}

public fun approved(outcome: &Approvals): vector<address> {
    *outcome.approved.keys()
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