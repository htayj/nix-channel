// Install check: serve one legacy PhiloLogic KWIC page on loopback, run the
// installed launcher against it and read the workbook back.
//
// usage: node check-export.js LAUNCHER MODULE_DIRECTORY

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { createRequire } = require('module');

const [launcher, moduleDirectory] = process.argv.slice(2);
const ExcelJS = createRequire(path.join(moduleDirectory, 'main.js'))('exceljs');

// Each hit is a .content element directly followed by its citation; matches
// are text nodes two levels below a <b>.
const page = [
  '<html><body>',
  '<div class="content"> arma virumque <b><font>cano</font></b> Troiae qui',
  ' primus ab oris </div>',
  '<span><b> Verg. A. </b><a href="#"> 1.1 </a></span>',
  '<div class="content">quidve dolens <b><font>regina</font></b> deum tot',
  ' <b><font>volvere</font></b> casus</div>',
  '<span><b>Verg. A.</b><a href="#">1.9</a></span>',
  '</body></html>',
].join('');

// A workbook stores bold only when set, so plain runs read back without it.
const runs = (cell) =>
  cell.value.richText.map((run) => [run.font.bold === true, run.text]);

async function verify(workbookFile) {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(workbookFile);
  const sheet = workbook.getWorksheet('Data');

  assert.deepStrictEqual(
    ['A1', 'B1', 'C1', 'D1'].map((cell) => sheet.getCell(cell).value),
    ['Text', 'Extract', 'Work', 'Passage']);
  assert.strictEqual(sheet.rowCount, 3);

  assert.deepStrictEqual(runs(sheet.getCell('A2')), [
    [false, 'arma virumque '],
    [true, 'cano'],
    [false, ' Troiae qui primus ab oris'],
  ]);
  assert.deepStrictEqual(runs(sheet.getCell('B2')), [[true, 'cano']]);
  assert.strictEqual(sheet.getCell('C2').value, 'Verg. A.');
  assert.strictEqual(sheet.getCell('D2').value, '1.1');

  // The extract spans the first through the last match.
  assert.deepStrictEqual(runs(sheet.getCell('B3')), [
    [true, 'regina'],
    [false, ' deum tot '],
    [true, 'volvere'],
  ]);
  assert.strictEqual(sheet.getCell('D3').value, '1.9');
}

const server = http.createServer((request, response) => {
  response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  response.end(page);
});

server.listen(0, '127.0.0.1', () => {
  const url = `http://127.0.0.1:${server.address().port}/kwic`;
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'persephil-'));

  execFile(launcher, [url], { cwd: directory }, (error, stdout, stderr) => {
    server.close();
    process.stderr.write(stderr);
    assert.ifError(error);

    // Upstream prints the workbook name, and prints errors without failing.
    const written = fs.readdirSync(directory);
    assert.strictEqual(written.length, 1, stdout);
    assert.match(written[0],
                 /^Latin corpus search \d\d-\d\d-\d\d \d\d \d\d \d\d\.xlsx$/);
    assert.strictEqual(stdout.trim(), written[0]);

    verify(path.join(directory, written[0])).then(
      () => console.log(`persephil export verified: ${written[0]}`),
      (failure) => {
        console.error(failure);
        process.exit(1);
      });
  });
});
