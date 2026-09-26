# central/

The only developer-run piece of Ink Frame: a static GitHub Pages site, published from
`site/` by `.github/workflows/pages.yml` to `https://psmyles.github.io/ink-frame/`.
It holds no data and no secrets.

| Path | Purpose |
|---|---|
| `site/join/` | Invite and "Use on another device" links: `/join#u=<project_url>&k=<publishable_key>[&c=<code>]` (u/k repeat once per frame). Opens `inkframe://join?…` on phones; on computers, says to paste the link into the app. The fragment never reaches the server. |
| `site/oauth/` | Supabase OAuth callback on phones: forwards `code`/`state` (or `error`) to `inkframe://supabase-oauth?…`. |
| `site/assets/links.js` | Link parsing and validation for both pages; tested by `tests/links_test.ts` (`deno test central/tests/`). |
| *(Phase 4)* `site/firmware/` | The signed firmware feed (PLAN.md §10). |

Preview locally: `deno run -A jsr:@std/http/file-server central/site`, then open
`http://localhost:4507/join/#u=https://<ref>.supabase.co&k=sb_publishable_…&c=ABCDE-FGHJK`.
