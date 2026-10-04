#include "cache.h"

#include <SD.h>

#include "util/log.h"

namespace cache {

static const char* kDir = "/cache";
static const char* kManifest = "/cache/manifest.txt";
static const char* kManifestTmp = "/cache/manifest.tmp";
static const char* kNewest = "/cache/newest.txt";
static const char* kTmpDir = "/cache/tmp";

static void ensureDir(const char* path) {
  if (!SD.exists(path)) SD.mkdir(path);
}

static bool readLines(const char* path, std::vector<std::string>& out) {
  if (!SD.exists(path)) return false;
  File f = SD.open(path, FILE_READ);
  if (!f) return false;
  std::string line;
  while (f.available()) {
    const int c = f.read();
    if (c < 0) break;
    if (c == '\n') {
      out.push_back(line);
      line.clear();
    } else {
      line += static_cast<char>(c);
    }
  }
  if (!line.empty()) out.push_back(line);
  f.close();
  return true;
}

// FAT can't rename over an existing file: write tmp, remove the old one, rename. A cut
// between the last two leaves only tmp, which the next read picks up.
static bool writeAtomic(const char* path, const char* tmp, const std::string& content) {
  ensureDir(kDir);
  File f = SD.open(tmp, FILE_WRITE);
  if (!f) return false;
  const bool ok = f.write(reinterpret_cast<const uint8_t*>(content.data()), content.size()) == content.size();
  f.close();
  if (!ok) {
    SD.remove(tmp);
    return false;
  }
  SD.remove(path);
  return SD.rename(tmp, path);
}

bool loadManifest(std::vector<manifest::Image>& out) {
  out.clear();
  if (!SD.exists(kManifest) && SD.exists(kManifestTmp)) SD.rename(kManifestTmp, kManifest);
  std::vector<std::string> lines;
  if (!readLines(kManifest, lines)) return false;
  for (const auto& l : lines) {
    manifest::Image img;
    if (manifest::parseLine(l, img)) out.push_back(img);
  }
  return true;
}

bool saveManifest(const std::vector<manifest::Image>& images) {
  std::string s;
  s.reserve(images.size() * 120);
  for (const auto& img : images) s += manifest::toLine(img) + "\n";
  return writeAtomic(kManifest, kManifestTmp, s);
}

bool has(const manifest::Image& img) {
  File f = SD.open(manifest::imagePath(img.id).c_str(), FILE_READ);
  if (!f) return false;
  const bool ok = f.size() == img.bytes;
  f.close();
  return ok;
}

static uint64_t removeDir(const String& path, const std::set<std::string>* keep) {
  uint64_t freed = 0;
  File dir = SD.open(path);
  if (!dir || !dir.isDirectory()) return 0;
  std::vector<std::pair<String, bool>> entries;  // name, is a folder
  for (File e = dir.openNextFile(); e; e = dir.openNextFile()) {
    entries.push_back({String(e.path()), e.isDirectory()});
    e.close();
  }
  dir.close();
  for (const auto& [p, isDir] : entries) {
    if (isDir) {
      freed += removeDir(p, keep);
      continue;
    }
    if (keep) {
      // /cache/<xx>/<id>.png
      const int slash = p.lastIndexOf('/');
      String name = p.substring(slash + 1);
      if (!name.endsWith(".png")) continue;  // manifest, newest
      name.remove(name.length() - 4);
      if (keep->count(name.c_str())) continue;
    }
    File f = SD.open(p, FILE_READ);
    const uint64_t size = f ? f.size() : 0;
    if (f) f.close();
    if (SD.remove(p)) freed += size;
  }
  if (!keep || path == kTmpDir) SD.rmdir(path);
  return freed;
}

uint64_t removeUnlisted(const std::set<std::string>& keep) {
  if (!SD.exists(kDir)) return 0;
  uint64_t freed = removeDir(kTmpDir, nullptr);
  File dir = SD.open(kDir);
  std::vector<String> shards;
  for (File e = dir.openNextFile(); e; e = dir.openNextFile()) {
    if (e.isDirectory() && String(e.path()) != kTmpDir) shards.push_back(e.path());
    e.close();
  }
  dir.close();
  for (const auto& s : shards) {
    freed += removeDir(s, &keep);
    SD.rmdir(s);  // only if now empty
  }
  return freed;
}

String tmpPath(const std::string& id) {
  ensureDir(kDir);
  ensureDir(kTmpDir);
  return String(kTmpDir) + "/" + id.c_str() + ".part";
}

bool commit(const std::string& id) {
  ensureDir(manifest::shardDir(id).c_str());
  const std::string to = manifest::imagePath(id);
  SD.remove(to.c_str());
  return SD.rename(tmpPath(id), to.c_str());
}

std::vector<std::string> loadNewest() {
  std::vector<std::string> ids;
  readLines(kNewest, ids);
  return ids;
}

void saveNewest(const std::vector<std::string>& ids) {
  if (ids.empty()) {
    SD.remove(kNewest);
    return;
  }
  std::string s;
  for (const auto& id : ids) s += id + "\n";
  writeAtomic(kNewest, "/cache/newest.tmp", s);
}

void wipe() {
  removeDir(kDir, nullptr);
  LOGLN("cache: wiped");
}

}  // namespace cache
