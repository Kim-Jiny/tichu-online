'use strict';
/**
 * Every ALTER TABLE must come after the CREATE TABLE it alters.
 *
 * initDatabase runs top to bottom in one pass, and an existing database hides
 * the ordering completely: `ALTER TABLE tc_notices ADD COLUMN IF NOT EXISTS ...`
 * placed 1200 lines above `CREATE TABLE IF NOT EXISTS tc_notices` works
 * perfectly on every machine that already has the table. On an empty one it
 * throws, the migration aborts half-built, and the server never finishes
 * starting — which is what a fresh dev clone, a new staging database or a
 * restore-into-an-empty-instance all are. It cost six tests that spin up their
 * own database before anyone noticed.
 *
 * A static read of the file rather than a live migration: this has to fail on
 * a machine with no Postgres at all, since that is where the ordering is
 * easiest to get wrong and hardest to notice.
 *
 * Run: node server/test_migration_order.js
 */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'db', 'database.js');
const lines = fs.readFileSync(SRC, 'utf8').split('\n');

const createdAt = new Map();
lines.forEach((line, i) => {
  const m = /CREATE TABLE (?:IF NOT EXISTS )?([a-zA-Z_][\w]*)/.exec(line);
  if (m && !createdAt.has(m[1])) createdAt.set(m[1], i + 1);
});

const problems = [];
let alters = 0;
lines.forEach((line, i) => {
  const m = /ALTER TABLE (?:IF EXISTS )?([a-zA-Z_][\w]*)/.exec(line);
  if (!m) return;
  alters++;
  const table = m[1];
  const lineNo = i + 1;
  const created = createdAt.get(table);
  if (created === undefined) {
    problems.push(`${lineNo}행: ALTER TABLE ${table} — 이 파일에 CREATE 문이 없습니다`);
  } else if (lineNo < created) {
    problems.push(`${lineNo}행: ALTER TABLE ${table} — CREATE 는 ${created}행에 있습니다`);
  }
});

console.log(`migration order — ALTER ${alters}개 검사, CREATE ${createdAt.size}개 발견`);
if (alters === 0 || createdAt.size === 0) {
  // The regexes stopped matching, so the check is silently passing everything.
  console.log('  FAIL 아무것도 못 찾았습니다 — 검사 자체가 고장났습니다');
  process.exit(1);
}
for (const p of problems) console.log(`  FAIL ${p}`);
console.log(problems.length === 0 ? '\nPASS' : `\n${problems.length} FAILURE(S)`);
process.exit(problems.length === 0 ? 0 : 1);
