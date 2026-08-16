#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { patchBundle, modulePatches } = require("./patch-linux.js");

function fixtureSource(modulePatch) {
  let source = `fixture:${modulePatch.target}\n`;
  for (const patch of modulePatch.patches) {
    source += `${patch.needle}\n`;
  }
  source += `//# sourceURL=webpack://alibaba-cloud-client/${modulePatch.target}?fixture\n`;
  return source;
}

function fixtureBundle() {
  return modulePatches
    .map((entry) => `eval(${JSON.stringify(fixtureSource(entry))});\n`)
    .join("");
}

test("all Linux patches apply exactly once and are idempotent", () => {
  const first = patchBundle(fixtureBundle());
  assert.equal(first.report.length, 12);
  assert.ok(first.report.every((entry) => entry.status === "applied"));

  const second = patchBundle(first.output);
  assert.equal(second.output, first.output);
  assert.ok(second.report.every((entry) => entry.status === "already-applied"));
});

test("upstream drift fails instead of producing a partial bundle", () => {
  const encodedNeedle = JSON.stringify(modulePatches[0].patches[0].needle).slice(1, -1);
  const broken = fixtureBundle().replace(encodedNeedle, "upstream changed");
  assert.throws(() => patchBundle(broken), /linux-window-manager-stub: patch target not found/);
});
