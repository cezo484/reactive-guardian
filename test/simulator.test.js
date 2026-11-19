import test from 'node:test';
import assert from 'node:assert/strict';
import { runSeries, demoScenario, renderRun } from '../js/simulator.js';
import { createRule } from '../js/rules.js';

test('runSeries records triggers per tick', () => {
  const rules = [
    createRule({ token: 'ETH', direction: 'below', threshold: '3500' }),
  ];
  const ticks = runSeries(rules, ['3600', '3490', '3480', '3600', '3490']);
  assert.equal(ticks.length, 5);
  assert.equal(ticks[0].triggers.length, 0);
  assert.equal(ticks[1].triggers.length, 1);
  assert.equal(ticks[2].triggers.length, 0);
  assert.equal(ticks[3].triggers.length, 0);
  assert.equal(ticks[4].triggers.length, 1);
});

test('demo scenario fires the stop-loss once and the take-profit twice', () => {
  const { rules, prices } = demoScenario();
  const ticks = runSeries(rules, prices);
  const triggers = ticks.flatMap((tick) => tick.triggers);
  assert.equal(triggers.length, 3);
  const stops = triggers.filter((t) => t.direction === 'below');
  const takes = triggers.filter((t) => t.direction === 'above');
  assert.equal(stops.length, 1);
  assert.equal(takes.length, 2);
  assert.equal(takes[1].triggerCount, 2);
});

test('renderRun prints the trigger log', () => {
  const { rules, prices } = demoScenario();
  const ticks = runSeries(rules, prices);
  const text = renderRun(rules, ticks).join('\n');
  assert.match(text, /Guardian demo/);
  assert.match(text, /TRIGGER ETH at \$3495/);
  assert.match(text, /TRIGGER ETH at \$3810/);
  assert.match(text, /Triggers fired: 3/);
});
