
module account_config::dao;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::{
    vec_set::{Self, VecSet},
    table::{Self, Table},
    clock::Clock,
    vec_map::{Self, VecMap},
    coin::Coin,
};
use account_extensions::extensions::Extensions;
use account_protocol::{
    account::{Self, Account},
    proposals::Expired,
    executable::Executable,
    auth::{Self, Auth},
    issuer::Issuer,
};
use account_config::{
    version,
    user::User,
    math,
};

// === Constants ===

const MUL: u64 = 1_000_000_000;
// acts as a dynamic enum for the voting rule
const LINEAR: u8 = 1;
const QUADRATIC: u8 = 2;

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
const EAlreadyApproved: vector<u8> = b"Proposal is already approved by the caller";
#[error]
const ENotApproved: vector<u8> = b"Caller has not approved";
#[error]
const ENotUnstaked: vector<u8> = b"Start cooldown before destroying voting power";
#[error]
const EProposalNotActive: vector<u8> = b"Proposal is not open to vote";
#[error]
const EInvalidAccount: vector<u8> = b"Invalid dao account for this staked asset";
#[error]
const EInvalidVotingRule: vector<u8> = b"Voting rule doesn't exist";
#[error]
const EInvalidAnswer: vector<u8> = b"Answer must be yes, no or abstain";
#[error]
const EThresholdNull: vector<u8> = b"Threshold must be greater than 0";
#[error]
const EMembersNotSameLength: vector<u8> = b"Members and roles vectors are not the same length";
#[error]
const ERolesNotSameLength: vector<u8> = b"The role vectors are not the same length";
#[error]
const ERoleNotAdded: vector<u8> = b"Role not added so member cannot have it";
#[error]
const EThresholdTooHigh: vector<u8> = b"Threshold is too high";

// === Structs ===

/// [PROPOSAL] modifies the rules of the dao account
public struct ConfigDaoProposal() has drop;

/// [ACTION] wraps a Dao struct into an action
public struct ConfigDaoAction has store {
    config: Dao,
}

/// Parent struct protecting the config
public struct Dao has copy, drop, store {
    // members and associated data
    members: vector<Member>,
    // role name with role threshold, works like a multisig, allows for "working groups"
    roles: vector<Role>,
    // object type allowed for voting
    asset_type: TypeName,
    // cooldown when unstaking, voting power decreases linearly over time
    staking_cooldown: u64,
    // type of voting mechanism, u8 so we can add more in the future
    voting_rule: u8,
    // maximum voting power that can be used in a single vote
    max_voting_power: u64,
    // minimum number of votes needed to pass a proposal (can be 0 if not important)
    minimum_votes: u64,
    // global voting threshold between (0, 1e9], If 50% votes needed, then should be > 500_000_000
    voting_quorum: u64, 
}

