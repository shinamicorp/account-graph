module account_graph::graph {
    use sui::vec_set::{Self, VecSet};
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::dynamic_field as df;

    struct Graph<phantom Node, phantom EdgeLabel> has key, store { id: UID }

    struct Adjacent<Node, EdgeLabel> has store, copy, drop {
        edge: EdgeLabel,
        target: Node,
    }

    public fun new<Node, EdgeLabel>(ctx: &mut TxContext): Graph<Node, EdgeLabel> {
        Graph { id: object::new(ctx) }
    }

    public fun add_node<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        node: Node
    ) {
        df::add(&mut self.id, node, vec_set::empty<Adjacent<Node, EdgeLabel>>());
    }

    public fun add_edge<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        src: Node,
        tar: Node,
        label: EdgeLabel,
    ) {
        let adj = Adjacent {
            target: tar,
            edge: label,
        };
        if (df::exists_(&self.id, src)) {
            let tars: &mut VecSet<Adjacent<Node, EdgeLabel>> = df::borrow_mut(&mut self.id, src);
            vec_set::insert(tars, adj)
        } else {
            df::add(&mut self.id, src, vec_set::singleton(adj));
        }
    }

    public fun remove_edge<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        src: Node,
        tar: Node,
        edge: EdgeLabel,
    ) {
        vec_set::remove(df::borrow_mut(&mut self.id, src), &Adjacent { target: tar, edge: edge });
    }

    public fun remove_node<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        src: Node,
    ) {
        df::remove<Node, Node>(&mut self.id, src);
    }

    public fun src_exists<Node: copy + drop + store, EdgeLabel: drop + copy + store>(
        self: &Graph<Node, EdgeLabel>,
        node: Node,
    ): bool {
        df::exists_(&self.id, node)
    }

    public fun borrow_adjacency_list<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &Graph<Node, EdgeLabel>,
        src: Node,
    ): &VecSet<Adjacent<Node, EdgeLabel>> {
        df::borrow(&self.id, src)
    }

    public fun borrow_adjacent_node<Node, EdgeLabel>(self: &Adjacent<Node, EdgeLabel>): &Node {
        &self.target
    }

    public fun borrow_adjacent_label<Node, EdgeLabel>(self: &Adjacent<Node, EdgeLabel>): &EdgeLabel {
        &self.edge
    }
}
