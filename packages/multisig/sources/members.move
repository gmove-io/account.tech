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

module kraken_multisig::members;

// === Imports ===

use std::string::String;
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EMemberNotFound: u64 = 0;

// === Structs ===

public struct Members has store, drop {
    inner: vector<Member>,
}

// struct for managing and displaying members
public struct Member has copy, drop, store {
    addr: address,
    // voting power of the member
    weight: u64,
    // ID of the member's account, none if he didn't join yet
    account_id: Option<ID>,
    // roles that have been attributed
    roles: VecSet<String>,
}

// === Public mutative functions ===

public fun new(): Members {
    Members { inner: vector[] }
}

public fun new_member(
    addr: address,
    weight: u64,
    account_id: Option<ID>,
    roles: vector<String>,
): Member {
    Member {
        addr,
        weight,
        account_id,
        roles: vec_set::from_keys(roles),
    }
}

// protected because &mut Deps accessible only from KrakenMultisig and KrakenActions
public fun add(
    members: &mut Members,
    member: Member,
) {
    members.inner.push_back(member);
}

public fun register_account_id(
    member: &mut Member,
    id: ID,
) {
    member.account_id.swap_or_fill(id);
}

public fun unregister_account_id(
    member: &mut Member,
): ID {
    member.account_id.extract()
}

// === View functions ===

public fun to_vec(members: &Members): vector<Member> {
    members.inner
}

public fun addresses(members: &Members): vector<address> {
    members.inner.map_ref!(|member| member.addr)
}

public fun get_idx(members: &Members, addr: address): u64 {
    let opt = members.inner.find_index!(|member| member.addr == addr);
    assert!(opt.is_some(), EMemberNotFound);
    opt.destroy_some()
}

public fun is_member(members: &Members, addr: address): bool {
    members.inner.any!(|member| member.addr == addr)
}

public fun get(members: &Members, addr: address): &Member {
    let idx = members.get_idx(addr);
    &members.inner[idx]
}

// member functions
public fun weight(member: &Member): u64 {
    member.weight
}

public fun account_id(member: &Member): Option<ID> {
    member.account_id
}

public fun roles(member: &Member): vector<String> {
    *member.roles.keys()
}

public fun has_role(member: &Member, role: String): bool {
    member.roles.contains(&role)
}

// === Package functions ===

public(package) fun get_mut(members: &mut Members, addr: address): &mut Member {
    let idx = members.get_idx(addr);
    &mut members.inner[idx]
}

// === Test functions ===

#[test_only]
public fun remove(
    members: &mut Members,
    addr: address,
) {
    let idx = members.get_idx(addr);
    members.inner.remove(idx);
}

#[test_only]
public fun set_weight(
    member: &mut Member,
    weight: u64,
) {
    member.weight = weight;
}

#[test_only]
public fun add_roles(
    member: &mut Member,
    mut roles: vector<String>,
) {
    while (!roles.is_empty()) {
        let role = roles.pop_back();
        member.roles.insert(role);
    };
}

#[test_only]
public fun remove_roles(
    member: &mut Member,
    mut roles: vector<String>,
) {
    while (!roles.is_empty()) {
        let role = roles.pop_back();
        member.roles.remove(&role);
    };
}