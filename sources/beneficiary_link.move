module account_graph::beneficiary_link {
    use std::vector;

    use sui::object::{Self, UID};
    use sui::transfer::share_object;
    use sui::tx_context::{TxContext, sender};
    use sui::vec_set;
    use account_graph::graph::{Self, Graph, Adjacent};

    const EBeneficiaryExeed: u64 = 0;
    const EBenefactorExeed: u64 = 1;

    const BENEFICIAL_TO: u8 = 0;
    const BENEFICIAL_FROM: u8 = 1;

    // TODO: this is the relation btw Beneficiary and Benefactor,
    // what's the better word? fiduciary or trust?
    struct Beneficial has drop, store, copy {
        domain: vector<u8>,
        kind: u8,
    }

    struct BeneficiaryLink has key {
        id: UID,
        graph: Graph<address, Beneficial>,
        max_benefactor_per_domain: u32,
        max_beneficiary_per_domain: u32,
    }

    public entry fun new(
        max_benefactor_per_domain: u32,
        max_beneficiary_per_domain: u32,
        ctx: &mut TxContext,
    ) {
        share_object(
            BeneficiaryLink {
                id: object::new(ctx),
                graph: graph::new(ctx),
                max_benefactor_per_domain,
                max_beneficiary_per_domain,
            }
        )
    }

    public entry fun add(
        self: &mut BeneficiaryLink,
        beneficiary: address,
        domain: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let benefactor: address = sender(ctx);

        let beneficial_to = Beneficial {
            kind: BENEFICIAL_TO,
            domain,
        };

        let beneficiary_count = count_targets_by_domain(self, benefactor, &beneficial_to);
        assert!(beneficiary_count < self.max_beneficiary_per_domain, EBeneficiaryExeed);

        let beneficial_from = Beneficial {
            kind: BENEFICIAL_FROM,
            domain,
        };

        let benefactor_count = count_targets_by_domain(self, beneficiary, &beneficial_from);
        assert!(benefactor_count < self.max_benefactor_per_domain, EBenefactorExeed);

        graph::add_edge(&mut self.graph, benefactor, beneficiary, beneficial_to);
        graph::add_edge(&mut self.graph, beneficiary, benefactor, beneficial_from);
    }

    public entry fun remove(
        self: &mut BeneficiaryLink,
        beneficiary: address,
        domain: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let benefactor: address = sender(ctx);
        let beneficial_to = Beneficial {
            kind: BENEFICIAL_TO,
            domain,
        };
        let beneficial_from = Beneficial {
            kind: BENEFICIAL_FROM,
            domain,
        };

        graph::remove_edge(&mut self.graph, benefactor, beneficiary, beneficial_to);
        graph::remove_edge(&mut self.graph, beneficiary, benefactor, beneficial_from);
    }

    fun count_targets_by_domain(self: &mut BeneficiaryLink, src: address, beneficiary: &Beneficial): u32 {
        if (graph::src_exists(&self.graph, src)) {
            count_by_domain(
                vec_set::keys(
                    graph::borrow_adjacency_list(&self.graph, src)
                ),
                beneficiary
            )
        } else {
            0
        }
    }

    fun count_by_domain(edges: &vector<Adjacent<address, Beneficial>>, beneficiary: &Beneficial): u32 {
        let c = 0;
        let i = 0;
        let size = vector::length(edges);
        while (i <= size) {
            if (graph::borrow_adjacent_label(vector::borrow(edges, i)) == beneficiary) {
                c = c + 1;
            }
        };
        c
    }
}
