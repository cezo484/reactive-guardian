# Guardian

Guardian is a set-and-forget stop-loss and take-profit watcher built on
Reactive Network. You register a rule, such as "if ETH drops below
$3,500, act", and a reactive contract watches the price for you. When
the threshold crosses, the contract records the trigger and asks
Reactive Network to deliver a callback to a contract on the destination
chain. Nothing runs off chain after setup.

This is an entry for the Reactive Omni Buildathon, track "Set It and
Forget It".

## How it works

1. Deploy Guardian on Reactive Lasna. Deploy GuardianAction and
   PriceBeacon on Sepolia.
2. Register a rule on Guardian: a price feed, a threshold, a direction
   (below for a stop-loss, above for a take-profit), and a callback
   target. Guardian subscribes to the feed through the Reactive system
   contract.
3. The feed emits a price event. On Sepolia that is either a Chainlink
   aggregator update or a PriceBeacon publish.
4. The system contract calls Guardian's react() with the log. Guardian
   decodes the price and checks every active rule on that feed.
5. A rule that just crossed its threshold fires. Guardian emits
   RuleTriggered and requests a callback to GuardianAction on Sepolia,
   which records the execution on chain.

## Rule semantics

A rule fires on the edge. The first observation past the threshold
triggers it. While the price stays past the threshold, the rule stays
quiet, so a flood of low prices produces one trigger, not one per
update. A repeat rule re-arms when the price comes back inside the
range. A one-shot rule deactivates after its first trigger and
unsubscribes when it was the last rule on its feed. A price exactly at
the threshold counts as inside the range.

Rules can be alert only: register with a zero callback target and the
trigger is recorded without a callback. A rule can be removed by its
owner at any time.

## Layout

    src/Guardian.sol        Reactive contract on Lasna
    src/GuardianAction.sol  Callback receiver on Sepolia
    src/PriceBeacon.sol     Demo price publisher on Sepolia
    script/                 Foundry deploy scripts
    js/rules.js             Rule logic, mirroring the contract
    js/simulator.js         Price series replay
    js/cli.js               Demo and rule commands
    test/                   Foundry tests (.t.sol) and Node tests (.test.js)
    lib/                    Vendored dependencies (reactive-lib-omni, forge-std)

## Quick start

Node 18 or newer, no dependencies. Foundry for the contract side.

    npm test          # Node test suite (19 tests)
    npm run demo      # replay a canned ETH price series, print the trigger log
    forge test        # Foundry test suite (21 tests)

If `forge` on your machine resolves to another tool, call the Foundry
binary by its full path.

## CLI

    node js/cli.js demo
      Run the demo series. ETH drifts down through a $3,500 stop-loss,
      recovers, then climbs through a $3,800 take-profit twice.

    node js/cli.js check --token ETH --below 3500 --price 3490
      Build a rule and check it against one price. Use --above for a
      take-profit, --oneshot for a one-shot rule, and
      --prices 3600,3490,3510 for a series.

    node js/cli.js rule --token ETH --below 3500 --oneshot --action 0x...
      Print the rule and the cast command that registers it on Lasna.
      Defaults to the Chainlink ETH/USD feed on Sepolia. Use
      --beacon 0x... with --token-address 0x... for a PriceBeacon feed.

## Deploy to Lasna

Status: the contracts are written and tested. They are not deployed
yet. Deployment needs Sepolia ETH, which comes from a faucet that asks
for a sign-in, so this step runs on your machine. The commands below
are the full sequence.

### 0. A fresh testnet key

Make a key that is only ever used on testnets. Never use a key that
holds real funds.

    cast wallet new

Put the private key in `.env` (mode 600, gitignored):

    PRIVATE_KEY=0x...
    LASNA_RPC=https://lasna-rpc.rnk.dev
    SEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com

Load it into your shell for the commands below:

    set -a; source .env; set +a

### 1. Sepolia ETH

Get Sepolia ETH from a faucet, for example the Google Cloud Web3
faucet or the Alchemy Sepolia faucet. 0.2 ETH covers the whole loop:
0.1 ETH buys lREACT, the rest pays Sepolia gas and funds the callback
receiver.

### 2. lREACT

Send Sepolia ETH to the Lasna faucet contract. 0.1 ETH returns
10 lREACT.

    cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 \
      --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY \
      "request(address)" $(cast wallet address --private-key $PRIVATE_KEY) \
      --value 0.1ether

