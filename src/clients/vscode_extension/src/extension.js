const fs = require("node:fs/promises");
const path = require("node:path");
const { execFile } = require("node:child_process");
const vscode = require("vscode");

function otterRepoRoot(extensionUri) {
  return path.resolve(extensionUri.fsPath, "../../..");
}

function cliSourcePath(extensionUri) {
  return path.join(otterRepoRoot(extensionUri), "src", "clients", "cli", "otter_repo_graph.nim");
}

function sharedWebDir(extensionUri) {
  return path.join(otterRepoRoot(extensionUri), "src", "clients", "webui", "web");
}

function workspaceRoot() {
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder ? folder.uri.fsPath : process.cwd();
}

function execFileAsync(file, args, cwd) {
  return new Promise((resolve, reject) => {
    execFile(file, args, { cwd, maxBuffer: 32 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`${error.message}\n${stderr || stdout}`));
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}

async function runOtterCli(extensionUri, args) {
  const repoRoot = otterRepoRoot(extensionUri);
  const cliPath = cliSourcePath(extensionUri);
  const nimArgs = [
    "c",
    "-r",
    "--path:src",
    "--hints:off",
    "--verbosity:0",
    "--nimcache:build/nimcache_vscode_graph",
    cliPath,
    ...args
  ];
  const result = await execFileAsync("nim", nimArgs, repoRoot);
  return JSON.parse(result.stdout);
}

function renderAnnotationMarkdown(repoRoot, annotations) {
  const lines = ["# Otter Notes For Codex", "", `Repo: \`${repoRoot.replace(/\\/g, "/")}\``, ""];
  annotations.forEach((item) => {
    lines.push(`## ${String(item.name || item.functionId || "function")}`);
    lines.push(`- functionId: \`${String(item.functionId || "")}\``);
    lines.push(`- source: \`${String(item.sourcePath || "")}:${String(item.lineStart || "")}\``);
    lines.push(`- note: ${String(item.note || "")}`);
    lines.push("");
  });
  return lines.join("\n");
}

async function sendAnnotationsToCodex(repoRoot, annotations) {
  const markdown = renderAnnotationMarkdown(repoRoot, annotations);
  const buildDir = path.join(workspaceRoot(), "build");
  const outPath = path.join(buildDir, "otter_annotations_for_codex.md");
  await fs.mkdir(buildDir, { recursive: true });
  await fs.writeFile(outPath, markdown, "utf8");
  const doc = await vscode.workspace.openTextDocument(outPath);
  await vscode.window.showTextDocument(doc, { preview: false });
  const commands = await vscode.commands.getCommands(true);
  if (commands.includes("chatgpt.addFileToThread")) {
    await vscode.commands.executeCommand("chatgpt.addFileToThread");
    if (commands.includes("chatgpt.openSidebar")) {
      await vscode.commands.executeCommand("chatgpt.openSidebar");
    }
    return {
      ok: true,
      message: "annotations sent to Codex",
      path: outPath.replace(/\\/g, "/")
    };
  }
  await vscode.env.clipboard.writeText(markdown);
  return {
    ok: true,
    message: "Codex command unavailable; copied annotations to clipboard",
    path: outPath.replace(/\\/g, "/")
  };
}

async function chooseFolder() {
  const pick = await vscode.window.showOpenDialog({
    canSelectFiles: false,
    canSelectFolders: true,
    canSelectMany: false,
    openLabel: "Select Repo"
  });
  if (!pick || !pick.length) {
    return { ok: false, error: "no folder selected" };
  }
  return { ok: true, repoRoot: pick[0].fsPath.replace(/\\/g, "/") };
}

function viewSettingsPath(repoRoot) {
  return path.join(repoRoot, ".otter", "repo_graph_view_settings.json");
}

async function loadViewSettings(repoRoot) {
  const settingsPath = viewSettingsPath(repoRoot);
  try {
    const raw = await fs.readFile(settingsPath, "utf8");
    return {
      ok: true,
      path: settingsPath.replace(/\\/g, "/"),
      settings: JSON.parse(raw)
    };
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return {
        ok: true,
        path: settingsPath.replace(/\\/g, "/"),
        settings: null
      };
    }
    throw error;
  }
}

async function saveViewSettings(repoRoot, settings) {
  const settingsPath = viewSettingsPath(repoRoot);
  await fs.mkdir(path.dirname(settingsPath), { recursive: true });
  await fs.writeFile(settingsPath, `${JSON.stringify(settings || {}, null, 2)}\n`, "utf8");
  return {
    ok: true,
    path: settingsPath.replace(/\\/g, "/")
  };
}

async function webviewHtml(panel, extensionUri) {
  const webDir = sharedWebDir(extensionUri);
  const htmlPath = path.join(webDir, "index.html");
  const cssUri = panel.webview.asWebviewUri(vscode.Uri.file(path.join(webDir, "app.css")));
  const jsUri = panel.webview.asWebviewUri(vscode.Uri.file(path.join(webDir, "app.js")));
  let html = await fs.readFile(htmlPath, "utf8");
  html = html.replace('<script src="/webui.js"></script>', "");
  html = html.replace('href="app.css"', `href="${cssUri.toString()}"`);
  html = html.replace('src="app.js"', `src="${jsUri.toString()}"`);
  return html;
}

async function handleHostCall(extensionUri, method, payload) {
  const repoRoot = String(payload.repoRoot || workspaceRoot());
  if (method === "otterBootstrap") {
    return {
      ok: true,
      host: "vscode",
      appName: "Otter Repo Graph",
      defaultRepoRoot: repoRoot.replace(/\\/g, "/"),
      supportsFolderPicker: true,
      supportsCodexSend: true
    };
  }
  if (method === "otterAnalyze") {
    const args = ["snapshot", repoRoot];
    if (payload.includeTests === true) args.push("--include-tests");
    const graph = await runOtterCli(extensionUri, args);
    const summary = [];
    const functions = Array.isArray(graph.functions) ? graph.functions : [];
    const edges = Array.isArray(graph.edges) ? graph.edges : [];
    const groups = Array.isArray(graph.groups) ? graph.groups : [];
    summary.push(`Root: ${repoRoot.replace(/\\/g, "/")}`);
    summary.push(`Functions: ${functions.length}`);
    summary.push(`Edges: ${edges.length}`);
    summary.push(`Groups: ${groups.length}`);
    return { ok: true, summary, graph };
  }
  if (method === "otterRunFunction") {
    const functionId = String(payload.functionId || "");
    const args = ["run", repoRoot, functionId];
    if (payload.includeTests === true) args.push("--include-tests");
    return runOtterCli(extensionUri, args);
  }
  if (method === "otterChooseFolder") {
    return chooseFolder();
  }
  if (method === "otterSendAnnotations") {
    const annotations = Array.isArray(payload.annotations) ? payload.annotations : [];
    return sendAnnotationsToCodex(repoRoot, annotations);
  }
  if (method === "otterLoadViewSettings") {
    return loadViewSettings(repoRoot);
  }
  if (method === "otterSaveViewSettings") {
    return saveViewSettings(repoRoot, payload.settings || {});
  }
  return { ok: false, error: `unknown method: ${method}` };
}

async function openPanel(context) {
  const panel = vscode.window.createWebviewPanel(
    "otterRepoGraph",
    "Otter Repo Graph",
    vscode.ViewColumn.Active,
    {
      enableScripts: true,
      retainContextWhenHidden: true,
      localResourceRoots: [
        vscode.Uri.file(sharedWebDir(context.extensionUri)),
        context.extensionUri
      ]
    }
  );
  panel.webview.html = await webviewHtml(panel, context.extensionUri);
  panel.webview.onDidReceiveMessage(async (msg) => {
    if (!msg || msg.type !== "hostCall") return;
    try {
      const body = await handleHostCall(context.extensionUri, String(msg.method), msg.payload || {});
      panel.webview.postMessage({ type: "hostResponse", id: String(msg.id), body });
    } catch (error) {
      panel.webview.postMessage({
        type: "hostResponse",
        id: String(msg.id),
        body: { ok: false, error: error instanceof Error ? error.message : String(error) }
      });
    }
  });
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("otterRepoGraph.open", () => {
      void openPanel(context);
    })
  );
}

function deactivate() {}

module.exports = {
  activate,
  deactivate
};
