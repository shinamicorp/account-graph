module account_graph::account_graph {
    use std::option::{Self, Option};
    use std::vector;

    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};
    use sui::transfer::{share_object};
    use sui::tx_context::{sender, TxContext};

    const EOutDegreeExceeded: u64 = 0;
    const EZeroOutDegree: u64     = 1;

    /// `AccountGraph` models the relationships between various addresses in a directed graph.
    /// This structure is defined by the following fields:
    struct AccountGraph<phantom AccountProps: copy + drop + store, phantom RelationshipProps: copy + drop + store> has key, store {
        /// A unique identifier (UID) for the graph as a SUI object.
        id: UID,

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

    struct EmptyProp has copy, drop, store {}

    struct RelationshipKey has copy, drop, store {
        source: address,
        target: address,
    }

    fun new<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        max_out_degree: Option<u32>,
        ctx: &mut TxContext,
    ): AccountGraph<AccountProps, RelationshipProps> {
        assert!(option::is_none(&max_out_degree) || *option::borrow(&max_out_degree) != 0, EZeroOutDegree);
        AccountGraph {
            id: object::new(ctx),
            max_out_degree,
            relationships: table::new<address, VecSet<address>>(ctx),
            account_props: table::new<address, AccountProps>(ctx),
            relationship_props: table::new<RelationshipKey, RelationshipProps>(ctx),
        }
    }

    /// Create a `account_graph`.
    public fun create<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        max_out_degree: Option<u32>,
        ctx: &mut TxContext,
    ) {
        let graph = new<AccountProps, RelationshipProps>(max_out_degree, ctx);
        let graph_id = object::id(&graph);
        share_object(graph);
        event::emit(GraphCreated{ graph_id });
    }

    /// Add a relationship as edge, where source is the sender.
    public fun add_relationship<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_list = &mut self.relationships;
        if (table::contains(adj_list, source)) {
            let targets = table::borrow_mut(adj_list, source);
            assert!(
                option::is_none(&self.max_out_degree) ||
                    vec_set::size(targets) < (*option::borrow(&self.max_out_degree) as u64),
                EOutDegreeExceeded
            );
            vec_set::insert(targets, target)
        } else {
            table::add(adj_list, source, vec_set::singleton(target))
        };
        event::emit(RelationshipAdded{ graph_id: object::id(self), source, target })
    }

    /// Remove a relationship as edge, where source is the sender,
    /// fail if node doesn't exist.
    /// If `remove_empty_vec` is `true`, the adjaceny list will be removed when it is empty.
    public fun remove_relationship<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        remove_empty_vec: bool,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_list = table::borrow_mut(&mut self.relationships, source);
        vec_set::remove(adj_list, &target);
        if (remove_empty_vec && vec_set::size(adj_list) == 0) {
            table::remove(&mut self.relationships, source);
        };
        unset_relationship_props(self, target, ctx);
        event::emit(RelationshipRemoved{ graph_id: object::id(self), source, target })
    }

    /// Remove all relationships of the sender,
    /// fail if node doesn't exist
    public fun clear_relationships<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_list = &mut self.relationships;
        if (!table::contains(adj_list, source)) return;
        let targets = table::remove(adj_list, source);
        let graph_id = object::id(self);
        let size = vec_set::size(&targets);
        let i = 0u64;
        while (i < size) {
            event::emit(
                RelationshipRemoved {
                    graph_id,
                    source,
                    target: *vector::borrow(vec_set::keys(&targets), i)
                }
            );
            i = i + 1;
        }
    }

    /// Set properties for the sender account,
    /// previous value is overwritten if exists
    public fun set_account_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        props: AccountProps,
        ctx: &mut TxContext,
    ) {
        let node = sender(ctx);
        let account_props = &mut self.account_props;
        if (table::contains(account_props, node)) {
            *table::borrow_mut(account_props, node) = props;
        } else {
            table::add(account_props, node, props);
        };
        event::emit(AccountPropsSet { graph_id: object::id(self), node, props, });
    }

    /// Unset properties for the sender account,
    /// fail if node doesn't exist
    public fun unset_account_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ) {
        let node = sender(ctx);
        let account_props = &mut self.account_props;
        if (table::contains(account_props, node)) {
            let props = table::remove(account_props, node);
            event::emit(AccountPropsUnset { graph_id: object::id(self), node, props })
        }
    }

    /// Set property for a relationship, where sender is the source,
    /// previous value is overwritten if exists
    public fun set_relationship_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        props: RelationshipProps,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let rel_props = &mut self.relationship_props;
        let rel_key = RelationshipKey { source, target };
        if (table::contains(rel_props, rel_key)) {
            *table::borrow_mut(rel_props, rel_key) = props;
        } else {
            table::add(rel_props, rel_key, props);
        };
        event::emit(RelationshipPropsSet{ graph_id: object::id(self), source, target, props })
    }

    /// Unset property for a relationship, where sender is the source,
    /// fail if node doesn't exist
    public fun unset_relationship_props<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let rel_props = &mut self.relationship_props;
        let key = RelationshipKey { source, target };
        if (table::contains(rel_props, key)) {
            let props = table::remove(rel_props, key);
            event::emit(RelationshipPropsUnset{ graph_id: object::id(self), source, target, props })
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
        let adj_list = &self.relationships;
        if (table::contains(adj_list, source)) {
            vec_set::size(table::borrow(adj_list, source))
        } else {
            0
        }
    }

    #[test_only]
    fun has_targets<AccountProps: copy + drop + store, RelationshipProps: copy + drop + store>(
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


    #[test]
    public fun test_create_graph() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);
        drop(graph);
    }

    #[test]
    #[expected_failure]
    public fun test_create_graph_zero_out_degree() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(0), &mut ctx);
        drop(graph);
    }

    #[test]
    public fun test_create_graph_none_out_degree() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::none(), &mut ctx);
        drop(graph);
    }

    #[test]
    public fun test_add_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 1, 0);

        drop(graph)
    }

    #[test]
    public fun test_add_2_relationships() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(2), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x234, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 2, 0);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_add_same_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x123, &mut ctx);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_add_exceeded_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x456, &mut ctx);

        drop(graph)
    }

    #[test]
    public fun test_remove_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        remove_relationship(&mut graph, @0x123, false, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    public fun test_remove_relationship_and_prop() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);

        remove_relationship(&mut graph, @0x123, false, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);
        assert!(!contains_relationship_props<u8, u8>(&graph, sender(&ctx), &mut ctx), 0);

        drop(graph)
    }

    #[test]
    public fun test_remove_and_clear_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        remove_relationship(&mut graph, @0x123, true, &mut ctx);
        assert!(!has_targets(&graph, sender(&ctx)), 0);

        drop(graph)
    }

    #[test]
    public fun test_remove_and_clear_relationship2() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(2), &mut ctx);

        add_relationship(&mut graph, @0x012, &mut ctx);
        add_relationship(&mut graph, @0x123, &mut ctx);
        remove_relationship(&mut graph, @0x123, true, &mut ctx);
        assert!(has_targets(&graph, sender(&ctx)), 0);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_remove_non_exist_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        remove_relationship(&mut graph, @0x123, false, &mut ctx);

        drop(graph)
    }

    #[test]
    public fun test_clear_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        clear_relationships(&mut graph, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    public fun test_clear_two_relationships() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(2), &mut ctx);

        add_relationship(&mut graph, @0x123, &mut ctx);
        add_relationship(&mut graph, @0x234, &mut ctx);
        clear_relationships(&mut graph, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    public fun test_clear_non_exist_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        clear_relationships(&mut graph, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    public fun test_set_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        set_account_props(&mut graph, 1, &mut ctx);
        assert!(*get_account_props(&mut graph, &mut ctx) == 1, 0);

        drop(graph)
    }

    #[test]
    public fun test_set_exist_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        set_account_props(&mut graph, 1, &mut ctx);
        set_account_props(&mut graph, 2, &mut ctx);
        assert!(*get_account_props(&mut graph, &mut ctx) == 2, 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_exist_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        set_account_props(&mut graph, 1, &mut ctx);
        unset_account_props(&mut graph, &mut ctx);

        assert!(!contains_account_props(&mut graph, &mut ctx), 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_non_exist_account_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        unset_account_props(&mut graph, &mut ctx);

        drop(graph)
    }


    #[test]
    public fun test_set_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);
        assert!(*get_relationship_props(&mut graph, @0x123, &mut ctx) == 1, 0);

        drop(graph)
    }

    #[test]
    public fun test_set_exist_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);
        set_relationship_props(&mut graph, @0x123, 2, &mut ctx);
        assert!(*get_relationship_props(&mut graph, @0x123, &mut ctx) == 2, 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_exist_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        set_relationship_props(&mut graph, @0x123, 1, &mut ctx);
        unset_relationship_props(&mut graph, @0x123, &mut ctx);

        assert!(!contains_relationship_props(&mut graph, @0x123, &mut ctx), 0);

        drop(graph)
    }

    #[test]
    public fun test_unset_non_exist_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        unset_relationship_props(&mut graph, @0x123, &mut ctx);

        drop(graph)
    }
}

