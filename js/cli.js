#!/usr/bin/env node
// Guardian command line: run the demo, check a rule against prices, or
// print the on-chain command that registers a rule.

import { runSeries, demoScenario, renderRun } from './simulator.js';
import {
  createRule,
  evaluateRule,
  formatPrice,
  parsePrice,
  SEPOLIA_CHAIN_ID,
  ETH_USD_FEED,
  CHAINLINK_TOPIC0,
  BEACON_TOPIC0,
} from './rules.js';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

const USAGE = `Guardian CLI

Usage:
  node js/cli.js demo
    Replay a canned ETH price series through two rules and print the
    trigger log.

  node js/cli.js check --token ETH --below 3500 --price 3490
    Build a rule and check it against one price. Use --above instead of
    --below for a take-profit, --oneshot for a one-shot rule, and
    --prices 3600,3490,3510 to check a series.

  node js/cli.js rule --token ETH --below 3500 [--oneshot] [--action 0x...]
    Print the rule and the cast command that registers it on Lasna.
    Defaults to the Chainlink ETH/USD feed on Sepolia. Use --beacon 0x...
    with --token-address 0x... for a PriceBeacon feed.
`;

function parseFlags(args) {
  const flags = {};
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (!arg.startsWith('--')) throw new Error(`Unexpected argument: ${arg}`);
    const key = arg.slice(2);
    if (key === 'oneshot') {
      flags.oneshot = true;
      continue;
    }
    const value = args[i + 1];
    if (value === undefined || value.startsWith('--')) {
      throw new Error(`Missing value for --${key}`);
    }
    flags[key] = value;
    i++;
  }
  return flags;
}

function ruleFromFlags(flags) {
  const direction = flags.below ? 'below' : flags.above ? 'above' : null;
  if (!direction) throw new Error('Pass --below <price> or --above <price>');
  return createRule({
    token: flags.token || 'ETH',
    direction,
    threshold: flags.below || flags.above,
    oneShot: Boolean(flags.oneshot),
  });
}

function cmdDemo() {
  const { rules, prices } = demoScenario();
  const ticks = runSeries(rules, prices);
  console.log(renderRun(rules, ticks).join('\n'));
}

function cmdCheck(args) {
  const flags = parseFlags(args);
  const rule = ruleFromFlags(flags);
  const rawPrices = flags.prices
    ? flags.prices.split(',').map((s) => s.trim()).filter(Boolean)
    : [flags.price];
  if (!rawPrices.length || rawPrices.includes(undefined)) {
    throw new Error('Pass --price <price> or --prices <a,b,c>');
  }
  const prices = rawPrices.map((p) => parsePrice(p));
  console.log(`Rule: ${rule.token} ${rule.direction} $${formatPrice(rule.threshold)}${rule.oneShot ? ' (one-shot)' : ''}`);
  let fired = 0;
  prices.forEach((price, i) => {
    const trigger = evaluateRule(rule, price);
    if (trigger) {
      fired += 1;
      console.log(`  $${formatPrice(price)} -> TRIGGER (fire #${trigger.triggerCount})`);
    } else {
      console.log(`  $${formatPrice(price)} -> quiet`);
    }
    void i;
  });
  console.log(`Triggers fired: ${fired}`);
}

function cmdRule(args) {
  const flags = parseFlags(args);
  const rule = ruleFromFlags(flags);
  const beacon = flags.beacon;
  const feed = beacon || ETH_USD_FEED;
  const topic0 = beacon ? BEACON_TOPIC0 : CHAINLINK_TOPIC0;
  const token = beacon ? flags['token-address'] || ZERO_ADDRESS : ZERO_ADDRESS;
  const direction = rule.direction === 'below' ? 0 : 1;
  const action = flags.action || ZERO_ADDRESS;
  const destChain = flags.action ? SEPOLIA_CHAIN_ID : 0;

  console.log(`Rule: ${rule.token} ${rule.direction} $${formatPrice(rule.threshold)}${rule.oneShot ? ' (one-shot)' : ''}`);
  console.log(`Feed: ${feed} (Sepolia)`);
  console.log('');
  console.log('Register it on Lasna with:');
  console.log('');
  console.log(
    'cast send $GUARDIAN --rpc-url $LASNA_RPC --private-key $PRIVATE_KEY \\',
  );
  console.log(
    '  "createRule(uint256,address,uint256,address,int256,uint8,bool,uint256,address)" \\',
  );
  console.log(
    `  ${SEPOLIA_CHAIN_ID} ${feed} ${topic0} ${token} ${rule.threshold} ${direction} ${rule.oneShot} ${destChain} ${action}`,
  );
}

function main() {
  const [command, ...args] = process.argv.slice(2);
  try {
    if (command === 'demo') return cmdDemo();
    if (command === 'check') return cmdCheck(args);
    if (command === 'rule') return cmdRule(args);
    if (command === 'help' || command === undefined) {
      console.log(USAGE);
      return;
    }
    throw new Error(`Unknown command: ${command}`);
  } catch (error) {
    console.error(`Error: ${error.message}`);
    console.error('');
    console.error(USAGE);
    process.exit(1);
  }
}

main();
