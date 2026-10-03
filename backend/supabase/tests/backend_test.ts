// Integration tests against a frame project: PLAN.md §12.1 (scenario and RLS) plus
// the permission rules and error codes in shared/api/openapi.yaml.
//   deno test --allow-net --allow-env --allow-read backend/supabase/tests/
//
// One stateful scenario, in order. It sets up the project's frame and owner itself,
// so it skips a project that already has a real owner. Everything it creates is
// removed at the end.

import { assert, assertEquals, assertExists, assertNotEquals } from "jsr:@std/assert@1";
import {
  addMember,
  admin,
  anon,
  call,
  cleanup,
  env,
  fetch,
  hasRealFrame,
  makePng,
  newUser,
  purgeLeftovers,
  sha256Hex,
  setupFrame,
  sql,
  upload,
  type User,
} from "./_lib.ts";

const expectError = (r: { status: number; body: any }, status: number, code: string) => {
  assertEquals(r.status, status, JSON.stringify(r.body));
  assertEquals(r.body?.error?.code, code, JSON.stringify(r.body));
};

const hw = (n: number) => `test-${crypto.randomUUID().slice(0, 8)}-${n}`;

async function connect(owner: User, hwId: string, modelId = "reterminal-e1002") {
  const t = await call("POST", "/app-api/pairing-tokens", { token: owner.token });
  assertEquals(t.status, 201, JSON.stringify(t.body));
  const c = await call("POST", "/device-api/claim", {
    body: { pairing_token: t.body.pairing_token, hw_id: hwId, model_id: modelId, fw_version: "0.0.0-test" },
  });
  return { res: c, token: t.body.pairing_token as string, secret: c.body?.device_secret as string };
}

const sync = (secret: string, manifest_version: number, local_ids: string[] = []) =>
  call("POST", "/device-api/sync", {
    token: secret,
    body: { manifest_version, fw_version: "0.0.0-test", battery_pct: 80, rssi: -60, sd_free_bytes: 1e9, local_ids },
  });

const invite = async (owner: User, body: Record<string, unknown> = {}) => {
  const r = await call("POST", "/app-api/invites", { token: owner.token, body });
  assertEquals(r.status, 201, JSON.stringify(r.body));
  return r.body as { invite_id: string; code: string };
};

