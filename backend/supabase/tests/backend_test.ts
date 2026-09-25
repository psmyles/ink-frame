// Integration tests against the dev project: PLAN.md §12.1 (scenario and RLS) plus
// the permission rules and error codes in shared/api/openapi.yaml.
//   deno test --allow-net --allow-env --allow-read backend/supabase/tests/
//
// One stateful scenario, in order. Everything it creates is removed at the end.

import { assert, assertEquals, assertExists, assertNotEquals } from "jsr:@std/assert@1";
import {
  addMember,
  admin,
  anon,
  call,
  cleanup,
  created,
  env,
  fetch,
  makePng,
  newUser,
  purgeLeftovers,
  sha256Hex,
  sql,
  upload,
  type User,
} from "./_lib.ts";

const expectError = (r: { status: number; body: any }, status: number, code: string) => {
  assertEquals(r.status, status, JSON.stringify(r.body));
  assertEquals(r.body?.error?.code, code, JSON.stringify(r.body));
};

async function pair(u: User, name: string, hwId: string, timezone?: string) {
  const t = await call("POST", "/app-api/pairing-tokens", { token: u.token, body: { frame_name: name, timezone } });
  assertEquals(t.status, 201, JSON.stringify(t.body));
  const c = await call("POST", "/device-api/claim", {
    body: { pairing_token: t.body.pairing_token, hw_id: hwId, model_id: "reterminal-e1002", fw_version: "0.0.0-test" },
  });
  assertEquals(c.status, 200, JSON.stringify(c.body));
  if (!created.frames.includes(c.body.frame_id)) created.frames.push(c.body.frame_id);
  return { frameId: c.body.frame_id as string, secret: c.body.device_secret as string, token: t.body.pairing_token };
}

const sync = (secret: string, manifest_version: number, local_ids: string[] = []) =>
  call("POST", "/device-api/sync", {
    token: secret,
    body: { manifest_version, fw_version: "0.0.0-test", battery_pct: 80, rssi: -60, sd_free_bytes: 1e9, local_ids },
  });