Check the balance on Lasna:

    cast balance $(cast wallet address --private-key $PRIVATE_KEY) \
      --rpc-url $LASNA_RPC

### 3. Deploy Guardian to Lasna

    forge script script/DeployGuardian.s.sol \
      --rpc-url $LASNA_RPC --broadcast --chain-id 5318007

Record the Guardian address and the deployment transaction hash. Save
the address in `.env` as GUARDIAN_ADDRESS and reload it.

### 4. Deploy the Sepolia side

    forge script script/DeploySepolia.s.sol \
      --rpc-url $SEPOLIA_RPC --broadcast --chain-id 11155111

Record the PriceBeacon and GuardianAction addresses and their
transaction hashes. Save them in `.env` as BEACON_ADDRESS and
ACTION_ADDRESS and reload it.

### 5. Register a rule

This rule watches the beacon and fires once when the price drops
below $3,500. The token is the zero address, which matches any token
published on the beacon.

    cast send $GUARDIAN_ADDRESS --rpc-url $LASNA_RPC \
      --private-key $PRIVATE_KEY \
      "createRule(uint256,address,uint256,address,int256,uint8,bool,uint256,address)" \
      11155111 $BEACON_ADDRESS \
      0x0d86730737b142fc160892fa8a0f2db687a92a0e294d1ad70624cf5acef03b84 \
      0x0000000000000000000000000000000000000000 \
      350000000000 0 true 11155111 $ACTION_ADDRESS

The `rule` CLI command prints this command for any threshold:

    node js/cli.js rule --token ETH --below 3500 --oneshot \
      --beacon $BEACON_ADDRESS --action $ACTION_ADDRESS

To watch the live market instead of the beacon, use the Chainlink
ETH/USD feed on Sepolia (0x694AA1769357215DE4FAC081bf1f309aDC325306)
with topic
0x0559884fd3a460db3073b7fc896cc77986f16e378210ded43186175bf646fc5f.

### 6. Show the full loop

Publish a price below the threshold from Sepolia:

    cast send $BEACON_ADDRESS --rpc-url $SEPOLIA_RPC \
      --private-key $PRIVATE_KEY \
      "publish(address,uint256)" \
      0x0000000000000000000000000000000000000000 349000000000

Then watch three transactions:

- The publish transaction on Sepolia (the origin event).
- The reactive transaction on Lasna, visible on the Guardian contract
  page at https://lasna.reactscan.net, showing the RuleTriggered log.
- The callback transaction on Sepolia, calling GuardianAction.

Confirm the callback landed:

    cast call $ACTION_ADDRESS --rpc-url $SEPOLIA_RPC \
      "totalExecutions()(uint256)"

It should read 1. Save all three transaction hashes for the
submission.

### 7. Verify the contracts (optional)

    forge verify-contract --verifier sourcify --chain-id 5318007 \
      $GUARDIAN_ADDRESS src/Guardian.sol:Guardian

    forge verify-contract --verifier sourcify --chain-id 11155111 \
      $ACTION_ADDRESS src/GuardianAction.sol:GuardianAction

## Funding

Guardian pays for reactive transactions in lREACT and GuardianAction
pays for callback delivery in Sepolia ETH. Both are funded at
deployment (0.01 each). Top either up with a plain transfer to its
address, then call coverDebt() if it ever goes quiet. A contract in
debt receives nothing until the debt clears.

## Addresses

    Reactive Lasna RPC:     https://lasna-rpc.rnk.dev (chain 5318007)
    Lasna explorer:         https://lasna.reactscan.net
    System contract:        0x8888888888888888888888888888888888888888
    Sepolia RPC:            https://ethereum-sepolia-rpc.publicnode.com (chain 11155111)
    Sepolia callback proxy: 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
    Lasna faucet:           0x9b9BB25f1A81078C544C829c5EB7822d747Cf434
    Chainlink ETH/USD:      0x694AA1769357215DE4FAC081bf1f309aDC325306

## What remains before submission

- Deploy with the steps above and fill in the deployed addresses and
  transaction hashes.
- Record a demo video under three minutes showing the loop.
- Push this folder to a public repository and submit the DoraHacks
  form with the repo link, the addresses, the transaction hashes, and
  the video.

## License

MIT. See LICENSE.
