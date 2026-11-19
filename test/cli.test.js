import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const run = promisify(execFile);
const cli = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  'js',
  'cli.js',
);

test('demo prints the trigger log', async () => {
  const { stdout } = await run('node', [cli, 'demo']);
  assert.match(stdout, /Guardian demo/);
  assert.match(stdout, /Triggers fired: 3/);
});

test('check reports a trigger for a crossed threshold', async () => {
  const { stdout } = await run('node', [
    cli, 'check', '--token', 'ETH', '--below', '3500', '--price', '3490',
  ]);
  assert.match(stdout, /TRIGGER/);
  assert.match(stdout, /Triggers fired: 1/);
});

test('check stays quiet inside the range', async () => {
  const { stdout } = await run('node', [
    cli, 'check', '--token', 'ETH', '--below', '3500', '--price', '3600',
  ]);
  assert.match(stdout, /quiet/);
  assert.match(stdout, /Triggers fired: 0/);
});

test('check accepts a price series', async () => {
  const { stdout } = await run('node', [
    cli, 'check', '--token', 'ETH', '--below', '3500',
    '--prices', '3600,3490,3480,3600,3490',
  ]);
  assert.match(stdout, /Triggers fired: 2/);
});

test('rule prints the cast command for the on-chain rule', async () => {
  const { stdout } = await run('node', [
    cli, 'rule', '--token', 'ETH', '--below', '3500', '--oneshot',
  ]);
  assert.match(stdout, /createRule\(uint256,address,uint256,address,int256,uint8,bool,uint256,address\)/);
  assert.match(stdout, /350000000000/);
  assert.match(stdout, /0x694AA1769357215DE4FAC081bf1f309aDC325306/);
});

test('unknown command exits non-zero with usage', async () => {
  await assert.rejects(run('node', [cli, 'nonsense']), /Unknown command/);
});
