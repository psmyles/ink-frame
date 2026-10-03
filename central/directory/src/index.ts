// Cloudflare Worker entry: the directory (shared/api/directory.yaml), with D1 as DB.

import clients from "../../../shared/oauth-clients.json" with { type: "json" };
import { type Db, directory, purgeTokens } from "./directory.ts";
import { IdTokenVerifier, remoteKeys } from "./id_token.ts";

interface Env {
  DB: Db;
}

// Module scope, so the providers' keys stay cached while the isolate lives.
const verifier = new IdTokenVerifier(
  { google: Object.values(clients.google), apple: [clients.apple.bundleId] },
  remoteKeys(),
);

export default {
  fetch: (req: Request, env: Env) => directory({ db: env.DB, verifier })(req),
  scheduled: (_controller: unknown, env: Env) => purgeTokens(env.DB),
};