Deno.test({
  name: "backend scenario",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn(t) {
    const stale = await purgeLeftovers();
    if (stale) console.warn(`Removed ${stale} test users left by an interrupted run.`);
    const [{ admins }] = await sql<{ admins: number }>(env,
      "select count(*)::int as admins from public.project_members where role = 'admin'");
    if (admins > 0) {
      console.warn("The dev project already has an admin; these tests need to create their own. Skipping.");
      return;
    }

    const hw = (n: number) => `test-${crypto.randomUUID().slice(0, 8)}-${n}`;
    let A: User, B: User, C: User;
    let frame: { frameId: string; secret: string; token: string };
    let version = 0;
    const imageIds: string[] = [];
    const pngs: Uint8Array<ArrayBuffer>[] = [];

    try {
      await t.step("set up users", async () => {
        A = await newUser("admin");
        B = await newUser("member");
        C = await newUser("outsider");
        await addMember(A, "admin", "Alice");
        await addMember(B, "member", "Bob");
      });

      await t.step("only one admin per space", async () => {
        const err = await sql(env, `insert into public.project_members (user_id, role, display_name)
          values ('${C.id}', 'admin', 'X')`).catch((e) => String(e));
        assert(String(err).includes("project_members_one_admin"), String(err));
      });

      await t.step("pair: token, claim, token reuse, empty first sync", async () => {
        frame = await pair(A, "Test frame", hw(1), "Europe/Berlin");
        assertEquals(frame.secret.length, 43);
        const again = await call("POST", "/device-api/claim", {
          body: { pairing_token: frame.token, hw_id: hw(2), model_id: "reterminal-e1002", fw_version: "x" },
        });
        expectError(again, 401, "invalid_pairing_token");

        const s = await sync(frame.secret, 0);
        assertEquals(s.status, 200, JSON.stringify(s.body));
        assertEquals(s.body.images, []);
        assertEquals(s.body.settings, {
          image_interval_s: 14400, display_order: "random", sync_interval_s: 86400,
          quiet_start: null, quiet_end: null, tz_posix: "CET-1CEST,M3.5.0,M10.5.0/3",
        });
        assert(Math.abs(s.body.server_time - Date.now() / 1000) < 120);
        version = s.body.manifest_version;
      });

      await t.step("claim errors: unknown model, other owner's hardware", async () => {
        const tk = await call("POST", "/app-api/pairing-tokens", { token: B.token, body: { frame_name: "B's" } });
        const bad = await call("POST", "/device-api/claim", {
          body: { pairing_token: tk.body.pairing_token, hw_id: hw(3), model_id: "no-such-model", fw_version: "x" },
        });
        expectError(bad, 422, "unknown_model");
        const taken = await call("POST", "/device-api/claim", {
          body: {
            pairing_token: tk.body.pairing_token,
            hw_id: (await sql<{ hw_id: string }>(env, `select hw_id from public.frames where id = '${frame.frameId}'`))[0].hw_id,
            model_id: "reterminal-e1002", fw_version: "x",
          },
        });
        expectError(taken, 409, "hw_id_conflict");
      });

      await t.step("upload 3 photos", async () => {
        for (let i = 0; i < 3; i++) {
          const png = await makePng(800, 480, i);
          const r = await upload(A, frame.frameId, png);
          assertEquals(r.status, 200, JSON.stringify(r.body));
          assertEquals(r.body.status, "ready");
          assertEquals(r.body.position, i + 1);
          assertEquals(r.body.uploaded_by, A.id);
          assertEquals(r.body.sha256, await sha256Hex(png));
          imageIds.push(r.body.id);
          pngs.push(png);
        }
        // Finalize is idempotent.
        const again = await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: imageIds[0] } });
        assertEquals(again.status, 200);
      });

      await t.step("upload errors", async () => {
        const small = await makePng(640, 400, 9);
        expectError(await upload(A, frame.frameId, small, 640, 400), 422, "dimension_mismatch");

        const dup = await call("POST", "/app-api/images/request-upload", {
          token: A.token,
          body: { frame_id: frame.frameId, sha256: await sha256Hex(pngs[0]), bytes: pngs[0].length, width: 800, height: 480 },
        });
        expectError(dup, 409, "duplicate_image");
        assertEquals(dup.body.error.details.image_id, imageIds[0]);

        const big = await call("POST", "/app-api/images/request-upload", {
          token: A.token, body: { frame_id: frame.frameId, sha256: "a".repeat(64), bytes: 600000, width: 800, height: 480 },
        });
        expectError(big, 413, "too_large");

        // Declared size differs from the upload.
        const png = await makePng(800, 480, 10);
        const req = await call("POST", "/app-api/images/request-upload", {
          token: A.token,
          body: { frame_id: frame.frameId, sha256: await sha256Hex(png), bytes: png.length + 1, width: 800, height: 480 },
        });
        assertEquals(req.status, 200);
        const early = await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: req.body.image_id } });
        expectError(early, 409, "not_uploaded");
        const put = await fetch(req.body.upload_url, { method: "PUT", headers: { "Content-Type": "image/png" }, body: png });
        await put.body?.cancel();
        const fin = await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: req.body.image_id } });
        expectError(fin, 422, "size_mismatch");
        const gone = await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: req.body.image_id } });
        expectError(gone, 404, "image_not_found");

        // Not a PNG.
        const junk = new TextEncoder().encode("definitely not a png, just some bytes");
        const r2 = await call("POST", "/app-api/images/request-upload", {
          token: A.token,
          body: { frame_id: frame.frameId, sha256: await sha256Hex(junk), bytes: junk.length, width: 800, height: 480 },
        });
        const put2 = await fetch(r2.body.upload_url, { method: "PUT", headers: { "Content-Type": "image/png" }, body: junk });
        await put2.body?.cancel();
        const fin2 = await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: r2.body.image_id } });
        expectError(fin2, 422, "invalid_png");

        const bad = await call("POST", "/app-api/images/request-upload", { token: A.token, body: { frame_id: "nope" } });
        expectError(bad, 400, "invalid_request");
      });

      await t.step("sync downloads 3, checksums match", async () => {
        const s = await sync(frame.secret, version);
        assertEquals(s.status, 200);
        assertNotEquals(s.body.manifest_version, version);
        version = s.body.manifest_version;
        assertEquals(s.body.images.map((i: any) => i.id), imageIds);
        for (const [n, img] of s.body.images.entries()) {
          assertExists(img.url);
          const bytes = new Uint8Array(await (await fetch(img.url)).arrayBuffer());
          assertEquals(await sha256Hex(bytes), img.sha256);
          assertEquals(img.sha256, await sha256Hex(pngs[n]));
        }
      });

      await t.step("unchanged manifest omits images; local ids get no url", async () => {
        const same = await sync(frame.secret, version, imageIds);
        assertEquals(same.body.images, undefined);
        const full = await sync(frame.secret, 0, imageIds.slice(0, 2));
        assertEquals(full.body.images.length, 3);
        assertEquals(full.body.images.map((i: any) => Boolean(i.url)), [false, false, true]);
      });

      await t.step("RLS: outsiders and non-frame members see nothing", async () => {
        for (const table of ["frames", "images", "frame_settings", "frame_members", "project_members", "invites"]) {
          const { data, error } = await C.db.from(table).select("*");
          assertEquals(error, null);
          assertEquals(data, [], `outsider read ${table}`);
        }
        assertEquals((await B.db.from("frames").select("id")).data, []);
        assertEquals((await B.db.from("images").select("id")).data, []);
        assertEquals((await B.db.from("project_members").select("user_id")).data?.length, 2);
        assertEquals((await A.db.from("images").select("id")).data?.length, 3);

        const models = await anon.from("device_models").select("id");
        assert((models.data?.length ?? 0) >= 5);
        const { error } = await anon.from("project_members").select("*");
        assertExists(error, "anon must not read members");

        // Writes are refused even for the admin.
        const ins = await A.db.from("frames").update({ name: "hacked" }).eq("id", frame.frameId);
        assertExists(ins.error);

        const path = `${frame.frameId}/${imageIds[0]}.png`;
        assertExists((await A.db.storage.from("frame-images").createSignedUrl(path, 60)).data?.signedUrl);
        assertExists((await C.db.storage.from("frame-images").createSignedUrl(path, 60)).error);
        assertExists((await B.db.storage.from("frame-images").createSignedUrl(path, 60)).error);
      });

      await t.step("non-members are refused by app-api", async () => {
        expectError(await upload(B, frame.frameId, await makePng(800, 480, 20)), 403, "not_frame_member");
        expectError(await call("GET", "/app-api/usage", { token: C.token }), 403, "not_project_member");
        expectError(await call("POST", "/app-api/pairing-tokens", { token: C.token, body: { frame_name: "x" } }),
          403, "not_project_member");
      });

      await t.step("invites: frame invite, accept, revoke, errors", async () => {
        expectError(await call("POST", "/app-api/invites", { token: B.token, body: {} }), 403, "not_admin");
        expectError(await call("POST", "/app-api/invites", { token: B.token, body: { frame_id: frame.frameId } }),
          403, "not_frame_owner");

        const inv = await call("POST", "/app-api/invites", { token: A.token, body: { frame_id: frame.frameId } });
        assertEquals(inv.status, 201, JSON.stringify(inv.body));
        assert(/^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/.test(inv.body.code));
        assertEquals(inv.body.max_uses, 1);

        // Lowercase and without the hyphen is accepted.
        const acc = await call("POST", "/app-api/invites/accept", {
          token: B.token, body: { code: inv.body.code.replace("-", "").toLowerCase() },
        });
        assertEquals(acc.status, 200, JSON.stringify(acc.body));
        assertEquals(acc.body, { project_role: "member", frame_id: frame.frameId });
        assertEquals((await B.db.from("images").select("id")).data?.length, 3);

        // Used up.
        expectError(await call("POST", "/app-api/invites/accept", { token: C.token, body: { code: inv.body.code } }),
          404, "invalid_invite");
        expectError(await call("POST", "/app-api/invites/accept", { token: C.token, body: { code: "ZZZZZ-ZZZZZ" } }),
          404, "invalid_invite");

        const inv2 = await call("POST", "/app-api/invites", { token: A.token, body: {} });
        expectError(await call("POST", "/app-api/invites/accept", { token: C.token, body: { code: inv2.body.code } }),
          422, "display_name_required");
        assertEquals((await call("DELETE", `/app-api/invites/${inv2.body.invite_id}`, { token: A.token })).status, 204);
        expectError(await call("POST", "/app-api/invites/accept", {
          token: C.token, body: { code: inv2.body.code, display_name: "Carol" },
        }), 404, "invalid_invite");
      });

      await t.step("photo delete permissions; frame mirrors", async () => {
        const mine = await upload(B, frame.frameId, await makePng(800, 480, 30));
        assertEquals(mine.status, 200, JSON.stringify(mine.body));
        const other = await upload(B, frame.frameId, await makePng(800, 480, 31));

        const denied = await call("POST", "/app-api/images/delete", { token: B.token, body: { image_ids: [imageIds[0]] } });
        expectError(denied, 403, "not_allowed");
        assertEquals(denied.body.error.details.image_ids, [imageIds[0]]);

        const own = await call("POST", "/app-api/images/delete", { token: B.token, body: { image_ids: [mine.body.id] } });
        assertEquals(own.body, { deleted_ids: [mine.body.id] });
        const byOwner = await call("POST", "/app-api/images/delete", {
          token: A.token, body: { image_ids: [other.body.id, imageIds[2]] },
        });
        assertEquals(byOwner.status, 200);
        assertEquals(new Set(byOwner.body.deleted_ids), new Set([other.body.id, imageIds[2]]));
        imageIds.pop();

        const s = await sync(frame.secret, version, imageIds);
        assertEquals(s.body.images.map((i: any) => i.id), imageIds);
        version = s.body.manifest_version;

        // Deleted object is gone from Storage.
        const obj = await admin.storage.from("frame-images").download(`${frame.frameId}/${mine.body.id}.png`);
        assertExists(obj.error);
      });

      await t.step("reorder", async () => {
        expectError(await call("POST", "/app-api/images/reorder", {
          token: B.token, body: { image_id: imageIds[1], after_image_id: null },
        }), 403, "not_frame_owner");
        const r = await call("POST", "/app-api/images/reorder", {
          token: A.token, body: { image_id: imageIds[1], after_image_id: null },
        });
        assertEquals(r.status, 200, JSON.stringify(r.body));
        const s = await sync(frame.secret, version, imageIds);
        assertEquals(s.body.images.map((i: any) => i.id), [imageIds[1], imageIds[0]]);
        version = s.body.manifest_version;

        // Moving images into the gap right after I1 halves it each time; 60 moves
        // force a renumber part-way. Ends with I0 moved last: [I1, I0, x].
        const x = await upload(A, frame.frameId, await makePng(800, 480, 40));
        for (let i = 0; i < 60; i++) {
          const id = i % 2 ? imageIds[0] : x.body.id;
          const m = await call("POST", "/app-api/images/reorder", {
            token: A.token, body: { image_id: id, after_image_id: imageIds[1] },
          });
          assertEquals(m.status, 200, JSON.stringify(m.body));
        }
        const s2 = await sync(frame.secret, 0, []);
        assertEquals(s2.body.images.map((i: any) => i.id), [imageIds[1], imageIds[0], x.body.id]);
        // I1 sat at 0 before the loop; a renumber puts it at exactly 1.
        const pos = s2.body.images.map((i: any) => i.position);
        assertEquals(pos[0], 1, `renumbered: ${pos}`);
        assert(pos[0] < pos[1] && pos[1] < pos[2], `ordered: ${pos}`);
        imageIds.splice(0, imageIds.length, imageIds[1], imageIds[0], x.body.id);
        version = s2.body.manifest_version;
      });

      await t.step("settings", async () => {
        const path = `/app-api/frames/${frame.frameId}/settings`;
        const r = await call("PATCH", path, {
          token: A.token,
          body: { image_interval_s: 7200, quiet_start: "22:00", quiet_end: "07:00", timezone: "Asia/Kolkata" },
        });
        assertEquals(r.status, 200, JSON.stringify(r.body));
        assertEquals(r.body.image_interval_s, 7200);
        assertEquals(r.body.quiet_start, "22:00");

        const s = await sync(frame.secret, version, imageIds);
        assertEquals(s.body.settings.tz_posix, "IST-5:30");
        assertEquals(s.body.settings.quiet_end, "07:00");
        assertEquals(s.body.images, undefined, "settings changes don't bump the manifest");

        expectError(await call("PATCH", path, { token: A.token, body: { quiet_start: null } }), 422, "quiet_hours_incomplete");
        expectError(await call("PATCH", path, { token: A.token, body: { timezone: "Mars/Olympus" } }), 422, "unknown_timezone");
        expectError(await call("PATCH", path, { token: A.token, body: { sync_interval_s: 600 } }), 400, "invalid_request");
        expectError(await call("PATCH", path, { token: A.token, body: {} }), 400, "invalid_request");
        expectError(await call("PATCH", path, { token: B.token, body: { display_order: "sequential" } }), 403, "not_frame_owner");

        const cleared = await call("PATCH", path, { token: A.token, body: { quiet_start: null, quiet_end: null } });
        assertEquals(cleared.body.quiet_start, null);
      });

      await t.step("rename; usage", async () => {
        const r = await call("PATCH", `/app-api/frames/${frame.frameId}`, { token: A.token, body: { name: "  Kitchen  " } });
        assertEquals(r.body, { frame_id: frame.frameId, name: "Kitchen" });

        const u = await call("GET", "/app-api/usage", { token: A.token });
        assertEquals(u.status, 200);
        assertEquals(u.body.project.free_tier_bytes, 1024 ** 3);
        const f = u.body.frames.find((x: any) => x.frame_id === frame.frameId);
        assertEquals(f.images, 3);
        assertEquals(u.body.users.length >= 2, true, "admin sees every member");
        const ub = await call("GET", "/app-api/usage", { token: B.token });
        assertEquals(ub.body.users.map((x: any) => x.user_id), [B.id]);
      });

      await t.step("quota", async () => {
        await sql(env, "update public.quota_config set max_images = 3 where scope = 'frame'");
        try {
          const r = await upload(A, frame.frameId, await makePng(800, 480, 50));
          expectError(r, 422, "quota_exceeded");
          assertEquals(r.body.error.details, { scope: "frame", limit: 3, used: 3, unit: "images" });
        } finally {
          await sql(env, "update public.quota_config set max_images = null where scope = 'frame'");
        }
      });

      await t.step("re-claim by the same owner rotates the secret", async () => {
        const [{ hw_id }] = await sql<{ hw_id: string }>(env, `select hw_id from public.frames where id = '${frame.frameId}'`);
        const again = await pair(A, "ignored", hw_id);
        assertEquals(again.frameId, frame.frameId);
        expectError(await sync(frame.secret, 0), 401, "invalid_device_secret");
        const s = await sync(again.secret, 0);
        assertEquals(s.body.images.length, 3, "photos kept");
        frame = again;
      });

      await t.step("frame members: leave, remove, owner can't be removed", async () => {
        const base = `/app-api/frames/${frame.frameId}/members`;
        expectError(await call("DELETE", `${base}/${A.id}`, { token: A.token }), 403, "cannot_remove_owner");
        expectError(await call("DELETE", `${base}/${A.id}`, { token: B.token }), 403, "not_allowed");
        assertEquals((await call("DELETE", `${base}/${B.id}`, { token: B.token })).status, 204);
        assertEquals((await B.db.from("frames").select("id")).data, []);
        expectError(await call("DELETE", `${base}/${B.id}`, { token: A.token }), 404, "member_not_found");
      });

      await t.step("member deletes account: frames pass to admin, photos stay", async () => {
        const D = await newUser("leaver");
        await addMember(D, "member", "Dana");
        const f = await pair(D, "Dana's frame", hw(4));
        const p = await upload(D, f.frameId, await makePng(800, 480, 60));
        assertEquals(p.status, 200);

        assertEquals((await call("DELETE", "/app-api/me", { token: D.token })).status, 204);
        const owner = await sql<{ user_id: string }>(env,
          `select user_id from public.frame_members where frame_id = '${f.frameId}' and role = 'owner'`);
        assertEquals(owner, [{ user_id: A.id }]);
        const [img] = await sql<{ uploaded_by: string | null }>(env,
          `select uploaded_by from public.images where id = '${p.body.id}'`);
        assertEquals(img.uploaded_by, null);
        assertEquals((await sync(f.secret, 0)).status, 200);
        const gone = await admin.auth.admin.getUserById(D.id);
        assertExists(gone.error, "auth user deleted");
      });

      await t.step("member deletes account with delete_photos", async () => {
        const E = await newUser("eraser");
        await addMember(E, "member", "Eve");
        const inv = await call("POST", "/app-api/invites", { token: A.token, body: { frame_id: frame.frameId } });
        await call("POST", "/app-api/invites/accept", { token: E.token, body: { code: inv.body.code } });
        const p = await upload(E, frame.frameId, await makePng(800, 480, 70));
        assertEquals(p.status, 200);
        const before = (await sync(frame.secret, 0)).body.manifest_version;

        expectError(await call("DELETE", "/app-api/me?delete_photos=maybe", { token: E.token }), 400, "invalid_request");
        assertEquals((await call("DELETE", "/app-api/me?delete_photos=true", { token: E.token })).status, 204);
        const s = await sync(frame.secret, before);
        assertNotEquals(s.body.manifest_version, before);
        assert(!s.body.images.some((i: any) => i.id === p.body.id));
      });

      await t.step("admin removes a member: frames pass to admin, photos stay", async () => {
        const inv = await call("POST", "/app-api/invites", { token: A.token, body: { frame_id: frame.frameId } });
        await call("POST", "/app-api/invites/accept", { token: B.token, body: { code: inv.body.code } });
        const p = await upload(B, frame.frameId, await makePng(800, 480, 80));
        const fb = await pair(B, "Bob's frame", hw(5));

        expectError(await call("DELETE", `/app-api/project-members/${A.id}`, { token: A.token }), 403, "cannot_remove_self");
        expectError(await call("DELETE", `/app-api/project-members/${A.id}`, { token: B.token }), 403, "not_admin");
        assertEquals((await call("DELETE", `/app-api/project-members/${B.id}`, { token: A.token })).status, 204);

        expectError(await call("GET", "/app-api/usage", { token: B.token }), 403, "not_project_member");
        const owner = await sql<{ user_id: string }>(env,
          `select user_id from public.frame_members where frame_id = '${fb.frameId}' and role = 'owner'`);
        assertEquals(owner, [{ user_id: A.id }]);
        const [img] = await sql<{ n: number }>(env, `select count(*)::int as n from public.images where id = '${p.body.id}'`);
        assertEquals(img.n, 1);
      });

      await t.step("delete frame → 410", async () => {
        expectError(await call("DELETE", `/app-api/frames/${frame.frameId}`, { token: C.token }), 403, "not_project_member");
        assertEquals((await call("DELETE", `/app-api/frames/${frame.frameId}`, { token: A.token })).status, 204);
        expectError(await sync(frame.secret, 0), 410, "frame_removed");
        const [{ n }] = await sql<{ n: number }>(env,
          `select count(*)::int as n from storage.objects where bucket_id = 'frame-images' and name like '${frame.frameId}/%'`);
        assertEquals(n, 0, "objects deleted");
      });

      await t.step("admin deletes account: their frames are removed", async () => {
        const [{ frame_id }] = await sql<{ frame_id: string }>(env,
          `select frame_id from public.frame_members where user_id = '${A.id}' and role = 'owner' limit 1`);
        assert(created.frames.includes(frame_id));
        assertEquals((await call("DELETE", "/app-api/me", { token: A.token })).status, 204);
        const [{ n }] = await sql<{ n: number }>(env,
          `select count(*)::int as n from public.frames where id = '${frame_id}'`);
        assertEquals(n, 0);
        const [{ admins: left }] = await sql<{ admins: number }>(env,
          "select count(*)::int as admins from public.project_members where role = 'admin'");
        assertEquals(left, 0);
      });
    } finally {
      await cleanup();
    }
  },
});
