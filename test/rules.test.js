import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parsePrice,
  formatPrice,
  createRule,
  evaluateRule,
} from '../js/rules.js';

test('parsePrice handles whole and fractional prices', () => {
  assert.equal(parsePrice('3500'), 350000000000n);
  assert.equal(parsePrice('3500.5'), 350050000000n);
  assert.equal(parsePrice('0.00000001'), 1n);
  assert.equal(parsePrice('1771.67104576'), 177167104576n);
});

test('parsePrice rejects bad input', () => {
  assert.throws(() => parsePrice('abc'), /Bad price/);
  assert.throws(() => parsePrice('1.123456789'), /Bad price/);
  assert.throws(() => parsePrice(''), /Bad price/);
});

test('formatPrice round trips parsePrice', () => {
  for (const text of ['3500', '3500.5', '0.00000001', '1771.67104576']) {
    assert.equal(formatPrice(parsePrice(text)), text);
  }
});

test('below rule fires on the first observation past the threshold', () => {
  const rule = createRule({ token: 'ETH', direction: 'below', threshold: '3500' });
  assert.equal(evaluateRule(rule, parsePrice('3600')), null);
  const fired = evaluateRule(rule, parsePrice('3490'));
  assert.ok(fired);
  assert.equal(fired.triggerCount, 1);
  assert.equal(rule.triggerCount, 1);
});

test('price exactly at the threshold does not fire', () => {
  const below = createRule({ token: 'ETH', direction: 'below', threshold: '3500' });
  assert.equal(evaluateRule(below, parsePrice('3500')), null);
  const above = createRule({ token: 'ETH', direction: 'above', threshold: '3500' });
  assert.equal(evaluateRule(above, parsePrice('3500')), null);
});

test('rule stays quiet while the price remains past the threshold', () => {
  const rule = createRule({ token: 'ETH', direction: 'below', threshold: '3500' });
  evaluateRule(rule, parsePrice('3490'));
  assert.equal(evaluateRule(rule, parsePrice('3480')), null);
  assert.equal(evaluateRule(rule, parsePrice('3000')), null);
  assert.equal(rule.triggerCount, 1);
});

test('repeat rule re-arms when the price comes back inside', () => {
  const rule = createRule({ token: 'ETH', direction: 'below', threshold: '3500' });
  evaluateRule(rule, parsePrice('3490'));
  evaluateRule(rule, parsePrice('3600'));
  assert.equal(rule.tripped, false);
  const fired = evaluateRule(rule, parsePrice('3490'));
  assert.ok(fired);
  assert.equal(fired.triggerCount, 2);
});

test('one-shot rule fires once and deactivates', () => {
  const rule = createRule({
    token: 'ETH',
    direction: 'below',
    threshold: '3500',
    oneShot: true,
  });
  evaluateRule(rule, parsePrice('3490'));
  assert.equal(rule.active, false);
  evaluateRule(rule, parsePrice('3600'));
  assert.equal(evaluateRule(rule, parsePrice('3490')), null);
  assert.equal(rule.triggerCount, 1);
});

test('above rule fires on a rise and ignores a fall', () => {
  const rule = createRule({ token: 'ETH', direction: 'above', threshold: '3500' });
  assert.equal(evaluateRule(rule, parsePrice('3400')), null);
  assert.ok(evaluateRule(rule, parsePrice('3600')));
});

test('createRule validates its input', () => {
  assert.throws(() => createRule({ direction: 'below', threshold: '3500' }), /token/);
  assert.throws(
    () => createRule({ token: 'ETH', direction: 'sideways', threshold: '3500' }),
    /Direction/,
  );
  assert.throws(
    () => createRule({ token: 'ETH', direction: 'below', threshold: '0' }),
    /above zero/,
  );
});
