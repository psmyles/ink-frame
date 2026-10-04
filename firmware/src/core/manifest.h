// The photo list (manifest) and the cache on the memory card (PLAN.md §9.3).
// Pure logic: no Arduino, tested on the computer (test/test_manifest).
#pragma once
#include <stdint.h>

#include <string>
#include <vector>

namespace manifest {

// The frame keeps this much of the card free (openapi.yaml, /device-api/sync).
constexpr uint64_t kCardReserve = 8ull * 1024 * 1024;

struct Image {
  std::string id;      // uuid
  std::string sha256;  // lowercase hex
  uint32_t bytes = 0;
  double position = 0;
};

// One line of /cache/manifest.txt: "id sha256 bytes position".
std::string toLine(const Image& img);
bool parseLine(const std::string& line, Image& out);

// Where a photo lives on the card: /cache/<first two hex digits>/<id>.png, so no folder
// holds more than a few dozen files (FAT looks names up one by one).
std::string imagePath(const std::string& id);
std::string shardDir(const std::string& id);

// Which photos to download, in manifest order, while they fit in freeBytes minus the
// reserve (after the photos no longer listed were deleted). The rest are skipped and
// tried again at the next check.
struct DownloadPlan {
  std::vector<size_t> download;  // indices into the manifest
  std::vector<size_t> skipped;   // didn't fit
};
DownloadPlan planDownloads(const std::vector<Image>& images, const std::vector<bool>& cached, uint64_t freeBytes,
                           uint64_t reserve = kCardReserve);

// The next photo to show: just-arrived ones first (newest, consumed from the back), then
// in order (sequential, previous/next with the white buttons) or shuffled without
// repeating the last one. Returns an index into images, or -1 if there are none.
struct PickState {
  int32_t sequentialIndex = -1;
  std::string lastId;
};
int pickNext(const std::vector<Image>& images, std::vector<std::string>& newest, PickState& state, bool sequential,
             bool previous, uint32_t random);

}  // namespace manifest
