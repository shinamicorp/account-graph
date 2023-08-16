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
PKD_ID=$(sui client publish . \
             --gas-budget 100000000 \
             --json \
             | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
echo "Package Id: $PKD_ID"

# create a graph
OBJ_ID=$(sui client call \
             --module account_graph \
             --package $PKD_ID \
             --function create \
             --args "1" \
             --type-args "u8" "u8" \
             --gas-budget 100000000 \
             --json \
             | jq -r '.objectChanges[] | select(.type=="created") | .objectId')
echo "Object Id: $OBJ_ID"

# add relationship
DIGEST=$(sui client call \
             --module account_graph \
             --package $PKD_ID \
             --function add_relationship \
             --type-args "u8" "u8" \
             --args $OBJ_ID $ADDR \
             --gas-budget 100000000 \
             --json \
             | jq -r '.digest')
echo "Digest: $DIGEST"

# set account property
# DIGEST=$(sui client call \
#              --module account_graph \
#              --package $PKD_ID \
#              --function test \
#              --type-args "u8" \
#              --args 1 \
#              --gas-budget 100000000 \
#              --json \
#              | jq -r '.objectChanges[] | select(.type=="created") | .digest')
# echo "Digest: $DIGEST"
```

<!-- testnet package id: 0xc86faa1dcf4928b6456c409cdc5183884bba5f158d16e801d6154417984f5df2 -->

