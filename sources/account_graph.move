module account_graph::account_graph {
    use std::option::{Self, Option};

    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};
    use sui::transfer::share_object;
    use sui::tx_context::{sender, TxContext};

    const EOutDegreeExceeded: u64 = 0;
    const EZeroOutDegree: u64     = 1;

    struct AccountGraph<phantom AccountProps: drop + store, phantom RelationshipProps: drop + store> has key, store {
        id: UID,
        max_out_degree: Option<u32>,
        relationships: Table<address, AccountRelationships>,
        account_props: Table<address, AccountProps>,
        relationship_props: Table<RelationshipKey, RelationshipProps>,
    }

    struct AccountRelationships has drop, store {
        targets: VecSet<address>,
    }

    struct RelationshipKey has copy, drop, store {
        source: address,
        target: address,
    }

    fun new<AccountProps: drop + store, RelationshipProps: drop + store>(
        max_out_degree: Option<u32>,
        ctx: &mut TxContext,
    ): AccountGraph<AccountProps, RelationshipProps> {
        assert!(option::is_none(&max_out_degree) || *option::borrow(&max_out_degree) != 0, EZeroOutDegree);
        AccountGraph {
            id: object::new(ctx),
            max_out_degree,
            relationships: table::new<address, AccountRelationships>(ctx),
            account_props: table::new<address, AccountProps>(ctx),
            relationship_props: table::new<RelationshipKey, RelationshipProps>(ctx),
        }
    }

    /// Create a `account_graph`.
    public entry fun create<AccountProps: drop + store, RelationshipProps: drop + store>(
        max_out_degree: Option<u32>,
        ctx: &mut TxContext,
    ) {
        let graph = new<AccountProps, RelationshipProps>(max_out_degree, ctx);
        let graph_id = object::id(&graph);
        share_object(graph);
        event::emit(GraphCreated{ graph_id });
    }

    /// Add a relationship as edge, where source is sender.
    public entry fun add_relationship<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_list = &mut self.relationships;
        if (table::contains(adj_list, source)) {
            let targets = &mut table::borrow_mut(adj_list, source).targets;
            assert!(option::is_none(&self.max_out_degree) ||  vec_set::size(targets) < (*option::borrow(&self.max_out_degree) as u64), EOutDegreeExceeded);
            vec_set::insert(targets, target)
        } else {
            table::add(adj_list, source, AccountRelationships{ targets: vec_set::singleton(target) })
        };
        event::emit(RelationshipAdded{ source, target })
    }

    /// Remove a relationship as edge, where source is sender,
    /// fail if node doesn't exist.
    public entry fun remove_relationship<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_list = &mut self.relationships;
        vec_set::remove(&mut table::borrow_mut(adj_list, source).targets, &target);
        event::emit(RelationshipRemoved{ source, target })
    }

    /// Remove all relationships of sender,
    /// fail if node doesn't exist
    public fun clear_relationships<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ) {
        let node = sender(ctx);
        let adj_list = &mut self.relationships;
        table::remove(adj_list, node);
        event::emit(RelationshipsCleared{ node })
    }

    /// Set property for account node, where sender is the node,
    /// previous value is overwritten if exists
    public entry fun set_account_props<AccountProps: drop + store, RelationshipProps: drop + store>(
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
        event::emit(AccountPropsSet { account: node });
    }

    /// Unset property for account node, where sender is the node,
    /// fail if node doesn't exist
    public entry fun unset_account_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ) {
        let node = sender(ctx);
        let account_props = &mut self.account_props;
        table::remove(account_props, node);
        event::emit(AccountPropsUnset { account: node })
    }

    /// Set property for a relationship, where sender is the source,
    /// previous value is overwritten if exists
    public entry fun set_relationship_props<AccountProps: drop + store, RelationshipProps: drop + store>(
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
        event::emit(RelationshipPropsSet{ source, target })
    }

    /// Unset property for a relationship, where sender is the source,
    /// fail if node doesn't exist
    public entry fun unset_relationship_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let rel_props = &mut self.relationship_props;
        table::remove(rel_props, RelationshipKey { source, target });
        event::emit(RelationshipPropsUnset{ source, target })
    }

    // === Events ===

    struct GraphCreated has copy, drop {
        graph_id: ID,
    }

    struct RelationshipAdded has copy, drop {
        source: address,
        target: address,
    }

    struct RelationshipRemoved has copy, drop {
        source: address,
        target: address,
    }

    struct RelationshipsCleared has copy, drop {
        node: address
    }

    struct AccountPropsSet has copy, drop {
        account: address,
    }

    struct AccountPropsUnset has copy, drop {
        account: address,
    }

    struct RelationshipPropsSet has copy, drop {
        source: address,
        target: address,
    }

    struct RelationshipPropsUnset has copy, drop {
        source: address,
        target: address,
    }

    // === Unit tests ===

    #[test_only]
    fun drop<AccountProps: drop + store, RelationshipProps: drop + store>(
        graph: AccountGraph<AccountProps, RelationshipProps>,
    ) {
        use sui::object::delete;

        let AccountGraph {
            id,
            max_out_degree: _,
            relationships,
            account_props,
            relationship_props,
        } = graph;
        delete(id);
        table::drop(relationships);
        table::drop(account_props);
        table::drop(relationship_props);
    }

    #[test_only]
    fun create_graph<AccountProps: drop + store, RelationshipProps: drop + store>(
        max_out_degree: option::Option<u32>,
    ): AccountGraph<AccountProps, RelationshipProps> {
        let ctx = sui::tx_context::dummy();
        new<AccountProps, RelationshipProps>(max_out_degree, &mut ctx)
    }

    #[test_only]
    fun target_count<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        source: address,
    ): u64 {
        let adj_list = &self.relationships;
        if (table::contains(adj_list, source)) {
            vec_set::size(&table::borrow(adj_list, source).targets)
        } else {
            0
        }
    }

    #[test_only]
    fun get_account_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ): &AccountProps {
        table::borrow(&self.account_props, sender(ctx))
    }

    #[test_only]
    fun contains_account_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ): bool {
        table::contains(&self.account_props, sender(ctx))
    }

    #[test_only]
    fun get_relationship_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ): &RelationshipProps {
        table::borrow(&self.relationship_props, RelationshipKey{ source: sender(ctx), target})
    }

    #[test_only]
    fun contains_relationship_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ): bool {
        table::contains(&self.relationship_props, RelationshipKey{ source: sender(ctx), target})
    }


    #[test]
    public fun test_create_graph() {
        drop(create_graph<u8, u8>(option::some(1)));
    }

    #[test]
    #[expected_failure]
    public fun test_create_graph_zero_out_degree() {
        drop(create_graph<u8, u8>(option::some(0)));
    }

    #[test]
    public fun test_create_graph_none_out_degree() {
        drop(create_graph<u8, u8>(option::none()));
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
        remove_relationship(&mut graph, @0x123, &mut ctx);
        assert!(target_count(&graph, sender(&ctx)) == 0, 0);

        drop(graph)
    }

    #[test]
    #[expected_failure]
    public fun test_remove_non_exist_relationship() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        remove_relationship(&mut graph, @0x123, &mut ctx);

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
    #[expected_failure]
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
    #[expected_failure]
    public fun test_unset_non_exist_relationship_props() {
        let ctx = sui::tx_context::dummy();
        let graph = new<u8, u8>(option::some(1), &mut ctx);

        unset_relationship_props(&mut graph, @0x123, &mut ctx);

        drop(graph)
    }
}