/// Child struct for managing and displaying members with roles
public struct Member has copy, drop, store {
    // address of the member
    addr: address,
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

/// Outcome field for the Proposals, voters are holders of the asset
/// Proposal is validated when role threshold is reached or dao rules are met
/// Must be validated before destruction
public struct Votes has store {
    // members with the role that approved the proposal
    role_approvals: u64,
    // who has approved the proposal
    approved: VecSet<address>,
    // voting start time 
    start_time: u64,
    // voting end time
    end_time: u64,
    // who has approved the proposal => (answer, voting_power)
    voted: Table<address, Voted>,
    // results of the votes, answer => total_voting_power
    results: VecMap<String, u64>,
}

/// Struct for storing the answer and voting power of a voter
public struct Voted(String, u64) has copy, drop, store;

/// Soul bound object wrapping the staked assets used for voting in a specific dao
/// Staked assets cannot be retrieved during the voting period
public struct Vote<Asset> has key, store {
    id: UID,
    // id of the dao account
    dao_id: ID,
    // Proposal.actions.id if VotingPower is linked to a proposal
    proposal_key: String,
    // answer chosen for the vote
    answer: String,
    // timestamp when the vote ends and when this object can be unpacked
    vote_end: u64,
    // staked assets with metadata
    assets: vector<Staked<Asset>>,
}

/// Staked asset, can be unstaked after the vote ends, according to the DAO cooldown
public struct Staked<Asset> has key, store {
    id: UID,
    // id of the dao account
    dao_id: ID,
    // value of the staked asset (Coin.value if Coin or 1 if Object)
    value: u64,
    // unstaking time, if none then staked
    unstaked: Option<u64>,
    // staked asset
    asset: Asset,
}

// === [ACCOUNT] Public functions ===

/// Init and returns a new Account object
public fun new_account<AssetType>(
    extensions: &Extensions,
    name: String,
    staking_cooldown: u64,
    voting_rule: u8,
    max_voting_power: u64,
    voting_quorum: u64,
    minimum_votes: u64,
    ctx: &mut TxContext,
): Account<Dao, Votes> {
    let config = Dao {
        members: vector[Member { 
            addr: ctx.sender(), 
            roles: vec_set::empty() 
        }],
        asset_type: type_name::get<AssetType>(),
        staking_cooldown,
        voting_rule,
        max_voting_power,
        voting_quorum,
        minimum_votes,
        roles: vector[],
    };

    account::new(extensions, name, config, ctx)
}

/// Authenticates the caller for a given role or globally
public fun authenticate<Outcome>(
    extensions: &Extensions,
    account: &Account<Dao, Outcome>,
    role: String, // can be empty
    ctx: &TxContext
): Auth {
    account.config().assert_is_member(ctx);
    if (!role.is_empty()) assert!(account.config().member(ctx.sender()).has_role(role), ERoleNotFound);

    auth::new(extensions, role, account.addr(), version::current())
}

/// Creates a new outcome to initiate a proposal
public fun empty_outcome(
    account: &Account<Dao, Votes>,
    start_time: u64,
    end_time: u64,
    ctx: &mut TxContext
): Votes {
    account.config().assert_is_member(ctx); // TODO: who can create a proposal?

    Votes {
        role_approvals: 0,
        approved: vec_set::empty(),
        start_time,
        end_time,
        voted: table::new(ctx),
        results: vec_map::from_keys_values(
            vector[b"yes".to_string(), b"no".to_string(), b"abstain".to_string()], 
            vector[0, 0, 0],
        ),
    }
}

public fun new_vote<Asset: store>(
    account: &mut Account<Dao, Votes>,
    proposal_key: String,
    ctx: &mut TxContext
): Vote<Asset> {
    Vote {
        id: object::new(ctx),
        dao_id: object::id(account),
        proposal_key,
        answer: b"".to_string(),
        vote_end: account.proposal(proposal_key).outcome().end_time,
        assets: vector[],
    }
}

/// Stakes a coin and calculates the voting power
public fun stake_coin<CoinType>(
    account: &mut Account<Dao, Votes>,
    coin: Coin<CoinType>,
    ctx: &mut TxContext
): Staked<Coin<CoinType>> {
    Staked {
        id: object::new(ctx),
        dao_id: object::id(account),
        value: coin.value(),
        unstaked: option::none(),
        asset: coin,
    }
}

/// Stakes the asset and calculates the voting power
public fun stake_object<Asset: store>(
    account: &mut Account<Dao, Votes>,
    asset: Asset,
    ctx: &mut TxContext
): Staked<Asset> {
    Staked {
        id: object::new(ctx),
        dao_id: object::id(account),
        value: 1,
        unstaked: option::none(),
        asset,
    }
}

/// Starts cooldown for the staked asset
public fun unstake<Asset>(
    staked: &mut Staked<Asset>,
    clock: &Clock,
) {
    staked.unstaked = option::some(clock.timestamp_ms());    
}

/// Retrieves the staked asset after cooldown
public fun claim<Asset>(
    staked: Staked<Asset>,
    account: &mut Account<Dao, Votes>,
    clock: &Clock,
): Asset {
    let Staked { id, dao_id, mut unstaked, asset, .. } = staked;
    id.delete();
    
    assert!(dao_id == object::id(account), EInvalidAccount);
    assert!(unstaked.is_some(), ENotUnstaked);
    assert!(clock.timestamp_ms() > account.config().staking_cooldown + unstaked.extract(), ENotUnstaked);

    asset
}

/// Can be done while vote is open 
public fun add_staked_to_vote<Asset>(
    vote: &mut Vote<Asset>,
    staked: Staked<Asset>,
) {
    vote.assets.push_back(staked);
}

/// Can be done after vote is closed
public fun remove_staked_from_vote<Asset>(
    vote: &mut Vote<Asset>,
    idx: u64,
): Staked<Asset> {
    vote.assets.swap_remove(idx)
}

public fun vote<Asset: store>(
    vote: &mut Vote<Asset>,
    account: &mut Account<Dao, Votes>,
    key: String,
    answer: String,
    clock: &Clock,
) {
    assert!(
        clock.timestamp_ms() > account.proposal(key).outcome().start_time &&
        clock.timestamp_ms() < account.proposal(key).outcome().end_time, 
        EProposalNotActive
    );
    assert!(
        answer == b"yes".to_string() || answer == b"no".to_string() || answer == b"abstain".to_string(), 
        EInvalidAnswer
    ); // could change in the future

    let power = vote.get_voting_power(account, clock);
    vote.answer = answer;

    account.proposals().all_idx(key).do!(|idx| {
        let outcome_mut = account.proposal_mut(idx, version::current()).outcome_mut();
        // if already voted, remove previous vote to update it
        if (outcome_mut.voted.contains(vote.addr())) {
            let (prev_answer, prev_power) = outcome_mut.voted(vote.addr());
            *outcome_mut.results.get_mut(&prev_answer) = *outcome_mut.results.get_mut(&prev_answer) - prev_power;
        };

        outcome_mut.voted.add(vote.addr(), Voted(answer, power)); // throws if already approved
        *outcome_mut.results.get_mut(&answer) = *outcome_mut.results.get_mut(&answer) + power;
    });
}

/// Members with the role of the proposal can approve the proposal and bypass the vote
/// We assert that all Proposals with the same key have the same outcome state
/// Approves all proposals with the same key
public fun approve_proposal(
    account: &mut Account<Dao, Votes>, 
    key: String,
    ctx: &TxContext
) {
    assert!(
        !account.proposal(key).outcome().approved.contains(&ctx.sender()), 
        EAlreadyApproved
    );

    let role = account.proposal(key).issuer().full_role();
    let member = account.config().member(ctx.sender());
    assert!(member.has_role(role), ERoleNotFound);

    account.proposals().all_idx(key).do!(|idx| {
        let outcome_mut = account.proposal_mut(idx, version::current()).outcome_mut();
        outcome_mut.approved.insert(ctx.sender()); // throws if already approved
        outcome_mut.role_approvals = outcome_mut.role_approvals + 1;
    });
}

/// We assert that all Proposals with the same key have the same outcome state
/// Approves all proposals with the same key
public fun disapprove_proposal(
    account: &mut Account<Dao, Votes>, 
    key: String,
    ctx: &TxContext
) {
    assert!(
        account.proposal(key).outcome().approved.contains(&ctx.sender()), 
        ENotApproved
    );
    
    let role = account.proposal(key).issuer().full_role();
    let member = account.config().member(ctx.sender());
    assert!(member.has_role(role), ERoleNotFound);

    account.proposals().all_idx(key).do!(|idx| {
        let outcome_mut = account.proposal_mut(idx, version::current()).outcome_mut();
        outcome_mut.approved.remove(&ctx.sender()); // throws if already approved
        outcome_mut.role_approvals = if (outcome_mut.role_approvals == 0) 0 else outcome_mut.role_approvals - 1;
    });
}

/// Returns an executable if the number of signers is >= (global || role) threshold
/// Anyone can execute a proposal, this allows to automate the execution of proposals
public fun execute_proposal(
    account: &mut Account<Dao, Votes>, 
    key: String, 
    clock: &Clock,
): Executable {
    let (executable, outcome) = account.execute_proposal(key, clock, version::current());
    outcome.validate(account.config(), executable.issuer());

    executable
}

public fun delete_proposal(
    account: &mut Account<Dao, Votes>, 
    key: String,
    clock: &Clock,
): Expired<Votes> {
    account.delete_proposal(key, version::current(), clock)
}

/// Actions must have been removed and deleted before calling this function
public fun delete_expired_outcome(
    expired: Expired<Votes>
) {
    let Votes { voted, .. } = expired.remove_expired_outcome();
    voted.drop();
}

// User functions

/// Inserts account_id in User, aborts if already joined
public fun join(user: &mut User, account: &mut Account<Dao, Votes>) {
    user.add_account(account.addr(), b"dao".to_string());
}

/// Removes account_id from User, aborts if not joined
public fun leave(user: &mut User, account: &mut Account<Dao, Votes>) {
    user.remove_account(account.addr(), b"dao".to_string());
}

// === [PROPOSAL] Public functions ===

/// No actions are defined as changing the config isn't supposed to be composable for security reasons

// step 1: propose to modify account rules (everything touching weights)
// threshold has to be valid (reachable and different from 0 for global)
public fun propose_config_dao(
    auth: Auth,
    account: &mut Account<Dao, Votes>, 
    outcome: Votes,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    // members & roles
    member_addresses: vector<address>,
    member_roles: vector<vector<String>>,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
    // dao rules
    asset_type: TypeName,
    staking_cooldown: u64,
    voting_rule: u8,
    max_voting_power: u64,
    minimum_votes: u64,
    voting_quorum: u64,
    ctx: &mut TxContext
) {
    // verify new rules are valid
    verify_new_rules(member_addresses, member_roles, role_names, role_thresholds);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        ConfigDaoProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_time,
        ctx
    );
    // must modify members before modifying thresholds to ensure they are reachable

