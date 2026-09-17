#!/usr/bin/env node
// Plexi-owned scratch only. Profiles, installed apps, sources and git history are excluded.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const DAY = 86400000;
const UUID = '[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}';
const LEGACY = new RegExp(`^plexi-test-(?:workspace|perms)-${UUID}$`);
const OWNED = /^plexi-test-host-(\d+)-[A-Za-z0-9]+$/;
const log = message => console.log(`[plexi-prune] ${message}`);

function run(command, args, env = process.env, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', env, cwd: options.cwd, maxBuffer: 32 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed: ${result.error?.message ?? result.stderr}`);
  }
  return result.stdout + (options.includeStderr ? result.stderr : "");
}

export function within(file, root) {
  return file === root || file.startsWith(root + path.sep);
}

// Inspect every entry without following links. Directory mtime alone misses
// fresh writes to existing children; any link/foreign owner makes us leave it alone.
export function oldOwnedTree(root, cutoff, uid = process.getuid()) {
  const pending = [root];
  while (pending.length) {
    const current = pending.pop();
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink() || stat.uid !== uid || stat.mtimeMs >= cutoff) return false;
    if (stat.isDirectory()) {
      for (const name of fs.readdirSync(current)) pending.push(path.join(current, name));
    } else if (!stat.isFile()) return false;
  }
  return true;
}

export function testProcessRunning(commands) {
  return /(?:^|[\s/])plexi-[a-f0-9]{16}(?:\s|$)/m.test(commands);
}

export function scratchEligible(root, { cutoff, commands, openPaths, pidAlive }) {
  const name = path.basename(root);
  const owned = OWNED.exec(name);
  if (!LEGACY.test(name) && !owned) return false;
  if (testProcessRunning(commands)) return false;
  if (owned && pidAlive(Number(owned[1]))) return false;
  if (openPaths.some(file => within(file, root))) return false;
  return oldOwnedTree(root, cutoff);
}

export function registeredWorktrees(output) {
  return output.split('\0').filter(line => line.startsWith('worktree ')).map(line => line.slice(9));
}

function liveState() {
  const commands = run('/bin/ps', ['-axo', 'command=']);
  // A failed or partial lsof snapshot is not evidence of inactivity.
  const result = spawnSync('/usr/sbin/lsof', ['-nP', '-u', String(process.getuid()), '-Ffn'],
    { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.error || result.status !== 0 || result.stderr.trim()) {
    throw new Error(`cannot inspect live files: ${result.error?.message ?? result.stderr}`);
  }
  const openPaths = [];
  const workingDirs = [];
  let cwd = false;
  for (const line of result.stdout.split('\n')) {
    if (line.startsWith('f')) cwd = line === 'fcwd';
    if (line.startsWith('n/')) {
      const name = line.slice(1);
      openPaths.push(name);
      if (cwd) workingDirs.push(name);
    }
  }
  return { commands, openPaths, workingDirs, pidAlive(pid) {
    try { process.kill(pid, 0); return true; }
    catch (error) { if (error.code === 'ESRCH') return false; throw error; }
  } };
}

function realDirectory(dir) {
  const stat = fs.lstatSync(dir);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid()) {
    throw new Error(`not an owned directory: ${dir}`);
  }
  return fs.realpathSync(dir);
}

export function targetBusy(project, target, live) {
  return live.openPaths.some(file => within(file, target)) ||
    live.workingDirs.some(dir => within(dir, project));
}

