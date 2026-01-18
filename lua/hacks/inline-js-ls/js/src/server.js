#!/usr/bin/env node

const childProcess = require("child_process");
const path = require("path");
// const fs = require('fs');
const {
  createConnection,
  ProposedFeatures,
  TextDocuments,
} = require("vscode-languageserver");
const {
  StreamMessageReader,
  StreamMessageWriter,
  createMessageConnection,
} = require("vscode-jsonrpc");
const logger = require("./logger");

// initialize file logger (truncates previous log)
logger.init();
// Log raw stdin frames for debugging
process.stdin.on("data", (chunk) => {
  try {
    logger.debug("[raw-in] " + chunk.toString());
  } catch (e) { }
});
// Simple LSP frame parser (Buffer-based) to ensure we catch didOpen/didChange notifications
let __lsp_buffer = Buffer.alloc(0);
process.stdin.on("data", (chunk) => {
  try {
    // append buffer
    __lsp_buffer = Buffer.concat([__lsp_buffer, Buffer.from(chunk)]);
    while (true) {
      // find header terminator (supports CRLF CRLF or LF LF)
      let headerEndIdx = __lsp_buffer.indexOf("\r\n\r\n");
      let headerLen = 4;
      if (headerEndIdx === -1) {
        headerEndIdx = __lsp_buffer.indexOf("\n\n");
        headerLen = 2;
      }
      if (headerEndIdx === -1) break;
      const headerBuf = __lsp_buffer.slice(0, headerEndIdx).toString("ascii");
      const m = headerBuf.match(/Content-Length:\s*(\d+)/i);
      if (!m) {
        // drop invalid header
        __lsp_buffer = __lsp_buffer.slice(headerEndIdx + headerLen);
        continue;
      }
      const len = parseInt(m[1], 10);
      const bodyStart = headerEndIdx + headerLen;
      if (__lsp_buffer.length < bodyStart + len) break; // wait for full body
      const bodyBuf = __lsp_buffer.slice(bodyStart, bodyStart + len);
      __lsp_buffer = __lsp_buffer.slice(bodyStart + len);
      try {
        const bodyStr = bodyBuf.toString("utf8");
        const msg = JSON.parse(bodyStr);
        if (msg && msg.method === "textDocument/didOpen") {
          const td = msg.params && msg.params.textDocument;
          if (td && td.uri && td.text !== undefined) {
            const script = extractFirstScript(td.text);
            if (script) {
              (async () => {
                const vuri = await openVirtual(td.uri, script.content);
                docs.set(td.uri, {
                  text: td.text,
                  script,
                  virtualUri: vuri,
                  version: td.version || 1,
                  textDocumentUri: td.uri,
                });
                logger.info(`[parser] created entry for ${td.uri}`);
              })();
            } else {
              docs.set(td.uri, {
                text: td.text,
                script: null,
                virtualUri: null,
                version: td.version || 1,
                textDocumentUri: td.uri,
              });
            }
          }
        }
        if (msg && msg.method === "textDocument/didChange") {
          const td = msg.params && msg.params.textDocument;
          const changes = msg.params && msg.params.contentChanges;
          if (td && td.uri && changes && changes.length) {
            const text = changes[0].text;
            const script = extractFirstScript(text);
            const entry = docs.get(td.uri) || {
              version: 0,
              textDocumentUri: td.uri,
            };
            entry.text = text;
            entry.version = (entry.version || 0) + 1;
            if (script) {
              const vuri = entry.virtualUri || td.uri + ".__inline.ts";
              entry.script = script;
              entry.virtualUri = vuri;
              entry.textDocumentUri = td.uri;
              docs.set(td.uri, entry);
              changeVirtual(vuri, script.content, entry.version);
              logger.info(`[parser] changed entry for ${td.uri}`);
            } else {
              if (entry.virtualUri) closeVirtual(entry.virtualUri);
              entry.script = null;
              entry.virtualUri = null;
              docs.set(td.uri, entry);
            }
          }
        }
      } catch (e) {
        logger.error("[parser] JSON parse error " + e.message);
      }
    }
  } catch (e) { }
});
const connection = createConnection(
  new StreamMessageReader(process.stdin),
  new StreamMessageWriter(process.stdout),
  ProposedFeatures.all,
);
const documents = new TextDocuments();

let tsConn = null;
let tsProc = null;
let tsInitialized = false;

const docs = new Map(); // uri -> { text, script: { content, startOffset, endOffset }, virtualUri, version }

