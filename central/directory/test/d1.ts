// D1's API over node:sqlite, with the Worker's migrations applied.

import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import type { Db, Stmt } from "../src/directory.ts";

export function testDb(): Db & { raw: DatabaseSync } {
  const raw = new DatabaseSync(":memory:");
  const dir = new URL("../migrations/", import.meta.url);
  for (const f of [...Deno.readDirSync(dir)].map((e) => e.name).sort()) {
    raw.exec(Deno.readTextFileSync(new URL(f, dir)));
  }
  const stmt = (sql: string, args: unknown[] = []): Stmt => {
    const run = () => raw.prepare(sql);
    const values = args as SQLInputValue[];
    return {
      bind: (...a) => stmt(sql, a),
      first: <T>() => Promise.resolve((run().get(...values) as T | undefined) ?? null).then((r) => r && { ...r }),
      all: <T>() => Promise.resolve({ results: run().all(...values).map((r) => ({ ...r }) as T) }),
      run: () => Promise.resolve(run().run(...values)),
    };
  };
  return {
    raw,
    prepare: (sql) => stmt(sql),
    async batch(statements) {
      raw.exec("begin");
      try {
        const out = [];
        for (const s of statements) out.push(await s.run());
        raw.exec("commit");
        return out;
      } catch (e) {
        raw.exec("rollback");
        throw e;
      }
    },
  };
}
