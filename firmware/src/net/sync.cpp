#include "sync.h"

#include <set>
#include <time.h>

#include "core/manifest.h"
#include "net/api_client.h"
#include "net/wifi.h"
#include "storage/cache.h"
#include "storage/sd_card.h"
#include "util/log.h"

namespace photos {

static FrameSettings parseSettings(JsonVariantConst s) {
  FrameSettings f;
  f.schedule.imageIntervalS = s["image_interval_s"] | 14400u;
  f.schedule.syncIntervalS = s["sync_interval_s"] | 86400u;
  f.schedule.quietStart = schedule::parseHhmm(s["quiet_start"] | static_cast<const char*>(nullptr));
  f.schedule.quietEnd = schedule::parseHhmm(s["quiet_end"] | static_cast<const char*>(nullptr));
  f.sequential = String(s["display_order"] | "random") == "sequential";
  f.tzPosix = s["tz_posix"] | "UTC0";
  return f;
}

Result sync(Config& cfg, int batteryPct, bool fullList, Report& report) {
  const bool cardOk = card::state() == CardState::ok;

  // What's on the card now.
  std::vector<manifest::Image> cached;
  bool haveList = cardOk && cache::loadManifest(cached);
  std::vector<manifest::Image> present;
  uint64_t cacheBytes = 0;
  for (const auto& img : cached) {
    if (cache::has(img)) {
      present.push_back(img);
      cacheBytes += img.bytes;
    }
  }

  JsonDocument body = api::newDocument();
  // No list on the card (new or swapped card): ask for every photo. No card at all: keep
  // the version, so the server doesn't send a list there's nowhere to put.
  body["manifest_version"] = (fullList || (cardOk && !haveList)) ? 0 : cfg.manifestVersion;
  body["fw_version"] = FW_VERSION;
  body["battery_pct"] = batteryPct;
  const int rssi = wifi::rssi();
  if (rssi < 0) body["rssi"] = rssi;
  body["sd_total_bytes"] = cardOk ? card::totalBytes() : 0;
  if (cardOk) {
    body["sd_free_bytes"] = card::freeBytes();
    body["cache_bytes"] = cacheBytes;
  }
  JsonArray ids = body["local_ids"].to<JsonArray>();
  for (const auto& img : present) ids.add(img.id);

  JsonDocument res = api::newDocument();
  const api::Response r = api::postJson(cfg.apiBaseUrl + "/device-api/sync", body, cfg.deviceSecret, res);
  body.clear();
  if (r.status == 410) {
    LOGLN("sync: this frame was removed in the app");
    if (cardOk) cache::wipe();
    nvs::forgetLink();
    cfg = nvs::load();
    return Result::removed;
  }
  if (r.status != 200) return Result::failed;

  const FrameSettings settings = parseSettings(res["settings"]);
  wifi::syncTime(settings.tzPosix, res["server_time"] | static_cast<int64_t>(0));
  const int64_t version = res["manifest_version"] | static_cast<int64_t>(0);
  int64_t applied = cfg.manifestVersion;

  JsonArrayConst images = res["images"].as<JsonArrayConst>();
  if (!images.isNull() && cardOk) {
    std::vector<manifest::Image> list;
    std::vector<String> urls;
    for (JsonObjectConst i : images) {
      list.push_back({i["id"] | "", i["sha256"] | "", i["bytes"] | 0u, i["position"] | 0.0});
      urls.push_back(i["url"] | "");
    }
    std::set<std::string> listed, have;
    for (const auto& i : list) listed.insert(i.id);
    for (const auto& p : present) have.insert(p.id);

    // Delete what's gone first, so its space is free for the new ones.
    std::vector<manifest::Image> kept;
    for (const auto& p : present) {
      if (listed.count(p.id)) kept.push_back(p);
    }
    report.deleted = present.size() - kept.size();
    std::set<std::string> keepIds;
    for (const auto& k : kept) keepIds.insert(k.id);
    cache::removeUnlisted(keepIds);

    std::vector<bool> isCached;
    for (const auto& i : list) isCached.push_back(have.count(i.id) > 0);
    const auto plan = manifest::planDownloads(list, isCached, card::freeBytes());
    report.skipped = plan.skipped.size();

    std::vector<std::string> newest = cache::loadNewest();
    std::set<std::string> ok = keepIds;
    for (size_t idx : plan.download) {
      const auto& img = list[idx];
      const String tmp = cache::tmpPath(img.id);
      if (urls[idx].length() && api::download(urls[idx], tmp, img.bytes, img.sha256.c_str()) && cache::commit(img.id)) {
        ok.insert(img.id);
        newest.push_back(img.id);
        report.added++;
      } else {
        report.failed++;
      }
    }

    std::vector<manifest::Image> now;
    for (const auto& i : list) {
      if (ok.count(i.id)) now.push_back(i);
    }
    cache::saveManifest(now);
    cache::saveNewest(newest);
    report.total = now.size();
    // Only when everything arrived: otherwise the next check asks again (and retries
    // what didn't fit once there's room).
    if (report.failed == 0 && report.skipped == 0) applied = version;
  } else if (images.isNull()) {
    applied = version;  // unchanged
    report.total = present.size();
  }

  cfg.manifestVersion = applied;
  cfg.lastSyncAt = time(nullptr);
  cfg.settings = settings;
  nvs::saveSync(cfg.manifestVersion, cfg.lastSyncAt, cfg.settings);
  LOGF("sync: %d photos (+%d, -%d, %d didn't fit, %d failed)\n", report.total, report.added, report.deleted,
       report.skipped, report.failed);
  return Result::ok;
}

}  // namespace photos
