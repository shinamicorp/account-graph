module account_graph::beneficiary_link {
    use std::vector;

    use sui::object::{Self, UID};
    use sui::transfer::share_object;
    use sui::tx_context::{TxContext, sender};
    use sui::vec_set;
    use account_graph::graph::{Self, Graph, Adjacent};

    const EBeneficiaryExeed: u64 = 0;
    const EBenefactorExeed: u64 = 1;

    const BENEFICIAL_TO: bool = true;
    const BENEFICIAL_FROM: bool = false;

    struct BeneficiaryLink has key {
        id: UID,
        graph: Graph<address, bool>,
        max_beneficiary: u32,
        max_benefactor: u32,
    }

    public entry fun new(
        max_beneficiary: u32,
        max_benefactor: u32,
        ctx: &mut TxContext,
    ) {
        share_object(
            BeneficiaryLink {
                id: object::new(ctx),
                graph: graph::new(ctx),
                max_beneficiary,
                max_benefactor,
            }
        )
    }

    public entry fun add(
        self: &mut BeneficiaryLink,
        beneficiary: address,
        ctx: &mut TxContext,
    ) {
        let benefactor: address = sender(ctx);

        let beneficiary_count = count_targets(self, benefactor, BENEFICIAL_TO);
        assert!(beneficiary_count < self.max_beneficiary, EBeneficiaryExeed);

        let benefactor_count = count_targets(self, beneficiary, BENEFICIAL_FROM);
        assert!(benefactor_count < self.max_benefactor, EBenefactorExeed);

        graph::add_edge(&mut self.graph, benefactor, beneficiary, BENEFICIAL_TO);
        graph::add_edge(&mut self.graph, beneficiary, benefactor, BENEFICIAL_FROM);
    }

    public entry fun remove(
        self: &mut BeneficiaryLink,
        beneficiary: address,
        ctx: &mut TxContext,
    ) {
        let benefactor: address = sender(ctx);
        graph::remove_edge(&mut self.graph, benefactor, beneficiary, BENEFICIAL_TO);
        graph::remove_edge(&mut self.graph, beneficiary, benefactor, BENEFICIAL_FROM);
    }

    fun count_targets(self: &mut BeneficiaryLink, src: address, edge_label: bool): u32 {
        if (graph::node_exists(&self.graph, src)) {
            count_by_edge_label(
                vec_set::keys(
                    graph::borrow_adjacency_list(&self.graph, src)
                ),
                edge_label
            )
        } else {
            0
        }
    }

    fun count_by_edge_label(edges: &vector<Adjacent<address, bool>>, edge_label: bool): u32 {
        let c = 0;
        let i = 0;
        let size = vector::length(edges);
        while (i <= size) {
            if (*graph::borrow_adjacent_label(vector::borrow(edges, i)) == edge_label) {
                c = c + 1;
            }
        };
        c
    }
}
