const cp = require('child_process');
const fs = require('fs');
const { StreamMessageReader, StreamMessageWriter, createMessageConnection } = require('vscode-jsonrpc');

function positionFromIndex(text, index) {
  const lines = text.split('\n');
  let off = 0;
  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i];
    if (index <= off + ln.length) return { line: i, character: index - off };
    off += ln.length + 1;
  }
  return { line: lines.length - 1, character: lines[lines.length - 1].length };
}

async function run() {
  const server = cp.spawn(process.execPath, ['src/server.js'], { cwd: process.cwd(), stdio: ['pipe', 'pipe', 'inherit'] });
  const reader = new StreamMessageReader(server.stdout);
  const writer = new StreamMessageWriter(server.stdin);
  const conn = createMessageConnection(reader, writer);
  conn.listen();

  await conn.sendRequest('initialize', { processId: process.pid, rootUri: null, capabilities: {} });
  await conn.sendNotification('initialized', {});

  const path = 'test/dj.html';
  const html = fs.readFileSync(path, 'utf8');
  const uri = 'file://' + require('path').resolve(path);

  await new Promise(r => setTimeout(r, 400));
  conn.sendNotification('textDocument/didOpen', { textDocument: { uri, languageId: 'html', version: 1, text: html } });
  await new Promise(r => setTimeout(r, 1200));

  // find createAutocomplete usage inside script
  const idx = html.indexOf('createAutocomplete');
  if (idx === -1) {
    console.error('symbol not found');
    process.exit(1);
  }
  const pos = positionFromIndex(html, idx + 0);

  const hover = await conn.sendRequest('textDocument/hover', { textDocument: { uri }, position: pos });
  console.log('DJ HOVER:', JSON.stringify(hover, null, 2));

  const comp = await conn.sendRequest('textDocument/completion', { textDocument: { uri }, position: pos });
  console.log('DJ COMPLETION: items=', (comp && comp.items && comp.items.length) || 0);

  server.kill();
  process.exit(0);
}

run().catch(e => { console.error(e); process.exit(1); });