    let mut config = Dao { 
        members: vector[], 
        roles: vector[], 
        asset_type, 
        staking_cooldown, 
        voting_rule, 
        max_voting_power, 
        minimum_votes, 
        voting_quorum
    };

    member_addresses.zip_do!(member_roles, |addr, role| {
        config.members.push_back(Member {
            addr,
            roles: vec_set::from_keys(role),
        });
    });

    role_names.zip_do!(role_thresholds, |role, threshold| {
        config.roles.push_back(Role { name: role, threshold });
    });

    proposal.add_action(ConfigDaoAction { config }, ConfigDaoProposal());
    account.add_proposal(proposal, version::current(), ConfigDaoProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)

// step 3: execute the action and modify Account Multisig
public fun execute_config_dao(
    mut executable: Executable,
    account: &mut Account<Dao, Votes>, 
) {
    let ConfigDaoAction { config } = executable.action(account.addr(), version::current(), ConfigDaoProposal());
    *account.config_mut(version::current()) = config;
    executable.destroy(version::current(), ConfigDaoProposal());
}

public fun delete_expired_config_dao(expired: &mut Expired<Votes>) {
    let action = expired.remove_expired_action();
    let ConfigDaoAction { .. } = action;
}

// === Accessors ===

public fun addr<Asset: store>(vote: &Vote<Asset>): address {
    object::id(vote).to_address()
}

public fun addresses(dao: &Dao): vector<address> {
    dao.members.map_ref!(|member| member.addr)
}

public fun member(dao: &Dao, addr: address): Member {
    let idx = dao.get_member_idx(addr);
    dao.members[idx]
}

public fun member_mut(dao: &mut Dao, addr: address): &mut Member {
    let idx = dao.get_member_idx(addr);
    &mut dao.members[idx]
}

public fun get_member_idx(dao: &Dao, addr: address): u64 {
    let opt = dao.members.find_index!(|member| member.addr == addr);
    assert!(opt.is_some(), EMemberNotFound);
    opt.destroy_some()
}

public fun is_member(dao: &Dao, addr: address): bool {
    dao.members.any!(|member| member.addr == addr)
}

public fun assert_is_member(dao: &Dao, ctx: &TxContext) {
    assert!(dao.is_member(ctx.sender()), ECallerIsNotMember);
}

// member functions
public fun roles(member: &Member): vector<String> {
    *member.roles.keys()
}

public fun has_role(member: &Member, role: String): bool {
    member.roles.contains(&role)
}

// roles functions
public fun get_role_threshold(dao: &Dao, name: String): u64 {
    let idx = dao.get_role_idx(name);
    dao.roles[idx].threshold
}

public fun get_role_idx(dao: &Dao, name: String): u64 {
    let opt = dao.roles.find_index!(|role| role.name == name);
    assert!(opt.is_some(), ERoleNotFound);
    opt.destroy_some()
}

public fun role_exists(dao: &Dao, name: String): bool {
    dao.roles.any!(|role| role.name == name)
}

public fun asset_type(dao: &Dao): TypeName {
    dao.asset_type
}

public fun is_coin(dao: &Dao): bool {
    let addr = dao.asset_type.get_address();
    let module_name = dao.asset_type.get_module();

    let str_bytes = dao.asset_type.into_string().as_bytes();
    let mut struct_name = vector[];
    4u64.do!(|i| {
        struct_name.push_back(str_bytes[i + 72]); // starts at 0x2::coin::
    });
    
    addr == @0x0000000000000000000000000000000000000000000000000000000000000002.to_ascii_string() &&
    module_name == b"coin".to_ascii_string() &&
    struct_name == b"Coin"
}

// outcome functions
public fun start_time(outcome: &Votes): u64 {
    outcome.start_time
}

public fun end_time(outcome: &Votes): u64 {
    outcome.end_time
}

public fun voted(outcome: &Votes, vote: address): (String, u64) {
    let voted = outcome.voted.borrow(vote);
    (voted.0, voted.1)
}

public fun results(outcome: &Votes): &VecMap<String, u64> {
    &outcome.results
}

// === Private functions ===

fun verify_new_rules(
    member_addresses: vector<address>,
    member_roles: vector<vector<String>>,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
) {
    assert!(member_addresses.length() == member_roles.length(), EMembersNotSameLength);
    assert!(role_names.length() == role_thresholds.length(), ERolesNotSameLength);
    assert!(!role_thresholds.any!(|threshold| threshold == 0), EThresholdNull);

    let mut weights_for_role: VecMap<String, u64> = vec_map::from_keys_values(role_names, vector::tabulate!(role_names.length(), |_| 0));
    member_roles.do!(|roles| {
        roles.do!(|role| {
            *weights_for_role.get_mut(&role) = *weights_for_role.get_mut(&role) + 1;
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
    outcome: Votes, 
    dao: &Dao, 
    issuer: &Issuer,
) {
    let Votes { voted, role_approvals, results, .. } = outcome;
    voted.drop();

    let role = issuer.full_role();
    let total_votes = results[&b"yes".to_string()] + results[&b"no".to_string()];

    assert!(
        (dao.role_exists(role) && role_approvals >= dao.get_role_threshold(role)) ||
        total_votes >= dao.minimum_votes && results[&b"yes".to_string()] * MUL / total_votes >= dao.voting_quorum, 
        EThresholdNotReached
    );
}

/// Returns the voting multiplier depending on the cooldown [0, 1e9]
fun get_voting_power<Asset>(
    vote: &Vote<Asset>,
    account: &Account<Dao, Votes>,
    clock: &Clock,
): u64 {
    assert!(vote.dao_id == object::id(account), EInvalidAccount);

    let mut total = 0;
    vote.assets.do_ref!(|staked| {
        let multiplier = if (staked.unstaked.is_none()) {
            MUL
        } else {
            let time_passed = clock.timestamp_ms() - *staked.unstaked.borrow();
            if (time_passed > account.config().staking_cooldown) 0 else
                (account.config().staking_cooldown - time_passed) * MUL / account.config().staking_cooldown
        };

        total = total + staked.value * multiplier;
    });

    let mut voting_power = total / MUL;

    if (account.config().voting_rule == LINEAR) {
        // do nothing
    } else if (account.config().voting_rule == QUADRATIC) {
        voting_power = math::sqrt_down(total as u256) as u64 / MUL
    } else {
        abort EInvalidVotingRule
    }; // can add other voting rules in the future

    voting_power
}

// === Test functions ===

#[test_only]
public fun add_member(
    dao: &mut Dao,
    addr: address,
) {
    dao.members.push_back(Member { addr, roles: vec_set::empty() });
}

#[test_only]
public fun remove_member(
    dao: &mut Dao,
    addr: address,
) {
    let idx = dao.get_member_idx(addr);
    dao.members.remove(idx);
}

#[test_only]
public fun add_role_to_multisig(
    dao: &mut Dao,
    name: String,
    threshold: u64,
) {
    dao.roles.push_back(Role { name, threshold });
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