function positionToOffset(text, pos) {
  const lines = text.split("\n");
  let offset = 0;
  for (let i = 0; i < pos.line; i++) offset += lines[i].length + 1;
  offset += pos.character;
  return offset;
}

function offsetToPosition(text, offset) {
  const lines = text.split("\n");
  let remaining = offset;
  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i].length;
    if (remaining <= ln) return { line: i, character: remaining };
    remaining -= ln + 1;
  }
  return { line: lines.length - 1, character: lines[lines.length - 1].length };
}

function extractFirstScript(fullText) {
  const re = /<script\b[^>]*>([\s\S]*?)<\/script>/i;
  const m = re.exec(fullText);
  if (!m) return null;
  const content = m[1];
  const contentIndex = fullText.indexOf(content, m.index);
  if (contentIndex === -1) return null;
  const startOffset = contentIndex;
  const endOffset = startOffset + content.length;
  return { content, startOffset, endOffset };
}

function ensureTsServer() {
  if (tsConn) return;
  let cliPath = null;
  try {
    try {
      cliPath = require.resolve("typescript-language-server/lib/cli.js");
    } catch (e) {
      // newer package uses ESM entrypoint
      cliPath = require.resolve("typescript-language-server/lib/cli.mjs");
    }
  } catch (e) {
    cliPath = path.join(
      __dirname,
      "..",
      "node_modules",
      "typescript-language-server",
      "lib",
      "cli.mjs",
    );
  }
  tsProc = childProcess.spawn(process.execPath, [cliPath, "--stdio"], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  const reader = new StreamMessageReader(tsProc.stdout);
  const writer = new StreamMessageWriter(tsProc.stdin);
  tsConn = createMessageConnection(reader, writer);
  tsConn.listen();
  // forward diagnostics from tsserver: map virtual uri diagnostics back to original HTML
  tsConn.onNotification &&
    tsConn.onNotification("textDocument/publishDiagnostics", (params) => {
      try {
        const vuri = params.uri;
        // find entry which has this virtualUri
        let entry = null;
        for (const [k, v] of docs) {
          if (v.virtualUri === vuri) {
            entry = v;
            break;
          }
        }
        if (!entry) return;
        const mapped = (params.diagnostics || []).map((d) => {
          const nd = Object.assign({}, d);
          if (nd.range) {
            const startOff =
              positionToOffset(entry.script.content, nd.range.start) +
              entry.script.startOffset;
            const endOff =
              positionToOffset(entry.script.content, nd.range.end) +
              entry.script.startOffset;
            nd.range = {
              start: offsetToPosition(entry.text, startOff),
              end: offsetToPosition(entry.text, endOff),
            };
          }
          if (nd.relatedInformation && Array.isArray(nd.relatedInformation)) {
            nd.relatedInformation = nd.relatedInformation.map((info) => {
              if (info.location && info.location.range) {
                const s =
                  positionToOffset(
                    entry.script.content,
                    info.location.range.start,
                  ) + entry.script.startOffset;
                const e =
                  positionToOffset(
                    entry.script.content,
                    info.location.range.end,
                  ) + entry.script.startOffset;
                return Object.assign({}, info, {
                  location: {
                    uri: entry.textDocumentUri || info.location.uri,
                    range: {
                      start: offsetToPosition(entry.text, s),
                      end: offsetToPosition(entry.text, e),
                    },
                  },
                });
              }
              return info;
            });
          }
          return nd;
        });
        connection.sendNotification("textDocument/publishDiagnostics", {
          uri: entry.textDocumentUri || params.uri,
          diagnostics: mapped,
        });
      } catch (e) {
        logger.error("[proxy] diagnostics mapping error " + (e && e.message));
      }
    });
  // initialize the ts server so it accepts didOpen/requests
  (async () => {
    try {
      const res = await tsConn.sendRequest("initialize", {
        processId: process.pid,
        rootUri: null,
        capabilities: {},
      });
      tsConn.sendNotification("initialized", {});
      tsInitialized = true;
    } catch (e) {
      // ignore
    }
  })();
  tsProc.on("exit", () => {
    tsConn = null;
    tsProc = null;
  });
}

async function openVirtual(uri, script) {
  ensureTsServer();
  const vuri = uri + ".__inline.ts";
  const textDoc = {
    uri: vuri,
    languageId: "typescript",
    version: 1,
    text: script,
  };
  try {
    await tsConn.sendNotification("textDocument/didOpen", {
      textDocument: textDoc,
    });
  } catch (e) { }
  return vuri;
}

async function changeVirtual(vuri, script, version) {
  if (!tsConn) return;
  try {
    await tsConn.sendNotification("textDocument/didChange", {
      textDocument: { uri: vuri, version },
      contentChanges: [{ text: script }],
    });
  } catch (e) { }
}

async function closeVirtual(vuri) {
  if (!tsConn) return;
  try {
    await tsConn.sendNotification("textDocument/didClose", {
      textDocument: { uri: vuri },
    });
  } catch (e) { }
}

documents.onDidOpen(async (e) => {
  logger.info(`[proxy] onDidOpen ${e.document.uri}`);
  const uri = e.document.uri;
  const text = e.document.getText();
  const script = extractFirstScript(text);
  if (script) {
    const vuri = await openVirtual(uri, script.content);
    docs.set(uri, {
      text,
      script,
      virtualUri: vuri,
      version: 1,
      textDocumentUri: uri,
    });
  } else {
    docs.set(uri, {
      text,
      script: null,
      virtualUri: null,
      version: 1,
      textDocumentUri: uri,
    });
  }
});

documents.onDidChangeContent(async (change) => {
  const uri = change.document.uri;
  const text = change.document.getText();
  const entry = docs.get(uri) || { version: 0, textDocumentUri: uri };
  const script = extractFirstScript(text);
  entry.text = text;
  entry.version = (entry.version || 0) + 1;
  if (script) {
    const vuri = entry.virtualUri || uri + ".__inline.ts";
    entry.script = script;
    entry.virtualUri = vuri;
    entry.textDocumentUri = uri;
    docs.set(uri, entry);
    await changeVirtual(vuri, script.content, entry.version);
  } else {
    if (entry.virtualUri) {
      await closeVirtual(entry.virtualUri);
    }
    entry.script = null;
    entry.virtualUri = null;
    docs.set(uri, entry);
  }
});

function mapParamsToVirtual(params) {
  const uri = params.textDocument.uri;
  const entry = docs.get(uri);
  if (!entry || !entry.script) return null;
  const full = entry.text;
  const contentStart = entry.script.startOffset;
  const absOffset = positionToOffset(full, params.position);
  if (absOffset < contentStart || absOffset > entry.script.endOffset)
    return null;
  const virtualOffset = absOffset - contentStart;
  const virtualPos = offsetToPosition(entry.script.content, virtualOffset);
  const newParams = JSON.parse(JSON.stringify(params));
  newParams.textDocument = { uri: entry.virtualUri };
  newParams.position = virtualPos;
  return newParams;
}

function mapLocationFromVirtual(loc, entry) {
  if (!loc) return loc;
  if (Array.isArray(loc))
    return loc.map((l) => mapLocationFromVirtual(l, entry));
  if (loc.range) {
    const startOff =
      positionToOffset(entry.script.content, loc.range.start) +
      entry.script.startOffset;
    const endOff =
      positionToOffset(entry.script.content, loc.range.end) +
      entry.script.startOffset;
    const startPos = offsetToPosition(entry.text, startOff);
    const endPos = offsetToPosition(entry.text, endOff);
    return {
      uri: entry.textDocumentUri || loc.uri,
      range: { start: startPos, end: endPos },
    };
  }
  if (loc.start) {
    const off =
      positionToOffset(entry.script.content, loc.start) +
      entry.script.startOffset;
    const pos = offsetToPosition(entry.text, off);
    return {
      uri: entry.textDocumentUri || loc.uri,
      range: { start: pos, end: pos },
    };
  }
  return loc;
}

async function forwardRequestIfInScript(method, params) {
  const uri = params.textDocument && params.textDocument.uri;
  if (!uri) return null;
  const entry = docs.get(uri);
  logger.debug(`[proxy] method ${method} uri ${uri} hasEntry ${!!entry}`);
  if (!entry || !entry.script || !tsConn) return null;
  const full = entry.text;
  const contentStart = entry.script.startOffset;
  const absOffset = positionToOffset(full, params.position);
  logger.debug(
    `[proxy] absOffset ${absOffset} scriptRange ${contentStart} ${entry.script.endOffset}`,
  );
  if (absOffset < contentStart || absOffset > entry.script.endOffset)
    return null;
  const newParams = mapParamsToVirtual(params);
  logger.debug(
    `[proxy] mapped params ${!!newParams} ${newParams && JSON.stringify(newParams.position)}`,
  );
  if (!newParams) return null;
  try {
    logger.debug(
      `[proxy] forwarding ${method} to tsserver; tsConn=${!!tsConn} tsInitialized=${tsInitialized}`,
    );
    const res = await tsConn.sendRequest(method, newParams);
    try {
      logger.debug(
        `[proxy] tsserver responded for ${method} -> ${JSON.stringify(res).slice(0, 2000)}`,
      );
    } catch (e) { }
    // map results back
    if (!res) return res;
    // handle hover
    if (method === "textDocument/hover") {
      if (res.range) {
        const startOff =
          positionToOffset(entry.script.content, res.range.start) +
          entry.script.startOffset;
        const endOff =
          positionToOffset(entry.script.content, res.range.end) +
          entry.script.startOffset;
        res.range = {
          start: offsetToPosition(entry.text, startOff),
          end: offsetToPosition(entry.text, endOff),
        };
      }
      return res;
    }
    if (
      method === "textDocument/definition" ||
      method === "textDocument/references"
    ) {
      const mapped = Array.isArray(res)
        ? res.map((r) => mapLocationFromVirtual(r, entry))
        : mapLocationFromVirtual(res, entry);
      return mapped;
    }
    if (method === "textDocument/completion") {
      // map completion item textEdit ranges
      if (Array.isArray(res)) {
        return res;
      }
      if (res.items) {
        for (const it of res.items) {
          if (it.textEdit && it.textEdit.range) {
            const sOff =
              positionToOffset(entry.script.content, it.textEdit.range.start) +
              entry.script.startOffset;
            const eOff =
              positionToOffset(entry.script.content, it.textEdit.range.end) +
              entry.script.startOffset;
            it.textEdit.range = {
              start: offsetToPosition(entry.text, sOff),
              end: offsetToPosition(entry.text, eOff),
            };
          }
        }
      }
      return res;
    }
    return res;
  } catch (e) {
    logger.error("[proxy] tsserver request error " + (e && e.message));
    return null;
  }
}

connection.onInitialize(() => {
  return {
    capabilities: {
      textDocumentSync: documents.syncKind || 1,
      hoverProvider: true,
      completionProvider: { resolveProvider: false },
      definitionProvider: true,
      referencesProvider: true,
    },
  };
});

connection.onNotification("textDocument/didOpen", (params) => {
  try {
    const td = params && params.textDocument;
    const uri = td && td.uri;
    logger.info(`[proxy] raw didOpen notification ${uri}`);
    if (uri && td.text !== undefined) {
      const text = td.text;
      const script = extractFirstScript(text);
      if (script) {
        (async () => {
          const vuri = await openVirtual(uri, script.content);
          docs.set(uri, {
            text,
            script,
            virtualUri: vuri,
            version: td.version || 1,
            textDocumentUri: uri,
          });
        })();
      } else {
        docs.set(uri, {
          text,
          script: null,
          virtualUri: null,
          version: td.version || 1,
          textDocumentUri: uri,
        });
      }
    }
  } catch (e) {
    console.error(e);
  }
});

connection.onNotification("textDocument/didChange", (params) => {
  try {
    const td = params && params.textDocument;
    const uri = td && td.uri;
    const changes = params && params.contentChanges;
    if (uri && changes && changes.length) {
      const text = changes[0].text;
      const script = extractFirstScript(text);
      const entry = docs.get(uri) || { version: 0, textDocumentUri: uri };
      entry.text = text;
      entry.version = (entry.version || 0) + 1;
      if (script) {
        const vuri = entry.virtualUri || uri + ".__inline.ts";
        entry.script = script;
        entry.virtualUri = vuri;
        entry.textDocumentUri = uri;
        docs.set(uri, entry);
        changeVirtual(vuri, script.content, entry.version);
      } else {
        if (entry.virtualUri) closeVirtual(entry.virtualUri);
        entry.script = null;
        entry.virtualUri = null;
        docs.set(uri, entry);
      }
    }
  } catch (e) {
    console.error(e);
  }
});

connection.onHover(async (params) => {
  const res = await forwardRequestIfInScript("textDocument/hover", params);
  return res || null;
});

connection.onCompletion(async (params) => {
  const res = await forwardRequestIfInScript("textDocument/completion", params);
  return res || { items: [] };
});

connection.onDefinition(async (params) => {
  const res = await forwardRequestIfInScript("textDocument/definition", params);
  return res || null;
});

connection.onReferences(async (params) => {
  const res = await forwardRequestIfInScript("textDocument/references", params);
  return res || [];
});

documents.listen(connection);
connection.listen();

// process exit handling
process.on("exit", () => {
  if (tsProc) tsProc.kill();
});
