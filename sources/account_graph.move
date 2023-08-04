module account_graph::account_graph {
    use sui::object::{Self, UID};
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};
    use sui::transfer::share_object;
    use sui::tx_context::{sender, TxContext};

    const EOutDegreeExceed: u64 = 0;

    struct AccountGraph<phantom AccountProps: drop + store, phantom RelationshipProps: drop + store> has key, store {
        id: UID,
        max_out_degree: u32,
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

    public entry fun new<AccountProps: drop + store, RelationshipProps: drop + store>(
        max_out_degree: u32,
        ctx: &mut TxContext,
    ) {
        share_object(
            AccountGraph {
                id: object::new(ctx),
                max_out_degree,
                relationships: table::new<address, AccountRelationships>(ctx),
                account_props: table::new<address, AccountProps>(ctx),
                relationship_props: table::new<RelationshipKey, RelationshipProps>(ctx),
            }
        );
    }

    public entry fun add_relationship<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_list = &mut self.relationships;
        if (table::contains(adj_list, source)) {
            let targets = &mut table::borrow_mut(adj_list, source).targets;
            assert!(vec_set::size(targets) < (self.max_out_degree as u64), EOutDegreeExceed);
            vec_set::insert(targets, target)
        } else {
            table::add(adj_list, source, AccountRelationships{ targets: vec_set::singleton(target) })
        }
    }

    public entry fun remove_relationship<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let adj_list = &mut self.relationships;
        vec_set::remove(&mut table::borrow_mut(adj_list, source).targets, &target);
    }

    public fun clear_relationships<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ) {
        let node = sender(ctx);
        let adj_list = &mut self.relationships;
        table::remove(adj_list, node);
    }

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
        }
    }

    public entry fun unset_account_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        ctx: &mut TxContext,
    ) {
        let node = sender(ctx);
        let account_props = &mut self.account_props;
        table::remove(account_props, node);
    }

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
        }
    }

    public entry fun unset_relationship_props<AccountProps: drop + store, RelationshipProps: drop + store>(
        self: &mut AccountGraph<AccountProps, RelationshipProps>,
        target: address,
        ctx: &mut TxContext,
    ) {
        let source = sender(ctx);
        let rel_props = &mut self.relationship_props;
        table::remove(rel_props, RelationshipKey { source, target });
    }
}
