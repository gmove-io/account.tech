/// This module defines and manages the members of a multisig Account.
/// Members have an address and a weight (1 by default).
/// They can have an User ID, when there's none it means the member didn't join yet.
/// They can also have roles, which are Auth.witness + opt(Auth.name).

module account_protocol::members;

// === Imports ===

use std::string::String;
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EMemberNotFound: u64 = 0;

// === Structs ===

/// Parent struct protecting the deps
public struct Members has store, drop {
    inner: vector<Member>,
}

/// Child struct for managing and displaying members
public struct Member has copy, drop, store {
    addr: address,
    // voting power of the member
    weight: u64,
    // ID of the member's User object, none if he didn't join yet
    user_id: Option<ID>,
    // roles that have been attributed
    roles: VecSet<String>,
}

// === Public mutative functions ===

/// Creates a new Deps struct with the core dependencies
public fun new(): Members {
    Members { inner: vector[] }
}

// Protected because &mut Deps is only accessible from AccountProtocol and AccountActions
public fun add(
    members: &mut Members,
    addr: address,
    weight: u64,
    user_id: Option<ID>,
    roles: vector<String>,
) {
    members.inner.push_back(Member {
        addr,
        weight,
        user_id,
        roles: vec_set::from_keys(roles),
    });
}

/// Registers the member's User ID, upon joining the Account
public fun register_user_id(
    member: &mut Member,
    id: ID,
) {
    member.user_id.swap_or_fill(id);
}

/// Unregisters the member's User ID, upon leaving the Account
public fun unregister_user_id(
    member: &mut Member,
): ID {
    member.user_id.extract()
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

public fun user_id(member: &Member): Option<ID> {
    member.user_id
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
    roles: vector<String>,
) {
    roles.do!(|role| {
        member.roles.insert(role);
    });
}

#[test_only]
public fun remove_roles(
    member: &mut Member,
    roles: vector<String>,
) {
    roles.do!(|role| {
        member.roles.remove(&role);
    });
}
