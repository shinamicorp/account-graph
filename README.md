# Account graph

`account-graph` is a smart contract in Move language on Sui network.
It captures relationships between accounts using a _directed graph_, where nodes are Sui addresses and edges are pairs of Sui addresses.
It also provides the ability to store properties of nodes and edges along with the graph.
All graph operations are authorized by the source account.

Many account graph instances can be created, each capturing one kind of account relationship, with different properties and constraints.

For information regarding Bullshark Quests integration, see [Bullshark Quests beneficiary graph](#bullshark-quests-beneficiary-graph) and [Deployed resources](#deployed-resources).

## Graph constraints

Currently, the only supported graph constraint is `max_out_degree`, which limits how many outgoing relationships a source account can have.
The constraint is specified during graph instantiation, and enforced during all later graph operations.

## Graph operations

Each account graph instance is a shared Move object, so anyone can interact with it.
However, all graph operations are implicitly performed against the transaction `sender` account.

### Manage relationships

An account can manage its own outgoing relationships in a graph through these move calls:

- `<ACCOUNT_GRAPH_PKG>::account_graph::add_relationship` - adds a relationship from the transaction `sender` account to an arbitrary target account.
- `<ACCOUNT_GRAPH_PKG>::account_graph::remove_relationship` - removes a relationship from the transaction `sender` account to an arbitrary target account.
- `<ACCOUNT_GRAPH_PKG>::account_graph::clear_relationship` - clears all relationships from the transaction `sender` account.

### Manage account properties

An account can optionally manage its own account properties in a graph.
The type of account properties is specified by the graph creator during instantiation.

- `<ACCOUNT_GRAPH_PKG>::account_graph::set_account_props` - sets account properties for the transaction `sender` account.
- `<ACCOUNT_GRAPH_PKG>::account_graph::unset_account_props` - unsets account properties for the transaction `sender` account.

### Manage relationship properties

An account can optionally manage properties of its outgoing relationships in a graph.
The type of relationship properties is specified by the graph creator during instantiation.

- `<ACCOUNT_GRAPH_PKG>::account_graph::set_relationship_props` - sets properties for the relationship from the transaction `sender` account to a target account.
- `<ACCOUNT_GRAPH_PKG>::account_graph::unset_relationship_props` - unsets properties for the relationship from the transaction `sender` account to a target account.

## Bullshark Quests beneficiary graph

The account graph has been adopted by the [Bullshark Quests](https://quests.mystenlabs.com/) as **the official way to link a user's managed in-app wallet to their self-custody wallet.**
This enables applications that leverage managed wallets for their users to participate in Bullshark Quests, while allowing their users' Bullshark NFTs to remain in their self-custody wallets.

This is achieved through the _beneficiary graph_ - an instance of account graph, where each relationship represents a _beneficiary designation_, between the _benefactor_ (managed wallet) and the _beneficiary_ (self-custody wallet).
All user activities happening on the _benefactor_ address are automatically attributed to the _beneficiary_ address.
As an end user who wants to earn Bullshark Quest points from an application, they just need to keep their Bullshark NFT in their self-custody wallet, and designate the self-custody wallet address as the beneficiary of their in-app managed wallet.

Note that in the case of the beneficiary graph, its `max_out_degree` is set to 1, i.e. an account cannot have more than one beneficiary.

### Shinami invisible wallet integration

For applications that use Shinami invisible wallet, there is native support for beneficiary graph, through both [Shinami Invisible Wallet API](https://docs.shinami.com/reference/invisible-wallet-api#shinami_walx_setbeneficiary), and [Shinami TypesScript SDK](https://www.npmjs.com/package/shinami#beneficiary-graph-api).

## Deployed resources

### Sui Mainnet

| Resource                                        | Id                                                                                                                                                                      |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Package                                         | [0x2461e4bcbc7f92d4d838cc6628afd8361d7ebb80eb11d1d4f249134db27a7756](https://suiexplorer.com/object/0x2461e4bcbc7f92d4d838cc6628afd8361d7ebb80eb11d1d4f249134db27a7756) |
| Official beneficiary graph for Bullshark Quests | [0x39fabecb3e74036e6140a938fd1cb194a1affd086004e93c4a76af59d64a2c76](https://suiexplorer.com/object/0x39fabecb3e74036e6140a938fd1cb194a1affd086004e93c4a76af59d64a2c76) |

### Sui Testnet

| Resource                              | Id                                                                                                                                                                                      |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Package                               | [0xc5085cb067b266f2312d827d14de58049dc3fff70f15c086aa9f0d54ed3b0848](https://suiexplorer.com/object/0xc5085cb067b266f2312d827d14de58049dc3fff70f15c086aa9f0d54ed3b0848?network=testnet) |
| Example beneficiary graph for testing | [0x1987692739e70cea40e5f2596eee2ebe00bde830f72bb76a7187a0d6d4cea278](https://suiexplorer.com/object/0x1987692739e70cea40e5f2596eee2ebe00bde830f72bb76a7187a0d6d4cea278?network=testnet) |

## Development

### Build

```
sui move build
```

### Test

```
sui move test
```

### Deploy and interact with an account graph instance

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
