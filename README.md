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
             --args "beneficiary" "[1]" \
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

testnet package: [0x72d6735d33e031262caaeba202feaf087c4d8d3ebf50265e67e4b710b568b7a5](https://suiexplorer.com/object/0x72d6735d33e031262caaeba202feaf087c4d8d3ebf50265e67e4b710b568b7a5?network=testnet)

testnet example account-graph id: [0x735f56ca17c5359bc6c9cebe97d853199627c44976eae93586225253d725b60c](https://suiexplorer.com/object/0x735f56ca17c5359bc6c9cebe97d853199627c44976eae93586225253d725b60c?network=testnet)