Deno.test({
  name: "backend scenario",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn(t) {
    const stale = await purgeLeftovers();
    if (stale) console.warn(`Removed ${stale} test users left by an interrupted run.`);
    if (await hasRealFrame()) {
      console.warn("This project already has a real frame owner; the tests need an empty project. Skipping.");
      return;
    }

    let A: User, B: User, C: User;
    let frameId = "";
    let device = { secret: "", hwId: "" };
    let version = 0;
    const imageIds: string[] = [];
    const pngs: Uint8Array<ArrayBuffer>[] = [];
    const upToDate = async () => (await A.db.from("frame").select("up_to_date").single()).data?.up_to_date;

    try {
      await t.step("set up: frame, owner, member, outsider", async () => {
        A = await newUser("owner");
        B = await newUser("member");
        C = await newUser("outsider");
        frameId = await setupFrame(A, "Alice");
        await addMember(B, "Bob");
      });

      await t.step("one frame and one owner per project", async () => {
        const f = await sql(env, "select private.setup_frame('Second', 'reterminal-e1002', 'UTC')").catch(String);
        assert(String(f).includes("frame_singleton_key"), String(f));
        const o = await sql(env, `insert into public.members (user_id, role, display_name) values ('${C.id}', 'owner', 'X')`)
          .catch(String);
        assert(String(o).includes("members_one_owner"), String(o));
      });

      await t.step("connect: token, claim, token reuse, empty first sync", async () => {
        device.hwId = hw(1);
        const c = await connect(A, device.hwId);
        assertEquals(c.res.status, 200, JSON.stringify(c.res.body));
        assertEquals(c.res.body.frame_id, frameId);
        assertEquals(c.secret.length, 43);
        device.secret = c.secret;

        const again = await call("POST", "/device-api/claim", {
          body: { pairing_token: c.token, hw_id: hw(2), model_id: "reterminal-e1002", fw_version: "x" },
        });
        expectError(again, 401, "invalid_pairing_token");

        const s = await sync(device.secret, 0);
        assertEquals(s.status, 200, JSON.stringify(s.body));
        assertEquals(s.body.images, []);
        assertEquals(s.body.settings, {
          image_interval_s: 14400, display_order: "random", sync_interval_s: 86400,
          quiet_start: null, quiet_end: null, tz_posix: "CET-1CEST,M3.5.0,M10.5.0/3",
        });
        assert(Math.abs(s.body.server_time - Date.now() / 1000) < 120);
        version = s.body.manifest_version;
        assertEquals(await upToDate(), true);
      });

      await t.step("claim errors: wrong model, unknown model, not the owner", async () => {
        expectError(await call("POST", "/app-api/pairing-tokens", { token: B.token }), 403, "not_owner");
        const t1 = await call("POST", "/app-api/pairing-tokens", { token: A.token });
        const claim = (model: string) => call("POST", "/device-api/claim", {
          body: { pairing_token: t1.body.pairing_token, hw_id: hw(3), model_id: model, fw_version: "x" },
        });
        const wrong = await claim("pimoroni-7-3");
        expectError(wrong, 409, "model_mismatch");
        assertEquals(wrong.body.error.details, { frame_model: "reterminal-e1002", device_model: "pimoroni-7-3" });
        expectError(await claim("no-such-model"), 422, "unknown_model");
        // Failed claims don't use up the token or disturb the connected device.
        assertEquals((await sync(device.secret, version)).status, 200);
      });

      await t.step("upload 3 photos", async () => {
        for (let i = 0; i < 3; i++) {
          const png = await makePng(800, 480, i);
          const r = await upload(A, png);
          assertEquals(r.status, 200, JSON.stringify(r.body));
          assertEquals(r.body.status, "ready");
          assertEquals(r.body.position, i + 1);
          assertEquals(r.body.uploaded_by, A.id);
          assertEquals(r.body.sha256, await sha256Hex(png));
          imageIds.push(r.body.id);
          pngs.push(png);
        }
        const again = await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: imageIds[0] } });
        assertEquals(again.status, 200, "finalize is idempotent");
        assertEquals(await upToDate(), false, "changes waiting");
      });

      await t.step("upload errors", async () => {
        expectError(await upload(A, await makePng(640, 400, 9), 640, 400), 422, "dimension_mismatch");

        const dup = await call("POST", "/app-api/images/request-upload", {
          token: A.token, body: { sha256: await sha256Hex(pngs[0]), bytes: pngs[0].length, width: 800, height: 480 },
        });
        expectError(dup, 409, "duplicate_image");
        assertEquals(dup.body.error.details.image_id, imageIds[0]);

        const big = await call("POST", "/app-api/images/request-upload", {
          token: A.token, body: { sha256: "a".repeat(64), bytes: 600000, width: 800, height: 480 },
        });
        expectError(big, 413, "too_large");

        // Declared size differs from the upload.
        const png = await makePng(800, 480, 10);
        const req = await call("POST", "/app-api/images/request-upload", {
          token: A.token, body: { sha256: await sha256Hex(png), bytes: png.length + 1, width: 800, height: 480 },
        });
        assertEquals(req.status, 200);
        expectError(await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: req.body.image_id } }),
          409, "not_uploaded");
        await (await fetch(req.body.upload_url, { method: "PUT", headers: { "Content-Type": "image/png" }, body: png })).body?.cancel();
        expectError(await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: req.body.image_id } }),
          422, "size_mismatch");
        expectError(await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: req.body.image_id } }),
          404, "image_not_found");

        // Not a PNG.
        const junk = new TextEncoder().encode("definitely not a png, just some bytes");
        const r2 = await call("POST", "/app-api/images/request-upload", {
          token: A.token, body: { sha256: await sha256Hex(junk), bytes: junk.length, width: 800, height: 480 },
        });
        await (await fetch(r2.body.upload_url, { method: "PUT", headers: { "Content-Type": "image/png" }, body: junk })).body?.cancel();
        expectError(await call("POST", "/app-api/images/finalize", { token: A.token, body: { image_id: r2.body.image_id } }),
          422, "invalid_png");

        expectError(await call("POST", "/app-api/images/request-upload", { token: A.token, body: { sha256: "nope" } }),
          400, "invalid_request");
      });

      await t.step("sync downloads 3, checksums match", async () => {
        const s = await sync(device.secret, version);
        assertNotEquals(s.body.manifest_version, version);
        version = s.body.manifest_version;
        assertEquals(s.body.images.map((i: any) => i.id), imageIds);
        for (const [n, img] of s.body.images.entries()) {
          assertExists(img.url);
          const bytes = new Uint8Array(await (await fetch(img.url)).arrayBuffer());
          assertEquals(await sha256Hex(bytes), img.sha256);
          assertEquals(img.sha256, await sha256Hex(pngs[n]));
        }
        assertEquals(await upToDate(), true);
      });

      await t.step("unchanged manifest omits images; local ids get no url", async () => {
        assertEquals((await sync(device.secret, version, imageIds)).body.images, undefined);
        const full = await sync(device.secret, 0, imageIds.slice(0, 2));
        assertEquals(full.body.images.map((i: any) => Boolean(i.url)), [false, false, true]);
      });

      await t.step("RLS: members read, outsiders see nothing, nobody writes", async () => {
        for (const table of ["frame", "images", "members", "invites", "quota_config"]) {
          const { data, error } = await C.db.from(table).select("*");
          assertEquals(error, null);
          assertEquals(data, [], `outsider read ${table}`);
        }
        const frame = await B.db.from("frame").select("id, name, model_id");
        assertEquals(frame.data, [{ id: frameId, name: "Test frame", model_id: "reterminal-e1002" }]);
        assertEquals((await B.db.from("images").select("id")).data?.length, 3);
        assertEquals((await B.db.from("members").select("user_id")).data?.length, 2);
        assertEquals((await A.db.from("invites").select("id")).error, null);

        assert(((await anon.from("device_models").select("id")).data?.length ?? 0) >= 5);
        assertExists((await anon.from("members").select("*")).error, "anon must not read members");
        assertExists((await A.db.from("frame").update({ name: "hacked" }).eq("id", frameId)).error, "no direct writes");

        const path = `${imageIds[0]}.png`;
        assertExists((await B.db.storage.from("frame-images").createSignedUrl(path, 60)).data?.signedUrl);
        assertExists((await C.db.storage.from("frame-images").createSignedUrl(path, 60)).error);
      });

      await t.step("non-members are refused by app-api", async () => {
        expectError(await upload(C, await makePng(800, 480, 20)), 403, "not_member");
        expectError(await call("GET", "/app-api/usage", { token: C.token }), 403, "not_member");
      });

      await t.step("invites: owner only, accept, reuse, revoke", async () => {
        expectError(await call("POST", "/app-api/invites", { token: B.token, body: {} }), 403, "not_owner");
        const inv = await invite(A);
        assert(/^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/.test(inv.code));

        const code = inv.code.replace("-", "").toLowerCase(); // case and hyphen don't matter
        expectError(await call("POST", "/app-api/invites/accept", { token: C.token, body: { code } }),
          422, "display_name_required");
        const acc = await call("POST", "/app-api/invites/accept", { token: C.token, body: { code, display_name: " Carol " } });
        assertEquals(acc.body, { role: "member" });
        assertEquals((await C.db.from("images").select("id")).data?.length, 3);
        const [{ display_name }] = await sql<{ display_name: string }>(env,
          `select display_name from public.members where user_id = '${C.id}'`);
        assertEquals(display_name, "Carol");

        const D = await newUser("latecomer");
        expectError(await call("POST", "/app-api/invites/accept", { token: D.token, body: { code: inv.code, display_name: "D" } }),
          404, "invalid_invite");
        expectError(await call("POST", "/app-api/invites/accept", { token: D.token, body: { code: "ZZZZZ-ZZZZZ", display_name: "D" } }),
          404, "invalid_invite");

        const inv2 = await invite(A);
        expectError(await call("DELETE", `/app-api/invites/${inv2.invite_id}`, { token: B.token }), 403, "not_owner");
        assertEquals((await call("DELETE", `/app-api/invites/${inv2.invite_id}`, { token: A.token })).status, 204);
        expectError(await call("POST", "/app-api/invites/accept", { token: D.token, body: { code: inv2.code, display_name: "D" } }),
          404, "invalid_invite");

        // An existing member accepting doesn't use up an invite.
        const inv3 = await invite(A);
        assertEquals((await call("POST", "/app-api/invites/accept", { token: B.token, body: { code: inv3.code } })).body,
          { role: "member" });
        assertEquals((await call("POST", "/app-api/invites/accept", { token: D.token, body: { code: inv3.code, display_name: "D" } })).status,
          200);
      });

      await t.step("photo delete permissions; frame mirrors", async () => {
        const mine = await upload(B, await makePng(800, 480, 30));
        assertEquals(mine.status, 200, JSON.stringify(mine.body));
        const other = await upload(B, await makePng(800, 480, 31));

        const denied = await call("POST", "/app-api/images/delete", { token: B.token, body: { image_ids: [imageIds[0], mine.body.id] } });
        expectError(denied, 403, "not_allowed");
        assertEquals(denied.body.error.details.image_ids, [imageIds[0]]);

        assertEquals((await call("POST", "/app-api/images/delete", { token: B.token, body: { image_ids: [mine.body.id] } })).body,
          { deleted_ids: [mine.body.id] });
        const byOwner = await call("POST", "/app-api/images/delete", { token: A.token, body: { image_ids: [other.body.id, imageIds[2]] } });
        assertEquals(new Set(byOwner.body.deleted_ids), new Set([other.body.id, imageIds[2]]));
        imageIds.pop();

        const s = await sync(device.secret, version, imageIds);
        assertEquals(s.body.images.map((i: any) => i.id), imageIds);
        version = s.body.manifest_version;
        assertExists((await admin.storage.from("frame-images").download(`${mine.body.id}.png`)).error, "object deleted");
      });

      await t.step("reorder", async () => {
        expectError(await call("POST", "/app-api/images/reorder", { token: B.token, body: { image_id: imageIds[1], after_image_id: null } }),
          403, "not_owner");
        const r = await call("POST", "/app-api/images/reorder", { token: A.token, body: { image_id: imageIds[1], after_image_id: null } });
        assertEquals(r.status, 200, JSON.stringify(r.body));
        const s = await sync(device.secret, version, imageIds);
        assertEquals(s.body.images.map((i: any) => i.id), [imageIds[1], imageIds[0]]);

        // Moving images into the gap right after I1 halves it each time; 60 moves
        // force a renumber part-way. Ends with I0 moved last: [I1, I0, x].
        const x = await upload(A, await makePng(800, 480, 40));
        for (let i = 0; i < 60; i++) {
          const m = await call("POST", "/app-api/images/reorder", {
            token: A.token, body: { image_id: i % 2 ? imageIds[0] : x.body.id, after_image_id: imageIds[1] },
          });
          assertEquals(m.status, 200, JSON.stringify(m.body));
        }
        const s2 = await sync(device.secret, 0, []);
        assertEquals(s2.body.images.map((i: any) => i.id), [imageIds[1], imageIds[0], x.body.id]);
        const pos = s2.body.images.map((i: any) => i.position);
        assertEquals(pos[0], 1, `renumbered: ${pos}`); // I1 sat at 0 before the loop
        assert(pos[0] < pos[1] && pos[1] < pos[2], `ordered: ${pos}`);
        imageIds.splice(0, imageIds.length, imageIds[1], imageIds[0], x.body.id);
        version = s2.body.manifest_version;
      });

      await t.step("settings", async () => {
        const r = await call("PATCH", "/app-api/frame/settings", {
          token: A.token, body: { image_interval_s: 7200, quiet_start: "22:00", quiet_end: "07:00", timezone: "Asia/Kolkata" },
        });
        assertEquals(r.status, 200, JSON.stringify(r.body));
        assertEquals(r.body.image_interval_s, 7200);
        assertEquals(r.body.quiet_start, "22:00");
        assertEquals(r.body.connected, true);
        assertEquals(r.body.up_to_date, false, "settings waiting");

        const s = await sync(device.secret, version, imageIds);
        assertEquals(s.body.settings.tz_posix, "IST-5:30");
        assertEquals(s.body.settings.quiet_end, "07:00");
        assertEquals(s.body.images, undefined, "settings changes don't bump the manifest");
        assertEquals(await upToDate(), true);

        const patch = (token: string, body: unknown) => call("PATCH", "/app-api/frame/settings", { token, body });
        expectError(await patch(A.token, { quiet_start: null }), 422, "quiet_hours_incomplete");
        expectError(await patch(A.token, { timezone: "Mars/Olympus" }), 422, "unknown_timezone");
        expectError(await patch(A.token, { sync_interval_s: 600 }), 400, "invalid_request");
        expectError(await patch(A.token, {}), 400, "invalid_request");
        expectError(await patch(B.token, { display_order: "sequential" }), 403, "not_owner");
        assertEquals((await patch(A.token, { quiet_start: null, quiet_end: null })).body.quiet_start, null);

        // The battery warning is app-only: it doesn't make the frame "Changes waiting".
        await sync(device.secret, version, imageIds);
        assertEquals(await upToDate(), true);
        const b = await patch(A.token, { low_battery_pct: 30 });
        assertEquals(b.status, 200, JSON.stringify(b.body));
        assertEquals([b.body.low_battery_pct, b.body.up_to_date], [30, true]);
        assertEquals((await patch(A.token, { low_battery_pct: null })).body.low_battery_pct, null);
        expectError(await patch(A.token, { low_battery_pct: 2 }), 400, "invalid_request");
        expectError(await patch(B.token, { low_battery_pct: 10 }), 403, "not_owner");
        const row = await B.db.from("frame").select("low_battery_pct").single();
        assertEquals(row.data?.low_battery_pct, null, "members read it directly");
      });

      await t.step("rename; usage", async () => {
        const r = await call("PATCH", "/app-api/frame", { token: A.token, body: { name: "  Kitchen  " } });
        assertEquals(r.body.name, "Kitchen");
        expectError(await call("PATCH", "/app-api/frame", { token: B.token, body: { name: "Mine" } }), 403, "not_owner");

        const u = await call("GET", "/app-api/usage", { token: A.token });
        assertEquals(u.body.frame.images, 3);
        assertEquals(u.body.frame.free_tier_bytes, 1024 ** 3);
        assert(u.body.users.length >= 3, "owner sees everyone");
        assertEquals((await call("GET", "/app-api/usage", { token: B.token })).body.users.map((x: any) => x.user_id), [B.id]);
      });

      await t.step("quota", async () => {
        await sql(env, "update public.quota_config set max_images = 3 where scope = 'frame'");
        try {
          const r = await upload(A, await makePng(800, 480, 50));
          expectError(r, 422, "quota_exceeded");
          assertEquals(r.body.error.details, { scope: "frame", limit: 3, used: 3, unit: "images" });
        } finally {
          await sql(env, "update public.quota_config set max_images = null where scope = 'frame'");
        }
      });

      await t.step("same hardware reconnecting rotates the secret", async () => {
        const again = await connect(A, device.hwId);
        assertEquals(again.res.status, 200);
        expectError(await sync(device.secret, 0), 401, "invalid_device_secret");
        assertEquals((await sync(again.secret, 0)).body.images.length, 3, "photos kept");
        device.secret = again.secret;
      });

      await t.step("replacement hardware (same model) takes over and keeps photos", async () => {
        const old = device.secret;
        const repl = await connect(A, hw(5));
        assertEquals(repl.res.status, 200);
        expectError(await sync(old, 0), 410, "frame_removed");
        assertEquals((await sync(repl.secret, 0)).body.images.length, 3);
        device = { secret: repl.secret, hwId: hw(5) };
      });

      await t.step("disconnect", async () => {
        expectError(await call("POST", "/app-api/frame/disconnect", { token: B.token }), 403, "not_owner");
        assertEquals((await call("POST", "/app-api/frame/disconnect", { token: A.token })).status, 204);
        expectError(await sync(device.secret, 0), 410, "frame_removed");
        assertEquals((await A.db.from("frame").select("hw_id, up_to_date")).data, [{ hw_id: null, up_to_date: false }]);
      });

      await t.step("switching the panel model clears photos and disconnects", async () => {
        const c = await connect(A, hw(6));
        const change = (body: unknown) => call("PATCH", "/app-api/frame", { token: A.token, body });
        const refused = await change({ model_id: "pimoroni-7-3" });
        expectError(refused, 409, "photos_would_be_cleared");
        assertEquals(refused.body.error.details, { images: 3 });
        expectError(await change({ model_id: "no-such-model", clear_photos: true }), 422, "unknown_model");

        const ok = await change({ model_id: "pimoroni-7-3", clear_photos: true });
        assertEquals(ok.status, 200, JSON.stringify(ok.body));
        assertEquals(ok.body.model_id, "pimoroni-7-3");
        assertEquals(ok.body.connected, false);
        expectError(await sync(c.secret, 0), 410, "frame_removed");
        const [{ n }] = await sql<{ n: number }>(env,
          "select count(*)::int as n from storage.objects where bucket_id = 'frame-images'");
        assertEquals(n, 0, "objects deleted");

        // Hardware of the new model connects; the old model is refused.
        const e1002 = await connect(A, hw(7));
        expectError(e1002.res, 409, "model_mismatch");
        const inky = await connect(A, hw(8), "pimoroni-7-3");
        assertEquals(inky.res.status, 200);
        assertEquals((await sync(inky.secret, 0)).body.images, []);
        device = { secret: inky.secret, hwId: hw(8) };
      });

      await t.step("members: leave, remove, owner stays; photos stay", async () => {
        const p = await upload(B, await makePng(800, 480, 60));
        assertEquals(p.status, 200);
        expectError(await call("DELETE", `/app-api/members/${A.id}`, { token: A.token }), 403, "cannot_remove_owner");
        expectError(await call("DELETE", `/app-api/members/${C.id}`, { token: B.token }), 403, "not_allowed");
        assertEquals((await call("DELETE", `/app-api/members/${C.id}`, { token: C.token })).status, 204, "C leaves");
        assertEquals((await C.db.from("frame").select("id")).data, []);
        assertEquals((await call("DELETE", `/app-api/members/${B.id}`, { token: A.token })).status, 204, "A removes B");
        expectError(await call("GET", "/app-api/usage", { token: B.token }), 403, "not_member");
        expectError(await call("DELETE", `/app-api/members/${B.id}`, { token: A.token }), 404, "member_not_found");
        const [img] = await sql<{ uploaded_by: string }>(env, `select uploaded_by from public.images where id = '${p.body.id}'`);
        assertEquals(img.uploaded_by, B.id, "photo kept");
      });

      await t.step("member deletes account, with and without their photos", async () => {
        const join = async (label: string) => {
          const u = await newUser(label);
          const inv = await invite(A);
          await call("POST", "/app-api/invites/accept", { token: u.token, body: { code: inv.code, display_name: label } });
          const p = await upload(u, await makePng(800, 480, 70 + label.length));
          assertEquals(p.status, 200, JSON.stringify(p.body));
          return { u, imageId: p.body.id as string };
        };

        const d = await join("dana");
        const before = (await sync(device.secret, 0)).body.manifest_version;
        expectError(await call("DELETE", "/app-api/me?delete_photos=maybe", { token: d.u.token }), 400, "invalid_request");
        assertEquals((await call("DELETE", "/app-api/me?delete_photos=true", { token: d.u.token })).status, 204);
        const s = await sync(device.secret, before);
        assertNotEquals(s.body.manifest_version, before);
        assert(!s.body.images.some((i: any) => i.id === d.imageId), "photo deleted");

        const e = await join("eve");
        assertEquals((await call("DELETE", "/app-api/me", { token: e.u.token })).status, 204);
        const [img] = await sql<{ uploaded_by: string | null }>(env, `select uploaded_by from public.images where id = '${e.imageId}'`);
        assertEquals(img.uploaded_by, null, "photo kept, uploader gone");
        assertExists((await admin.auth.admin.getUserById(e.u.id)).error, "auth user deleted");
      });

      await t.step("the owner can't delete their account through app-api", async () => {
        expectError(await call("DELETE", "/app-api/me", { token: A.token }), 409, "owner_must_delete_frame");
      });
    } finally {
      await cleanup();
    }
  },
});
