// The microSD card (docs/pairing.md `info.sd`; openapi.yaml `sd_total_bytes`).
//
// Edge cases handled here:
// - no card (the detect pin, and a card that doesn't answer) → missing;
// - a card the frame can't read: exFAT or NTFS (cards over 32 GB come as exFAT, which
//   this FAT library doesn't support), or a damaged one → unreadable, until it's erased;
// - a card in a bad state after a reset → its slot is powered off and on, and mounting
//   is retried, more slowly the second time;
// - any size: FAT16/FAT32 up to 2 TB; erasing formats FAT32 (FAT16 for tiny cards) over
//   the whole card, so a 64 GB exFAT card becomes a usable 64 GB FAT32 one.
#pragma once
#include <Arduino.h>

enum class CardState : uint8_t { ok, missing, unreadable };

namespace card {

CardState mount();
void unmount();
CardState state();
const char* stateName(CardState s);

// The file system's size and free space (0 unless mounted).
uint64_t totalBytes();
uint64_t freeBytes();

// Formats the whole card as FAT32 (everything on it is lost) and mounts it again.
bool format();

}  // namespace card
