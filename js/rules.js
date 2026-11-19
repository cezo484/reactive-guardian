// Rule logic for the Guardian simulator. This mirrors Guardian.sol
// exactly: same edge trigger, same latch, same one-shot handling. Prices
// use 8 decimals, the scale Chainlink feeds report in.

export const SCALE = 100000000n;

export const SEPOLIA_CHAIN_ID = 11155111;
export const LASNA_CHAIN_ID = 5318007;
export const ETH_USD_FEED = '0x694AA1769357215DE4FAC081bf1f309aDC325306';
export const CHAINLINK_TOPIC0 =
  '0x0559884fd3a460db3073b7fc896cc77986f16e378210ded43186175bf646fc5f';
export const BEACON_TOPIC0 =
  '0x0d86730737b142fc160892fa8a0f2db687a92a0e294d1ad70624cf5acef03b84';

const PRICE_RE = /^-?\d+(\.\d{1,8})?$/;

// Parses a decimal price like "3500.5" into 8 decimal fixed point.
export function parsePrice(text) {
  if (typeof text !== 'string' || !PRICE_RE.test(text.trim())) {
    throw new Error(`Bad price: ${text}`);
  }
  const clean = text.trim();
  const negative = clean.startsWith('-');
  const digits = negative ? clean.slice(1) : clean;
  const [whole, frac = ''] = digits.split('.');
  const value = BigInt(whole) * SCALE + BigInt(frac.padEnd(8, '0') || '0');
  return negative ? -value : value;
}

// Formats an 8 decimal fixed point price back to readable text.
export function formatPrice(value) {
  const negative = value < 0n;
  const abs = negative ? -value : value;
  const whole = abs / SCALE;
  const frac = (abs % SCALE).toString().padStart(8, '0').replace(/0+$/, '');
  const text = frac ? `${whole}.${frac}` : `${whole}`;
  return negative ? `-${text}` : text;
}

// Builds a rule. direction is "below" for a stop-loss and "above" for a
// take-profit. threshold is a decimal price string.
export function createRule({ token, direction, threshold, oneShot = false }) {
  if (!token || typeof token !== 'string') {
    throw new Error('A token symbol is required');
  }
  if (direction !== 'below' && direction !== 'above') {
    throw new Error('Direction must be "below" or "above"');
  }
  const thresholdValue = parsePrice(String(threshold));
  if (thresholdValue <= 0n) {
    throw new Error('Threshold must be above zero');
  }
  return {
    token: token.toUpperCase(),
    direction,
    threshold: thresholdValue,
    oneShot,
    active: true,
    tripped: false,
    triggerCount: 0,
    lastPrice: null,
  };
}

// Runs one price observation through a rule. Returns the trigger record
// when the rule fires, or null when it stays quiet. This is the same
// decision Guardian.sol makes inside react().
export function evaluateRule(rule, price) {
  if (!rule.active) return null;
  const past =
    rule.direction === 'below' ? price < rule.threshold : price > rule.threshold;
  rule.lastPrice = price;
  if (!past) {
    rule.tripped = false;
    return null;
  }
  if (rule.tripped) return null;
  rule.tripped = true;
  rule.triggerCount += 1;
  if (rule.oneShot) rule.active = false;
  return {
    token: rule.token,
    direction: rule.direction,
    price,
    threshold: rule.threshold,
    triggerCount: rule.triggerCount,
    oneShot: rule.oneShot,
  };
}

export function describeRule(rule) {
  const side = rule.direction === 'below' ? 'drops below' : 'rises above';
  const mode = rule.oneShot ? 'one-shot' : 'repeat';
  return `${rule.token} ${side} $${formatPrice(rule.threshold)} (${mode})`;
}