function pruneBuilds(repos, apply, days) {
  // Ignore pane/build overrides: metadata and sweep must resolve the same target.
  const env = { ...process.env };
  delete env.CARGO_TARGET_DIR;
  delete env.CARGO_BUILD_TARGET_DIR;
  const cargo = path.join(os.homedir(), '.cargo/bin/cargo');
  const sweep = path.join(os.homedir(), '.cargo/bin/cargo-sweep');
  const seen = new Set();
  for (const repo of repos) {
    if (!fs.existsSync(repo)) continue;
    realDirectory(repo);
    const remote = run('/usr/bin/git', ['-C', repo, 'remote', 'get-url', 'origin']).trim();
    if (!/github\.com[:/]ianjamesburke\/PLEXI(?:\.git)?$/i.test(remote)) {
      throw new Error(`refusing non-Plexi repository: ${repo}`);
    }
    for (const entry of registeredWorktrees(run('/usr/bin/git', ['-C', repo, 'worktree', 'list', '--porcelain', '-z']))) {
      if (!fs.existsSync(entry)) continue;
      const project = realDirectory(entry);
      const targetPath = path.join(project, 'target');
      if (!fs.existsSync(targetPath)) continue;
      const target = realDirectory(targetPath);
      if (target !== targetPath || seen.has(target)) continue;
      seen.add(target);
      // Cargo owns regular artifacts here; never let a redirected child escape it.
      if (!oldOwnedTree(target, Infinity)) {
        log(`skip target with links, foreign ownership or special files: ${target}`);
        continue;
      }
      const live = liveState();
      if (targetBusy(project, target, live)) {
        log(`skip active worktree/target: ${project}`);
        continue;
      }
      const metadata = JSON.parse(run(cargo, ['metadata', '--no-deps', '--format-version', '1', '--manifest-path', path.join(project, 'Cargo.toml')], env, { cwd: project }));
      if (path.resolve(metadata.target_directory) !== target) {
        log(`skip redirected Cargo target: ${project}`);
        continue;
      }
      log(`${apply ? 'prune' : 'preview'} artifacts older than ${days} days: ${target}`);
      process.stdout.write(run(sweep, ['sweep', '--time', String(days), ...(apply ? [] : ['--dry-run']), project], env, { cwd: project, includeStderr: true }));
    }
  }
}

export function pruneScratch(roots, apply, days, live = liveState()) {
  const cutoff = Date.now() - days * DAY;
  let count = 0;
  let bytes = 0;
  for (const root of roots) {
    for (const name of fs.readdirSync(root)) {
      if (!LEGACY.test(name) && !OWNED.test(name)) continue;
      const candidate = path.join(root, name);
      if (!scratchEligible(candidate, { ...live, cutoff })) continue;
      const pending = [candidate];
      let size = 0;
      while (pending.length) {
        const current = pending.pop();
        const stat = fs.lstatSync(current);
        size += stat.blocks * 512;
        if (stat.isDirectory()) for (const name of fs.readdirSync(current)) pending.push(path.join(current, name));
      }
      if (apply) fs.rmSync(candidate, { recursive: true });
      count++;
      bytes += size;
    }
  }
  log(`${apply ? 'removed' : 'would remove'} ${count} abandoned test directories, ${(bytes / 1024 ** 3).toFixed(3)} GiB`);
  return { count, bytes };
}

export function main(args) {
  if (args.some(arg => !['--apply', '--dry-run'].includes(arg)) || args.length > 1) {
    throw new Error('usage: plexi-cargo-sweep [--dry-run | --apply]');
  }
  if (process.env.PLEXI_CARGO_LOCK_HELD !== '1') throw new Error('run through plexi-cargo-sweep to acquire the build lock');
  const live = liveState();
  // Also protect builds launched without the sanctioned lease wrapper.
  if (/(?:^|[\s/])(?:cargo|rustc)(?:\s|$)/m.test(live.commands) || testProcessRunning(live.commands)) {
    log('skip: Rust build or Plexi test process is live');
    return;
  }
  const apply = args.includes('--apply');
  const days = 14;
  const home = os.homedir();
  const repos = [path.join(home, 'Documents/GitHub/PLEXI'), path.join(home, '.plexi-src')];
  const temp = run('/usr/bin/getconf', ['DARWIN_USER_TEMP_DIR']).trim();
  const roots = [...new Set([temp, '/private/tmp'].map(root => fs.realpathSync(root)))];
  log(`${apply ? 'apply' : 'dry run'}; cutoff ${days} days; profiles, installs and sources excluded`);
  pruneBuilds(repos, apply, days);
  pruneScratch(roots, apply, days);
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(`[plexi-prune] ${error.message}`); process.exitCode = 1; }
}
