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

module kraken_multisig::member;

// === Imports ===

use std::string::String;
use sui::vec_set::{Self, VecSet};

// === Structs ===

// struct for managing and displaying members
public struct Member has store {
    // voting power of the member
    weight: u64,
    // ID of the member's account, none if he didn't join yet
    account_id: Option<ID>,
    // roles that have been attributed
    roles: VecSet<String>,
}

// === Public mutative functions ===

public fun new(
    weight: u64,
    account_id: Option<ID>,
    roles: vector<String>,
): Member {
    Member {
        weight,
        account_id,
        roles: vec_set::from_keys(roles),
    }
}

public fun delete(member: Member) {
    let Member { .. } = member;
}

// === View functions ===

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

// === Package functions ===

// callable only in config.move, if the proposal has been accepted
public(package) fun modify_weight(
    member: &mut Member, 
    weight: u64,
) {
    member.weight = weight;
}

// callable only in config.move, if the proposal has been accepted
public(package) fun add_roles(
    member: &mut Member, 
    mut roles: vector<String>,
) {
    while (!roles.is_empty()) {
        let role = roles.pop_back();
        member.roles.insert(role);
    };
}

// callable only in config.move, if the proposal has been accepted
public(package) fun remove_roles(
    member: &mut Member, 
    mut roles: vector<String>,
) {
    while (!roles.is_empty()) {
        let role = roles.pop_back();
        member.roles.remove(&role);
    };
}

// for adding account id to members, from account.move
public(package) fun register_account_id(member: &mut Member, id: ID) {
    member.account_id.swap_or_fill(id);
}

// for removing account id from members, from account.move
public(package) fun unregister_account_id(member: &mut Member): ID {
    member.account_id.extract()
}
