# account-graph

`account-graph` is a smart contract in Move language on Sui network.
It captures relationships between accounts using a directed graph, where nodes are addresses and edges are pairs of addresses.
It also provides the ability to store properties of nodes and edges along with the graph.
All graph operations are authorized by the source account.

## Build
`sui move build`

## Test
`sui move test`

## Deploy and interact with `account-graph`
```bash
# deploy
PKG_ID=$(sui client publish . \
  --gas-budget 100000000 \
  --json \
  | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
echo "Package Id: $PKG_ID"

# create a graph
GRAPH_ID=$(sui client call \
  --module account_graph \
  --package $PKG_ID \
  --function create \
  --args "beneficiary" "[1]" \
  --type-args "$PKG_ID::account_graph::EmptyProp" "$PKG_ID::account_graph::EmptyProp" \
  --gas-budget 100000000 \
  --json \
  | jq -r '.events[0].parsedJson.graph_id' )
echo "Graph Id: $GRAPH_ID"

# add a relationship from my address to TARGET_ADDRESS
TX_DIGEST=$(sui client call \
  --module account_graph \
  --package $PKG_ID \
  --function add_relationship \
  --type-args "$PKG_ID::account_graph::EmptyProp" "$PKG_ID::account_graph::EmptyProp" \
  --args $GRAPH_ID $TARGET_ADDRESS \
  --gas-budget 100000000 \
  --json \
  | jq -r '.digest')
echo "Tx Digest: $TX_DIGEST"

# get relationships table id
REL_TBL_ID=$(sui client object \
  --json \
  $GRAPH_ID \
  | jq -r .content.fields.relationships.fields.id.id)
echo "Relationships Table Id: $REL_TBL_ID"

# query relationships table
sui client dynamic-field $REL_TBL_ID

# get one entry from relationships table
REL_FIELD_ID=$(sui client dynamic-field \
  --json \
  $REL_TBL_ID \
  | jq -r '.data[0].objectId')
echo "Relationships Field Id: $REL_FIELD_ID"

# get source and target addresses
sui client object \
  --json \
  $REL_FIELD_ID \
  | jq -r '{"source": .content.fields.name, "targets": .content.fields.value.fields.contents}'
```

## Deployed resources

### Testnet

| Resource | Id   |
| -------- | ---- |
| Package | [0x72d6735d33e031262caaeba202feaf087c4d8d3ebf50265e67e4b710b568b7a5](https://suiexplorer.com/object/0x72d6735d33e031262caaeba202feaf087c4d8d3ebf50265e67e4b710b568b7a5?network=testnet) |
| Example graph | [0x735f56ca17c5359bc6c9cebe97d853199627c44976eae93586225253d725b60c](https://suiexplorer.com/object/0x735f56ca17c5359bc6c9cebe97d853199627c44976eae93586225253d725b60c?network=testnet) |
| Relationships table | `0x346b1a1c18bc78d91dd38679910e87cdf94e8517fc2ab2320076e20df8951785` |

### Mainnet

TODO
