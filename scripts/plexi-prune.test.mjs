import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pruneScratch, scratchEligible, oldOwnedTree, targetBusy, registeredWorktrees } from './plexi-prune.mjs';

const old = new Date(Date.now() - 30 * 86400000);
const cutoff = Date.now() - 14 * 86400000;
const idle = { cutoff, commands: '', openPaths: [], workingDirs: [], pidAlive: () => false };
const legacy = 'plexi-test-workspace-12345678-1234-1234-1234-123456789abc';
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'plexi-prune-spec-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return root;
}
function directory(root, name) {
  const dir = path.join(root, name);
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'state'), 'scratch');
  fs.utimesSync(path.join(dir, 'state'), old, old);
  fs.utimesSync(dir, old, old);
  return dir;
}

test('preview preserves files; apply removes only old allowlisted scratch', t => {
  const root = fixture(t);
  const eligible = directory(root, legacy);
  const data = directory(root, 'plexi-user-notes');
  const fresh = directory(root, 'plexi-test-host-9876-abcdef');
  fs.utimesSync(path.join(fresh, 'state'), new Date(), new Date());
  assert.equal(pruneScratch([root], false, 14, idle).count, 1);
  assert.ok(fs.existsSync(eligible));
  assert.equal(pruneScratch([root], true, 14, idle).count, 1);
  assert.ok(!fs.existsSync(eligible));
  assert.ok(fs.existsSync(data));
  assert.ok(fs.existsSync(fresh));
});

test('active test process, open file and live owner each prevent deletion', t => {
  const root = fixture(t);
  const dir = directory(root, 'plexi-test-host-1234-abcdef');
  for (const live of [
    { ...idle, commands: '/repo/target/debug/deps/plexi-a03e06e2d2d5bc13 --test-threads=4' },
    { ...idle, openPaths: [path.join(dir, 'state')] },
    { ...idle, pidAlive: pid => pid === 1234 },
  ]) {
    assert.equal(pruneScratch([root], true, 14, live).count, 0);
    assert.ok(fs.existsSync(dir));
  }
});

test('symlink root and nested symlink never reach their target', t => {
  const root = fixture(t);
  const data = directory(root, 'user-data');
  const link = path.join(root, legacy);
  fs.symlinkSync(data, link);
  const nested = directory(root, 'plexi-test-host-1234-abcdef');
  fs.symlinkSync(data, path.join(nested, 'link'));
  fs.utimesSync(nested, old, old);
  assert.equal(pruneScratch([root], true, 14, idle).count, 0);
  assert.ok(fs.readFileSync(path.join(data, 'state'), 'utf8') === 'scratch');
});

test('foreign ownership and near-matching names are excluded', t => {
  const root = fixture(t);
  const dir = directory(root, legacy);
  assert.equal(oldOwnedTree(dir, cutoff, process.getuid() + 1), false);
  assert.equal(scratchEligible(directory(root, legacy + '-backup'), idle), false);
});

test('registered worktrees retain spaces and include non-feature paths', () => {
  assert.deepEqual(registeredWorktrees('worktree /repo root\0HEAD abc\0\0worktree /tmp/0759-impl\0HEAD def\0'),
    ['/repo root', '/tmp/0759-impl']);
});

test('mapped build files and active working directories protect targets', () => {
  assert.equal(targetBusy('/repo', '/repo/target', { ...idle, openPaths: ['/repo/target/debug/plexi'] }), true);
  assert.equal(targetBusy('/repo', '/repo/target', { ...idle, workingDirs: ['/repo/src'] }), true);
  assert.equal(targetBusy('/repo', '/repo/target', { ...idle, openPaths: ['/repo-other/target/a'] }), false);
});
