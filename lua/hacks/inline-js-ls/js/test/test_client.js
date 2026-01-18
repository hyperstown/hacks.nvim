const cp = require('child_process');
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

  const initRes = await conn.sendRequest('initialize', {
    processId: process.pid,
    rootUri: null,
    capabilities: {}
  });
  await conn.sendNotification('initialized', {});

  const html = `<!doctype html>
<html>
<body>
<script>
function greet(name: string) {
  return 'hello ' + name;
}

const x = greet('world');
</script>
</body>
</html>`;

  const uri = 'file://' + __dirname + '/sample.html';

  await new Promise(r => setTimeout(r, 800));
  conn.sendNotification('textDocument/didOpen', { textDocument: { uri, languageId: 'html', version: 1, text: html } });
  await new Promise(r => setTimeout(r, 1000));

  // find position of 'greet' in the call
  const idx = html.indexOf("greet('world')");
  const pos = positionFromIndex(html, idx + 0);

  const hover = await conn.sendRequest('textDocument/hover', { textDocument: { uri }, position: pos });
  console.log('HOVER RESULT:', JSON.stringify(hover, null, 2));

  // test completion at position inside call
  const comp = await conn.sendRequest('textDocument/completion', { textDocument: { uri }, position: pos });
  console.log('COMPLETION RESULT: items=', (comp && comp.items && comp.items.length) || 0);

  server.kill();
  process.exit(0);
}

run().catch(e => { console.error(e); process.exit(1); });
