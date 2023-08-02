module account_graph::graph {
    use sui::vec_set::{Self, VecSet};
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::dynamic_field as df;

    const ENodeHasIncoming: u64 = 0;
    const ENodeHasOutgoing: u64 = 0;

    struct Graph<phantom Node, phantom EdgeLabel> has key, store { id: UID }

    struct Adjacent<Node, EdgeLabel> has copy, drop, store {
        edge: EdgeLabel,
        target: Node,
    }

    struct NodeData<Node: copy + drop, EdgeLabel: copy + drop> has drop, store {
        adjacency_list: VecSet<Adjacent<Node, EdgeLabel>>,
        incoming: u128,
    }

    fun inc_incoming<Node: copy + drop, EdgeLabel: copy + drop>(self: &mut NodeData<Node, EdgeLabel>) {
        self.incoming = self.incoming + 1;
    }

    fun dec_incoming<Node: copy + drop, EdgeLabel: copy + drop>(self: &mut NodeData<Node, EdgeLabel>) {
        self.incoming = self.incoming - 1;
    }

    fun borrow_node_data_mut<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        node: Node
    ): &mut NodeData<Node, EdgeLabel> {
        df::borrow_mut<Node, NodeData<Node, EdgeLabel>>(&mut self.id, node)
    }

    fun borrow_node_data<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &Graph<Node, EdgeLabel>,
        node: Node
    ): &NodeData<Node, EdgeLabel> {
        df::borrow<Node, NodeData<Node, EdgeLabel>>(&self.id, node)
    }

    public fun new<Node, EdgeLabel>(ctx: &mut TxContext): Graph<Node, EdgeLabel> {
        Graph { id: object::new(ctx) }
    }

    public fun add_node<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        node: Node
    ) {
        let node_data: NodeData<Node, EdgeLabel> = NodeData {
            adjacency_list: vec_set::empty<Adjacent<Node, EdgeLabel>>(),
            incoming: 0,
        };
        df::add(&mut self.id, node, node_data);
    }

    public fun add_edge<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        src: Node,
        tar: Node,
        label: EdgeLabel,
    ) {
        if (!df::exists_(&self.id, src)) { add_node(self, src) };

        if (!df::exists_(&self.id, tar)) { add_node(self, tar) };

        let adjacency_list: &mut VecSet<Adjacent<Node, EdgeLabel>> = &mut borrow_node_data_mut(self, src).adjacency_list;
        let adj = Adjacent { target: tar, edge: label };

        if (vec_set::contains(adjacency_list, &adj)) { return };

        vec_set::insert(adjacency_list, adj);
        inc_incoming(borrow_node_data_mut(self, tar));
    }


    public fun remove_edge<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        src: Node,
        tar: Node,
        label: EdgeLabel,
    ) {
        let adjacency_list: &mut VecSet<Adjacent<Node, EdgeLabel>> = &mut borrow_node_data_mut(self, src).adjacency_list;
        let adj = Adjacent { target: tar, edge: label };

        if (!vec_set::contains(adjacency_list, &adj)) { return };

        vec_set::remove(adjacency_list, &adj);
        dec_incoming(borrow_node_data_mut(self, tar));
    }

    public fun remove_node<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &mut Graph<Node, EdgeLabel>,
        node: Node,
    ) {
        let data = borrow_node_data(self, node);

        assert!(data.incoming == 0, ENodeHasIncoming);
        assert!(vec_set::size(&data.adjacency_list) == 0, ENodeHasOutgoing);

        df::remove<Node, Node>(&mut self.id, node);
    }

    public fun node_exists<Node: copy + drop + store, EdgeLabel: drop + copy + store>(
        self: &Graph<Node, EdgeLabel>,
        node: Node,
    ): bool {
        df::exists_(&self.id, node)
    }

    public fun node_incoming_count<Node: copy + drop + store, EdgeLabel: drop + copy + store>(
        self: &Graph<Node, EdgeLabel>,
        node: Node,
    ): u128 {
        borrow_node_data(self, node).incoming
    }

    public fun borrow_adjacency_list<Node: drop + copy + store, EdgeLabel: drop + copy + store>(
        self: &Graph<Node, EdgeLabel>,
        node: Node,
    ): &VecSet<Adjacent<Node, EdgeLabel>> {
        &borrow_node_data(self, node).adjacency_list
    }

    public fun borrow_adjacent_node<Node, EdgeLabel>(self: &Adjacent<Node, EdgeLabel>): &Node {
        &self.target
    }

    public fun borrow_adjacent_label<Node, EdgeLabel>(self: &Adjacent<Node, EdgeLabel>): &EdgeLabel {
        &self.edge
    }
}
