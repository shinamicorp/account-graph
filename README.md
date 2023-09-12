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
| Package | [0xc5085cb067b266f2312d827d14de58049dc3fff70f15c086aa9f0d54ed3b0848](https://suiexplorer.com/object/0xc5085cb067b266f2312d827d14de58049dc3fff70f15c086aa9f0d54ed3b0848?network=testnet) |
| Example graph | [0x1987692739e70cea40e5f2596eee2ebe00bde830f72bb76a7187a0d6d4cea278](https://suiexplorer.com/object/0x1987692739e70cea40e5f2596eee2ebe00bde830f72bb76a7187a0d6d4cea278?network=testnet) |
| Relationships table | `0x612f13538b12aa6ea30275332756aebe429fee48ece3803f256b22dfdd626c1d` |

### Mainnet

| Resource | Id   |
| -------- | ---- |
| Package | [0x2461e4bcbc7f92d4d838cc6628afd8361d7ebb80eb11d1d4f249134db27a7756](https://suiexplorer.com/object/0x2461e4bcbc7f92d4d838cc6628afd8361d7ebb80eb11d1d4f249134db27a7756) |
| Example graph | [0xda544a6d6fe38d0d83a67209bd0866ab6f3f7f48fd2bee762c3cec811009b835](https://suiexplorer.com/object/0xda544a6d6fe38d0d83a67209bd0866ab6f3f7f48fd2bee762c3cec811009b835) |
| Relationships table | `0xc2b0e1db481f1383ad23b2439819813008f4edd43a2c1fc04891ae28baa340e9` |

#### Beneficiary graph
Graph Id: [0x39fabecb3e74036e6140a938fd1cb194a1affd086004e93c4a76af59d64a2c76](https://suiexplorer.com/object/0x39fabecb3e74036e6140a938fd1cb194a1affd086004e93c4a76af59d64a2c76)

Relationships table: `0x63da13e57687bc5639e0160fbab2d4e1d00bc6b25ecaa44a0624b75b6a9f3776`
