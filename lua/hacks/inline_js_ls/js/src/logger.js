const fs = require('fs');
const path = require('path');

const logDir = path.join(__dirname, '..', 'logs');
const logFile = path.join(logDir, 'lsp.log');

function ensureDir() {
  try {
    fs.mkdirSync(logDir, { recursive: true });
  } catch (e) {}
}

function init() {
  ensureDir();
  try {
    fs.writeFileSync(logFile, `[START][${new Date().toISOString()}] LSP logging initiated\n`);
  } catch (e) {
    // ignore
  }
}

function write(level, msg) {
  try {
    const line = `[${level}][${new Date().toISOString()}] ${msg}\n`;
    fs.appendFileSync(logFile, line);
  } catch (e) {
    // ignore
  }
}

module.exports = {
  init,
  info: (m) => write('INFO', m),
  warn: (m) => write('WARN', m),
  error: (m) => write('ERROR', m),
  debug: (m) => write('DEBUG', m),
  file: () => logFile,
};
