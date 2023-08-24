// Copyright 2023 Shinami Corp.
// SPDX-License-Identifier: Apache-2.0

module account_graph::account_graph {
    use std::option::{Self, Option};
    use std::string::String;
    use std::vector;

    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::vec_map::{Self, VecMap};
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};
    use sui::transfer::{share_object};
    use sui::tx_context::{sender, TxContext};

    const EOutDegreeExceeded: u64    = 0;
    const EZeroOutDegree: u64        = 1;
    const ERelationshipNotExist: u64 = 2;

    /// `AccountGraph` models the relationships between various addresses in a directed graph.
    /// Nodes are all addresses and relationships are edges between nodes or addresses,
    /// `AccountGraph` stores relationships, properties of addresses, properties of edges.
    struct AccountGraph<phantom AccountProps: copy + drop + store, phantom RelationshipProps: copy + drop + store> has key, store {
        /// A unique identifier (UID) for the graph as a SUI object.
        id: UID,

        /// Purpose of this `AccountGraph` and actual meaning of account relationship.
        description: String,

        /// An optional field that limits the maximum number of outgoing edges from a node,
        /// if set to `Some(0)`, graph creation will fail.
        max_out_degree: Option<u32>,

        /// A table mapping an address to its associated account relationships.
        relationships: Table<address, VecSet<address>>,

        /// A table mapping an address to its associated account properties of type `AccountProps`.
        account_props: Table<address, AccountProps>,

        /// A table mapping a relationship key to its associated relationship properties of type `RelationshipProps`.
        relationship_props: Table<RelationshipKey, RelationshipProps>,
    }

    /// `EmptyProp` can be used as `AccountProps` or `RelationshipProps`,
    /// when no specific properties are required.
    struct EmptyProp has copy, drop, store {}

    struct RelationshipKey has copy, drop, store {
        source: address,
        target: address,
    }

    fun new<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        description: String,
        max_out_degree: Option<u32>,
        ctx: &mut TxContext,
    ): AccountGraph<AccountProps, RelationshipProps> {
        assert!(option::is_none(&max_out_degree) || !option::contains(&max_out_degree, &0), EZeroOutDegree);
        AccountGraph {
            id: object::new(ctx),
            description,
            max_out_degree,
            relationships: table::new<address, VecSet<address>>(ctx),
            account_props: table::new<address, AccountProps>(ctx),
            relationship_props: table::new<RelationshipKey, RelationshipProps>(ctx),
        }
    }

    /// Create an `account_graph`.
    public fun create<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        description: String,
        max_out_degree: Option<u32>,
        ctx: &mut TxContext,
    ) {
        let graph = new<AccountProps, RelationshipProps>(description, max_out_degree, ctx);
        let graph_id = object::id(&graph);
        share_object(graph);
        event::emit(GraphCreated{ graph_id });
    }

    fun relationship_exists<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        source: address,
        target: address,
    ): bool {
        table::contains(&self.relationships, source) && vec_set::contains(table::borrow(&self.relationships, source), &target)
    }

    /// Add a relationship as edge, where source is the sender.
    public fun add_relationship<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_lists = &mut self.relationships;
        if (table::contains(adj_lists, source)) {
            let targets = table::borrow_mut(adj_lists, source);
            assert!(
                option::is_none(&self.max_out_degree) ||
                    vec_set::size(targets) < (*option::borrow(&self.max_out_degree) as u64),
                EOutDegreeExceeded
            );
            vec_set::insert(targets, target)
        } else {
            table::add(adj_lists, source, vec_set::singleton(target))
        };
        event::emit(RelationshipAdded{ graph_id: object::id(self), source, target })
    }

    /// Remove a relationship as edge, where source is the sender,
    /// fail if node doesn't exist. Property of the relationship
    /// will be removed if exists. It also unsets relationship
    /// property in `relationship_props` if there is any.
    public fun remove_relationship<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ): (address, Option<RelationshipProps>) {
        let source = sender(ctx);
        let adj_lists = table::borrow_mut(&mut self.relationships, source);
        vec_set::remove(adj_lists, &target);
        if (vec_set::size(adj_lists) == 0) {
            table::remove(&mut self.relationships, source);
        };
        let props = unset_relationship_props(self, target, ctx);
        event::emit(RelationshipRemoved{ graph_id: object::id(self), source, target });
        (target, props)
    }

    /// Remove all relationships of the sender and remove all
    /// properties of these relationships if there is any.
    public fun clear_relationships<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ): VecMap<address, Option<RelationshipProps>> {
        let source = sender(ctx);
        let adj_lists = &mut self.relationships;
        let ret = vec_map::empty();
        if (!table::contains(adj_lists, source)) return ret;
        let targets = table::remove(adj_lists, source);
        let target_vec = vec_set::keys(&targets);
        let graph_id = object::id(self);
        let size = vector::length(target_vec);
        let i = 0u64;
        while (i < size) {
            let target = *vector::borrow(target_vec, i);
            let props = unset_relationship_props(self, target, ctx);

            vec_map::insert(&mut ret, target, props);

            event::emit(
                RelationshipRemoved {
                    graph_id,
                    source,
                    target,
                }
            );
            i = i + 1;
        };
        ret
    }

    /// Set properties for the sender account,
    /// previous value is overwritten if exists
    public fun set_account_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        props: AccountProps,
        ctx: &mut TxContext,
    ): Option<AccountProps> {
        let node = sender(ctx);
        let account_props = &mut self.account_props;
        let ret = if (table::contains(account_props, node)) {
            let props_ref = table::borrow_mut(account_props, node);
            let ret = option::some(*props_ref);
            *props_ref = props;
            ret
        } else {
            table::add(account_props, node, props);
            option::none()
        };
        event::emit(AccountPropsSet { graph_id: object::id(self), node, props });
        ret
    }

    /// Unset properties for the sender account.
    public fun unset_account_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ): Option<AccountProps> {
        let node = sender(ctx);
        let account_props = &mut self.account_props;
        if (table::contains(account_props, node)) {
            let props = table::remove(account_props, node);
            event::emit(AccountPropsUnset { graph_id: object::id(self), node, props });
            option::some(props)
        } else {
            option::none()
        }
    }

    /// Set property for a relationship, where sender is the source,
    /// previous value is overwritten if exists
    public fun set_relationship_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        props: RelationshipProps,
        ctx: &mut TxContext,
    ): Option<RelationshipProps> {
        let source = sender(ctx);
        assert!(relationship_exists(self, source, target), ERelationshipNotExist);
        let rel_props = &mut self.relationship_props;
        let rel_key = RelationshipKey { source, target };
        let ret = if (table::contains(rel_props, rel_key)) {
            let props_ref = table::borrow_mut(rel_props, rel_key);
            let ret = option::some(*props_ref);
            *props_ref = props;
            ret
        } else {
            table::add(rel_props, rel_key, props);
            option::none()
        };
        event::emit(RelationshipPropsSet{ graph_id: object::id(self), source, target, props });
        ret
    }

    /// Unset property for a relationship, where sender is the source.
    public fun unset_relationship_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ): Option<RelationshipProps> {
        let source = sender(ctx);
        let rel_props = &mut self.relationship_props;
        let key = RelationshipKey { source, target };
        if (table::contains(rel_props, key)) {
            let props = table::remove(rel_props, key);
            event::emit(RelationshipPropsUnset{ graph_id: object::id(self), source, target, props });
            option::some(props)
        } else {
            option::none()
        }
    }


    // === Events ===

    struct GraphCreated has copy, drop {
        graph_id: ID,
    }

    struct RelationshipAdded has copy, drop {
        graph_id: ID,
        source: address,
        target: address,
    }

    struct RelationshipRemoved has copy, drop {
        graph_id: ID,
        source: address,
        target: address,
    }

    struct AccountPropsSet<Props: copy> has copy, drop {
        graph_id: ID,
        node: address,
        props: Props,
    }

    struct AccountPropsUnset<Props: copy> has copy, drop {
        graph_id: ID,
        node: address,
        props: Props,
    }

    struct RelationshipPropsSet<Props: copy> has copy, drop {
        graph_id: ID,
        source: address,
        target: address,
        props: Props,
    }

    struct RelationshipPropsUnset<Props: copy> has copy, drop {
        graph_id: ID,
        source: address,
        target: address,
        props: Props,
    }

    // === Unit tests ===

    #[test_only]
    public fun drop<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        graph: AccountGraph<AccountProps, RelationshipProps>,
    ) {
        let AccountGraph {
            id,
            description: _,
            max_out_degree: _,
            relationships,
            account_props,
            relationship_props,
        } = graph;
        object::delete(id);
        table::drop(relationships);
        table::drop(account_props);
        table::drop(relationship_props);
    }


    #[test_only]
    fun target_count<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        source: address,
    ): u64 {
        let adj_lists = &self.relationships;
        if (table::contains(adj_lists, source)) {
            vec_set::size(table::borrow(adj_lists, source))
        } else {
            0
        }
    }

    #[test_only]
    fun contains_relationships<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        source: address,
    ): bool {
        table::contains(&self.relationships, source)
    }

    #[test_only]
    fun get_account_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ): &AccountProps {
        table::borrow(&self.account_props, sender(ctx))
    }

    #[test_only]
    fun contains_account_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ): bool {
        table::contains(&self.account_props, sender(ctx))
    }

    #[test_only]
    fun get_relationship_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ): &RelationshipProps {
        table::borrow(&self.relationship_props, RelationshipKey{ source: sender(ctx), target})
    }

    #[test_only]
    fun contains_relationship_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ): bool {
        table::contains(&self.relationship_props, RelationshipKey{ source: sender(ctx), target})
    }

    #[test_only]
    fun new_for_test<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        max_out_degree: Option<u32>,
        ctx: &mut TxContext,
    ): AccountGraph<AccountProps, RelationshipProps> {
        new<AccountProps, RelationshipProps>(std::string::utf8(vector::empty()), max_out_degree, ctx)
    }


    #[test]
    public fun test_create_graph() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);
        drop(graph);
    }

    #[test]
    #[expected_failure]
    public fun test_create_graph_zero_out_degree() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(0), &mut ctx);
        drop(graph);
    }

    #[test]
    public fun test_create_graph_none_out_degree() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::none(), &mut ctx);
        drop(graph);
    }

    #[test]
    public fun test_add_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 1, 0);

        drop(graph)
    }

    #[test]
    public fun test_add_2_relationships() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(2), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x234, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 2, 0);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_add_same_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x123, &mut ctx);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_add_same_relationship2() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::none(), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x123, &mut ctx);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_add_exceeded_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x456, &mut ctx);

        drop(graph)
    }

    #[test]
    public fun test_add_relationship_no_max_outdegree() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::none(), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x234, &mut ctx);
        add_relationship(&mut graph, @0x345, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 3, 0);

        drop(graph)
    }

    #[test]
    public fun test_remove_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        remove_relationship(&mut graph, @0x123, &mut ctx);
        assert!(!contains_relationships(&graph, sender(&ctx)), 0);

        drop(graph)
    }

    #[test]
    public fun test_remove_relationship_and_prop() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);

        remove_relationship(&mut graph, @0x123, &mut ctx);
        assert!(!contains_relationships(&graph, sender(&ctx)), 0);
        assert!(!contains_relationship_props<u8, u8>(&graph, sender(&ctx), &mut ctx), 0);

        drop(graph)
    }

    #[test]
    public fun test_remove_relationship2() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(2), &mut ctx);

        add_relationship(&mut graph, @0x012, &mut ctx);
        add_relationship(&mut graph, @0x123, &mut ctx);
        remove_relationship(&mut graph, @0x123, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 1, 0);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_remove_non_exist_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        remove_relationship(&mut graph, @0x123, &mut ctx);

        drop(graph)
    }

    #[test]
    public fun test_clear_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        let ret = clear_relationships(&mut graph, &mut ctx);
        assert!(vec_map::size(&ret) == 1, 0);
        assert!(option::is_none(vec_map::get(&ret, &@0x123)), 0);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    public fun test_clear_two_relationships() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(2), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x234, &mut ctx);
        set_relationship_props(&mut graph, @0x234, 1, &mut ctx);
        let ret = clear_relationships(&mut graph, &mut ctx);
        assert!(vec_map::size(&ret) == 2, 0);
        assert!(option::is_none(vec_map::get(&ret, &@0x123)), 0);
        assert!(option::contains(vec_map::get(&ret, &@0x234), &1), 0);
        assert!(!contains_relationship_props(&graph, @0x234, &mut ctx), 0);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    public fun test_clear_non_exist_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        let ret = clear_relationships(&mut graph, &mut ctx);
        assert!(vec_map::size(&ret) == 0, 0);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    public fun test_set_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        let old_props = set_account_props(&mut graph, 1, &mut ctx);
        assert!(option::is_none(&old_props), 0);
        assert!(*get_account_props(&mut graph, &mut ctx) == 1, 0);

        drop(graph)
    }

    #[test]
    public fun test_set_exist_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        set_account_props(&mut graph, 1, &mut ctx);
        let old_props = set_account_props(&mut graph, 2, &mut ctx);
        assert!(option::contains(&old_props, &1), 0);
        assert!(*get_account_props(&mut graph, &mut ctx) == 2, 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_exist_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        set_account_props(&mut graph, 1, &mut ctx);
        let old_props: Option<u8> = unset_account_props(&mut graph, &mut ctx);
        assert!(option::contains(&old_props, &1), 0);
        assert!(!contains_account_props(&mut graph, &mut ctx), 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_non_exist_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        let old_props: Option<u8> = unset_account_props(&mut graph, &mut ctx);
        assert!(option::is_none(&old_props), 0);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_set_relationship_props_for_non_exist_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);

        drop(graph)
    }

    #[test]
    public fun test_set_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);

        let old_props = set_relationship_props(&mut graph, @0x123, 1, &mut ctx);
        assert!(option::is_none(&old_props), 0);
        assert!(*get_relationship_props(&mut graph, @0x123, &mut ctx) == 1, 0);

        drop(graph)
    }

    #[test]
    public fun test_set_exist_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);

        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);
        let old_props = set_relationship_props(&mut graph, @0x123, 2, &mut ctx);
        assert!(option::contains(&old_props, &1), 0);
        assert!(*get_relationship_props(&mut graph, @0x123, &mut ctx) == 2, 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_exist_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);

        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);
        let old_props = unset_relationship_props(&mut graph, @0x123, &mut ctx);
        assert!(option::contains(&old_props, &1), 0);
        assert!(!contains_relationship_props(&mut graph, @0x123, &mut ctx), 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_non_exist_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new_for_test<u8, u8>(option::some(1), &mut ctx);

        let old_props = unset_relationship_props(&mut graph, @0x123, &mut ctx);
        assert!(option::is_none(&old_props), 0);

        drop(graph)
    }

    #[test]
    public fun tset_empty_props() {
        let ctx = sui::tx_context::dummy();
        drop(new_for_test<EmptyProp, EmptyProp>(option::some(1), &mut ctx));
    }
}

