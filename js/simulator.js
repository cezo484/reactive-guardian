// Replays a price series through Guardian rules and records every
// trigger, so the full loop can be seen without touching a testnet.

import { createRule, evaluateRule, formatPrice, parsePrice } from './rules.js';

// Runs each price in the series through every rule in order. Returns one
// entry per tick, each holding the triggers that fired on that tick.
export function runSeries(rules, prices) {
  const ticks = [];
  for (const raw of prices) {
    const price = typeof raw === 'bigint' ? raw : parsePrice(String(raw));
    const triggers = [];
    for (const rule of rules) {
      const fired = evaluateRule(rule, price);
      if (fired) triggers.push(fired);
    }
    ticks.push({ price, triggers });
  }
  return ticks;
}

// The canned demo: ETH drifts down through a stop-loss, recovers, then
// climbs through a take-profit twice. The stop-loss is one-shot, the
// take-profit repeats.
export function demoScenario() {
  const rules = [
    createRule({ token: 'ETH', direction: 'below', threshold: '3500', oneShot: true }),
    createRule({ token: 'ETH', direction: 'above', threshold: '3800', oneShot: false }),
  ];
  const prices = [
    '3600', '3580', '3520', '3495', '3480', '3510', '3490',
    '3650', '3750', '3810', '3790', '3820', '3780',
  ];
  return { rules, prices };
}

function triggerLine(trigger, tick) {
  const side = trigger.direction === 'below' ? 'below' : 'above';
  return (
    `  tick ${tick}: TRIGGER ${trigger.token} at $${formatPrice(trigger.price)} ` +
    `crossed ${side} $${formatPrice(trigger.threshold)} ` +
    `(fire #${trigger.triggerCount}${trigger.oneShot ? ', rule now off' : ''})`
  );
}

// Renders a run as plain text lines.
export function renderRun(rules, ticks) {
  const lines = [];
  lines.push('Guardian demo');
  lines.push('');
  lines.push('Rules:');
  for (const rule of rules) {
    const side = rule.direction === 'below' ? 'drops below' : 'rises above';
    const mode = rule.oneShot ? 'one-shot' : 'repeat';
    lines.push(`  ${rule.token} ${side} $${formatPrice(rule.threshold)} (${mode})`);
  }
  lines.push('');
  lines.push('Price feed:');
  let total = 0;
  ticks.forEach((tick, i) => {
    lines.push(`  tick ${i}: ETH $${formatPrice(tick.price)}`);
    for (const trigger of tick.triggers) {
      lines.push(triggerLine(trigger, i));
      total += 1;
    }
  });
  lines.push('');
  lines.push(`Triggers fired: ${total}`);
  return lines;
}
