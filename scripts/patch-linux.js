#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

function locateEvalModule(bundle, target) {
  const marker = `sourceURL=webpack://alibaba-cloud-client/${target}?`;
  const markerIndex = bundle.indexOf(marker);
  if (markerIndex < 0) {
    throw new Error(`Webpack module not found: ${target}`);
  }

  const evalIndex = bundle.lastIndexOf('eval("', markerIndex);
  if (evalIndex < 0) {
    throw new Error(`Webpack eval wrapper not found: ${target}`);
  }

  const quoteStart = evalIndex + 5;
  let escaped = false;
  let quoteEnd = -1;
  for (let index = quoteStart + 1; index < bundle.length; index += 1) {
    const character = bundle[index];
    if (escaped) {
      escaped = false;
    } else if (character === "\\") {
      escaped = true;
    } else if (character === '"') {
      quoteEnd = index;
      break;
    }
  }
  if (quoteEnd < markerIndex) {
    throw new Error(`Webpack eval string is malformed: ${target}`);
  }

  return {
    start: quoteStart,
    end: quoteEnd + 1,
    source: JSON.parse(bundle.slice(quoteStart, quoteEnd + 1)),
  };
}

function replaceOnce(source, patch) {
  const count = source.split(patch.needle).length - 1;
  if (count === 1) {
    return { source: source.replace(patch.needle, patch.replacement), status: "applied" };
  }
  if (count > 1) {
    throw new Error(`${patch.id}: expected one match, found ${count}`);
  }
  if (source.includes(patch.replacement)) {
    return { source, status: "already-applied" };
  }
  throw new Error(`${patch.id}: patch target not found`);
}

