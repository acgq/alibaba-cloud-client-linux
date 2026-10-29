#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const https = require("node:https");
const { patchBundle, modulePatches, locateEvalModule } = require("./patch-linux.js");

const httpTarget = "./target/main/local/HttpClient.js";
const httpFixture = fs.readFileSync(path.join(__dirname, "../tests/fixtures/http-client-2.3.6.js"), "utf8");

function fixtureSource(modulePatch) {
  if (modulePatch.target === httpTarget) return httpFixture;
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
  assert.equal(first.report.length, 13);
  assert.ok(first.report.every((entry) => entry.status === "applied"));

  const second = patchBundle(first.output);
  assert.equal(second.output, first.output);
  assert.ok(second.report.every((entry) => entry.status === "already-applied"));
});

test("upstream drift fails instead of producing a partial bundle", () => {
  const patch = modulePatches[0].patches[0];
  const encodedNeedle = JSON.stringify(patch.needle).slice(1, -1);
  const broken = fixtureBundle().replace(encodedNeedle, "upstream changed");
  assert.throws(() => patchBundle(broken), new RegExp(`${patch.id}: patch target not found`));
});

function loadHttpClient(platform, send, proxy) {
  const patched = patchBundle(fixtureBundle()).output;
  const source = locateEvalModule(patched, httpTarget).source;
  const exports = {};
  const dependencies = {
    https,
    "./node_modules/axios/dist/node/axios.cjs": { request: send },
    "./target/main/global.js": { getHttpsProxy: () => proxy, getHttpProxy: () => proxy },
    "./target/main/i18n/i18nopt.js": { t: () => "proxy error" },
    "./target/main/logger/logger.js": { info() {}, warn() {} },
  };
  vm.runInNewContext(source, {
    exports, process: { platform }, URL,
    __webpack_require__(id) {
      assert.ok(Object.hasOwn(dependencies, id), `Unexpected dependency: ${id}`);
      return dependencies[id];
    },
  });
  return exports;
}

test("Linux Alibaba API transport uses verified TLS 1.2 and preserves request data", async () => {
  const calls = [];
  const response = { status: 200, data: { Regions: [] } };
  const client = loadHttpClient("linux", async request => { calls.push(request); return response; });
  const request = { url: "HTTPS://ecs.aliyuncs.com/?AcceptLanguage=zh-CN", method: "POST", data: "signed body", headers: { Authorization: "test signature" } };
  assert.equal(await client.httpxSend(request), response);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].data, "signed body");
  assert.equal(calls[0].headers.Authorization, "test signature");
  const agent = calls[0].httpsAgent;
  assert.ok(agent instanceof https.Agent);
  assert.equal(agent.options.minVersion, "TLSv1.2");
  assert.equal(agent.options.maxVersion, "TLSv1.2");
  assert.notEqual(agent.options.rejectUnauthorized, false);
  await client.httpxGet("https://sts.cn-hangzhou.aliyuncs.com/", {});
  assert.equal(calls[1].httpsAgent, agent);
  agent.destroy();
});

test("TLS workaround preserves custom agents, other hosts, HTTP and non-Linux platforms", async () => {
  for (const platform of ["linux", "darwin", "win32"]) {
    const client = loadHttpClient(platform, async request => request);
    for (const url of ["https://example.com/", "https://ecs.aliyuncs.com.example.com/", "https://aliyuncs.com.example.com/", "http://ecs.aliyuncs.com/"]) {
      assert.equal((await client.httpxSend({ url })).httpsAgent, undefined);
    }
    const customAgent = { clientCertificate: "test certificate" };
    assert.equal((await client.httpxSend({ url: "https://ecs.aliyuncs.com/", httpsAgent: customAgent })).httpsAgent, customAgent);
    if (platform !== "linux") {
      assert.equal((await client.httpxSend({ url: "https://ecs.aliyuncs.com/" })).httpsAgent, undefined);
    }
  }
});

test("TLS errors propagate without automatically replaying cloud operations", async () => {
  const error = Object.assign(new Error("test decrypt failure"), { code: "ERR_SSL_BAD_DECRYPT" });
  let calls = 0;
  const client = loadHttpClient("linux", async () => { calls++; throw error; });
  await assert.rejects(client.httpxSend({ url: "https://ecs.aliyuncs.com/", method: "POST", data: "cloud operation" }), e => e === error);
  assert.equal(calls, 1);
});

test("TLS workaround preserves proxy authentication", async () => {
  const proxy = { protocol: "http", server: "127.0.0.1", port: 8080, needAuth: true, username: "test", password: "test" };
  const client = loadHttpClient("linux", async request => request, proxy);
  const request = await client.httpxSend({ url: "https://ecs.aliyuncs.com/", method: "POST" });
  assert.equal(request.proxy.host, proxy.server);
  assert.equal(request.proxy.auth.username, proxy.username);
  assert.equal(request.proxy.auth.password, proxy.password);
});
