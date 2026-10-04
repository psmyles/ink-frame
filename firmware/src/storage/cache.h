// Ink Frame's photos on the card (PLAN.md §9.3), all under /cache: the frame never
// touches anything else on the card.
//   /cache/manifest.txt     the photos it has, "id sha256 bytes position" per line
//   /cache/newest.txt       just-arrived ids, shown first
//   /cache/<xx>/<id>.png    the photos (core/manifest.h)
//   /cache/tmp/<id>.part    downloads in progress; never shown
#pragma once
#include <Arduino.h>

#include <set>
#include <string>
#include <vector>

#include "core/manifest.h"

namespace cache {

// False when there's no manifest (a new or swapped card): then ask for the full list.
bool loadManifest(std::vector<manifest::Image>& out);
// Written to a temporary file first, so a power cut leaves the old list or the new one.
bool saveManifest(const std::vector<manifest::Image>& images);

// Present with the right size.
bool has(const manifest::Image& img);

// Deletes photos not in keep, and any leftover downloads. Returns the bytes freed.
uint64_t removeUnlisted(const std::set<std::string>& keep);

String tmpPath(const std::string& id);
// Moves a checked download into place.
bool commit(const std::string& id);

std::vector<std::string> loadNewest();
void saveNewest(const std::vector<std::string>& ids);

// Everything under /cache (410: the frame was removed; a factory reset).
void wipe();

}  // namespace cache