const modulePatches = [
  {
    target: "./node_modules/@johnlindquist/node-window-manager/dist/index.js",
    patches: [
      {
        id: "linux-window-manager-stub",
        needle: 'var addon = require(__webpack_require__.ab + "build/Release/window-manager.node");',
        replacement:
          'var addon = process.platform === "linux"\n' +
          '  ? null\n' +
          '  : require(__webpack_require__.ab + "build/Release/window-manager.node");',
      },
    ],
  },
  {
    target: "./target/main/starter.js",
    patches: [
      {
        id: "guard-active-window",
        needle:
          '            if (global_1.options.spotQuery.autoScreen || node_process_1.default.platform == "darwin") {\n' +
          '                if (this.autoJustWindow(activeWindow)) {',
        replacement:
          '            if (activeWindow && (global_1.options.spotQuery.autoScreen || node_process_1.default.platform == "darwin")) {\n' +
          '                if (this.autoJustWindow(activeWindow)) {',
      },
      {
        id: "guard-linux-vibrancy",
        needle: '    setVibrancy(vibrancy) {\n        if (this.homeWindow) {',
        replacement:
          '    setVibrancy(vibrancy) {\n' +
          '        if (node_process_1.default.platform === "darwin" && this.homeWindow) {',
      },
      {
        id: "disable-linux-autostart-write",
        needle:
          '    setAutoStart(value) {\n' +
          '        global_1.options.general.autoStart = value;',
        replacement:
          '    setAutoStart(value) {\n' +
          '        if (node_process_1.default.platform === "linux") {\n' +
          '            global_1.options.general.autoStart = false;\n' +
          '            return;\n' +
          '        }\n' +
          '        global_1.options.general.autoStart = value;',
      },
      {
        id: "disable-linux-autostart-check",
        needle:
          '    checkAutoStart() {\n' +
          '        const autoStart = global_1.options.general.autoStart;',
        replacement:
          '    checkAutoStart() {\n' +
          '        if (node_process_1.default.platform === "linux") {\n' +
          '            global_1.options.general.autoStart = false;\n' +
          '            return;\n' +
          '        }\n' +
          '        const autoStart = global_1.options.general.autoStart;',
      },
    ],
  },
  {
    target: "./target/main/local/ClipboardMonitor.js",
    patches: [
      {
        id: "linux-clipboard-window-fallback",
        needle:
          '        const activeWindow = node_window_manager_1.windowManager.getActiveWindow();\n' +
          '        clipItem.app = activeWindow.path;\n' +
          '        clipItem.icon = this.appIcons.get(activeWindow.path);\n' +
          '        if (clipItem.icon === undefined) {',
        replacement:
          '        const activeWindow = node_window_manager_1.windowManager.getActiveWindow();\n' +
          '        clipItem.app = (activeWindow === null || activeWindow === void 0 ? void 0 : activeWindow.path) || "";\n' +
          '        clipItem.icon = clipItem.app ? this.appIcons.get(clipItem.app) : "";\n' +
          '        if (activeWindow && clipItem.app && clipItem.icon === undefined) {',
      },
    ],
  },
  {
    target: "./node_modules/robotjs/index.js",
    patches: [
      {
        id: "linux-robotjs-stub",
        needle:
          'var robotjs = __webpack_require__(/*! ./build/Release/robotjs.node */ "./node_modules/robotjs/build/Release/robotjs.node");',
        replacement:
          'var robotjs = process.platform === "linux"\n' +
          '  ? { keyTap: function () {} }\n' +
          '  : __webpack_require__(/*! ./build/Release/robotjs.node */ "./node_modules/robotjs/build/Release/robotjs.node");',
      },
    ],
  },
  {
    target: "./target/main/local/SysUtils.js",
    patches: [
      {
        id: "linux-local-shell-list",
        needle:
          'function getShellList() {\n' +
          '    return __awaiter(this, void 0, void 0, function* () {\n' +
          '        switch (node_process_1.default.platform) {\n' +
          '            case "darwin":\n' +
          '                return new Promise((resolve, reject) => {',
        replacement:
          'function getShellList() {\n' +
          '    return __awaiter(this, void 0, void 0, function* () {\n' +
          '        switch (node_process_1.default.platform) {\n' +
          '            case "darwin":\n' +
          '            case "linux":\n' +
          '                return new Promise((resolve, reject) => {',
      },
    ],
  },
  {
    target: "./target/main/option/initial.json",
    patches: [
      {
        id: "linux-default-terminal-font",
        needle:
          '\"shell\":{\"fontSize\":{\"current\":\"14px\",\"options\":[\"12px\",\"14px\",\"16px\"]},' +
          '\"fontFamily\":{\"current\":\"Monaco\",\"options\":[]}',
        replacement:
          '\"shell\":{\"fontSize\":{\"current\":\"14px\",\"options\":[\"12px\",\"14px\",\"16px\"]},' +
          '\"fontFamily\":{\"current\":\"Consolas\",\"options\":[]}',
      },
    ],
  },
  {
    target: "./target/main/handler/updater.js",
    patches: [
      {
        id: "disable-linux-updater-setup",
        needle:
          '    setup() {\n' +
          '        electron_updater_1.autoUpdater.autoDownload = false;',
        replacement:
          '    setup() {\n' +
          '        if (process.platform === "linux") {\n' +
          '            return;\n' +
          '        }\n' +
          '        electron_updater_1.autoUpdater.autoDownload = false;',
      },
      {
        id: "linux-manual-update-message",
        needle:
          '    checkUpdate(sender) {\n' +
          '        electron_updater_1.autoUpdater.removeAllListeners("error");',
        replacement:
          '    checkUpdate(sender) {\n' +
          '        if (process.platform === "linux") {\n' +
          '            this.status = "error";\n' +
          '            sender.send(this.channel, {\n' +
          '                status: "error",\n' +
          '                message: "Linux 版本请使用新的官方 DMG 重新构建安装包 / Rebuild the Linux package from a new official DMG."\n' +
          '            });\n' +
          '            return Promise.resolve(false);\n' +
          '        }\n' +
          '        electron_updater_1.autoUpdater.removeAllListeners("error");',
      },
      {
        id: "linux-local-version-info",
        needle:
          '    getVersion(sender, lang) {\n' +
          '        const updaterServer = this.getUpdateServer(global_1.options.updater.updaterServer);',
        replacement:
          '    getVersion(sender, lang) {\n' +
          '        if (process.platform === "linux") {\n' +
          '            return Promise.resolve({\n' +
          '                version: package_json_1.default.version,\n' +
          '                packageSize: 0,\n' +
          '                releaseName: package_json_1.default.version,\n' +
          '                releaseDate: undefined,\n' +
          '                releaseNotes: []\n' +
          '            });\n' +
          '        }\n' +
          '        const updaterServer = this.getUpdateServer(global_1.options.updater.updaterServer);',
      },
    ],
  },
];

function patchBundle(bundle) {
  const report = [];
  let output = bundle;

  for (const modulePatch of modulePatches) {
    const module = locateEvalModule(output, modulePatch.target);
    let source = module.source;
    for (const patch of modulePatch.patches) {
      const result = replaceOnce(source, patch);
      source = result.source;
      report.push({ id: patch.id, target: modulePatch.target, status: result.status });
    }
    output = output.slice(0, module.start) + JSON.stringify(source) + output.slice(module.end);
  }

  return { output, report };
}

function main() {
  const [bundlePath, reportPath] = process.argv.slice(2);
  if (!bundlePath) {
    throw new Error("Usage: patch-linux.js <main/index.js> [report.json]");
  }

  const original = fs.readFileSync(bundlePath, "utf8");
  const result = patchBundle(original);
  if (result.output !== original) {
    fs.writeFileSync(bundlePath, result.output);
  }
  if (reportPath) {
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, `${JSON.stringify({ patches: result.report }, null, 2)}\n`);
  }
  for (const entry of result.report) {
    process.stderr.write(`[PATCH] ${entry.id}: ${entry.status}\n`);
  }
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`[ERROR] ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { locateEvalModule, replaceOnce, patchBundle, modulePatches };
