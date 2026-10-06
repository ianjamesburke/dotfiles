#!/usr/bin/env node
// Idempotently sets the Pi settings we own in <agent-dir>/settings.json. Other keys are untouched.
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const OWNED = { tuiMode: "regular", outputPad: 0 };

const agentDir = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
const file = join(agentDir, "settings.json");

let settings = {};
if (existsSync(file)) {
  try {
    settings = JSON.parse(readFileSync(file, "utf8"));
  } catch (err) {
    throw new Error(`pi-settings-seed: ${file} is not valid JSON, fix or remove it: ${err.message}`);
  }
}

const changed = Object.keys(OWNED).filter((k) => settings[k] !== OWNED[k]);
if (changed.length === 0) {
  console.log(`pi settings already set in ${file}`);
  process.exit(0);
}

mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, JSON.stringify({ ...settings, ...OWNED }, null, 2) + "\n");
console.log(`pi settings updated in ${file}: ${changed.join(", ")}`);
