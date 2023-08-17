# account-graph

`account-graph` is a smart contract in Move language on Sui network.
It captures relationships between accounts using a directed graph, where nodes are addresses and edges are pairs of addresses.
It also provides the ability to store properties of nodes and edges along with the graph.
All graph operations are authorized by the source account.

## build
`sui move build`

## test
`sui move test`

## deploy and interact with `account-graph`
```bash
# deploy
PKG_ID=$(sui client publish . \
             --gas-budget 100000000 \
             --json \
             | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
echo "Package Id: $PKG_ID"

# create a graph
OBJ_ID=$(sui client call \
             --module account_graph \
             --package $PKG_ID \
             --function create \
             --args "[1]" \
             --type-args "$PKG_ID::account_graph::EmptyProp" "$PKG_ID::account_graph::EmptyProp" \
             --gas-budget 100000000 \
             --json \
             | jq -r '.events[0].parsedJson.graph_id' )
echo "Object Id: $OBJ_ID"

# add relationship
TX_DIGEST=$(sui client call \
             --module account_graph \
             --package $PKG_ID \
             --function add_relationship \
             --type-args "$PKG_ID::account_graph::EmptyProp" "$PKG_ID::account_graph::EmptyProp" \
             --args $OBJ_ID $ADDR \
             --gas-budget 100000000 \
             --json \
             | jq -r '.digest')
echo "Tx Digest: $TX_DIGEST"
```

<!-- testnet package id: 0x487033e5fff33ac00ccacfd907dc2537f1baa301a8e0f2143a38d93a5f42c7f8 -->
<!-- testnet account-graph id: 0x769a08c2d29fe6f4f1836cb295dbe64d91192383369de84660a00331e8734693 -->

