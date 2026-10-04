#include "manifest.h"

#include <cstdio>
#include <cstdlib>

namespace manifest {

static bool isHex(const std::string& s, size_t len) {
  if (s.size() != len) return false;
  for (char c : s) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  }
  return true;
}

static bool isUuid(const std::string& s) {
  if (s.size() != 36) return false;
  for (size_t i = 0; i < s.size(); i++) {
    const char c = s[i];
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (c != '-') return false;
    } else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
      return false;
    }
  }
  return true;
}

std::string toLine(const Image& img) {
  char buf[48];
  snprintf(buf, sizeof buf, " %lu %.17g", static_cast<unsigned long>(img.bytes), img.position);
  return img.id + " " + img.sha256 + buf;
}

bool parseLine(const std::string& line, Image& out) {
  std::vector<std::string> parts;
  size_t i = 0;
  while (i < line.size()) {
    while (i < line.size() && (line[i] == ' ' || line[i] == '\r' || line[i] == '\t')) i++;
    size_t j = i;
    while (j < line.size() && line[j] != ' ' && line[j] != '\r' && line[j] != '\t') j++;
    if (j > i) parts.push_back(line.substr(i, j - i));
    i = j;
  }
  if (parts.size() != 4 || !isUuid(parts[0]) || !isHex(parts[1], 64)) return false;
  char* end = nullptr;
  const unsigned long bytes = strtoul(parts[2].c_str(), &end, 10);
  if (*end != '\0' || bytes == 0) return false;
  const double position = strtod(parts[3].c_str(), &end);
  if (*end != '\0') return false;
  out = Image{parts[0], parts[1], static_cast<uint32_t>(bytes), position};
  return true;
}

std::string shardDir(const std::string& id) { return "/cache/" + id.substr(0, 2); }

std::string imagePath(const std::string& id) { return shardDir(id) + "/" + id + ".png"; }

DownloadPlan planDownloads(const std::vector<Image>& images, const std::vector<bool>& cached, uint64_t freeBytes,
                           uint64_t reserve) {
  DownloadPlan plan;
  uint64_t room = freeBytes > reserve ? freeBytes - reserve : 0;
  for (size_t i = 0; i < images.size(); i++) {
    if (i < cached.size() && cached[i]) continue;
    if (images[i].bytes <= room) {
      plan.download.push_back(i);
      room -= images[i].bytes;
    } else {
      plan.skipped.push_back(i);
    }
  }
  return plan;
}

int pickNext(const std::vector<Image>& images, std::vector<std::string>& newest, PickState& state, bool sequential,
             bool previous, uint32_t random) {
  const int n = static_cast<int>(images.size());
  if (n == 0) return -1;
  auto indexOf = [&](const std::string& id) {
    for (int i = 0; i < n; i++) {
      if (images[i].id == id) return i;
    }
    return -1;
  };

  int pick = -1;
  while (!newest.empty() && pick < 0) {
    pick = indexOf(newest.back());
    newest.pop_back();
  }
  if (pick < 0) {
    if (sequential) {
      pick = ((state.sequentialIndex + (previous ? -1 : 1)) % n + n) % n;
    } else if (n == 1) {
      pick = 0;
    } else {
      const int last = indexOf(state.lastId);
      pick = static_cast<int>(random % static_cast<uint32_t>(last >= 0 ? n - 1 : n));
      if (last >= 0 && pick >= last) pick++;  // every photo but the last one shown
    }
  }
  if (sequential) state.sequentialIndex = pick;
  state.lastId = images[pick].id;
  return pick;
}

}  // namespace manifest
