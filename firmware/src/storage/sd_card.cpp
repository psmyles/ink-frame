#include "sd_card.h"

#include <SD.h>
#include <esp_heap_caps.h>

#include "board/e1002.h"
#include "board/spi_bus.h"
#include "ff.h"
#include "sd_diskio.h"
#include "util/log.h"

namespace card {

static CardState s_state = CardState::missing;
static bool s_mounted = false;

// The card shares the bus with the display; it's fine at 20 MHz, and 4 MHz is the safe
// fallback for a card that won't mount fast.
static const uint32_t kFast = 20000000, kSlow = 4000000;

static void powerCycle() {
  pinMode(SD_EN_PIN, OUTPUT);
  digitalWrite(SD_EN_PIN, LOW);
  delay(200);  // let the card power down fully
  digitalWrite(SD_EN_PIN, HIGH);
  delay(300);  // and power up
  digitalWrite(EPD_CS_PIN, HIGH);
}

// Why mounting failed: no FAT file system on a card that answers (unreadable) or no
// answer at all (missing). FatFs tells them apart; the SD library doesn't.
static CardState probe() {
  const uint8_t pdrv = sdcard_init(SD_CS_PIN, &spiBus(), kSlow);
  if (pdrv == 0xFF) return CardState::missing;
  char drv[3] = {static_cast<char>('0' + pdrv), ':', 0};
  FATFS* fs = static_cast<FATFS*>(heap_caps_malloc(sizeof(FATFS), MALLOC_CAP_8BIT));
  FRESULT r = fs ? f_mount(fs, drv, 1) : FR_NOT_ENOUGH_CORE;
  if (r == FR_OK) f_mount(nullptr, drv, 0);
  free(fs);
  sdcard_uninit(pdrv);
  LOGF("card probe: FatFs %d\n", r);
  return r == FR_NO_FILESYSTEM ? CardState::unreadable : (r == FR_OK ? CardState::ok : CardState::missing);
}

CardState mount() {
  if (s_mounted) return CardState::ok;
  pinMode(SD_DET_PIN, INPUT_PULLUP);
  const bool detected = digitalRead(SD_DET_PIN) == LOW;
  for (int attempt = 0; attempt < (detected ? 3 : 1); attempt++) {
    powerCycle();
    if (SD.begin(SD_CS_PIN, spiBus(), attempt == 0 ? kFast : kSlow)) {
      s_mounted = true;
      s_state = CardState::ok;
      LOGF("card: mounted, %llu MB, %llu MB free\n", totalBytes() >> 20, freeBytes() >> 20);
      return s_state;
    }
    SD.end();
  }
  s_state = detected ? probe() : CardState::missing;
  if (s_state == CardState::ok) {  // answered the slow probe: one more try at that speed
    powerCycle();
    s_mounted = SD.begin(SD_CS_PIN, spiBus(), kSlow);
    if (!s_mounted) s_state = CardState::unreadable;
  }
  LOGF("card: %s\n", stateName(s_state));
  return s_state;
}

void unmount() {
  if (s_mounted) SD.end();
  s_mounted = false;
  digitalWrite(SD_EN_PIN, LOW);
}

CardState state() { return s_state; }

const char* stateName(CardState s) {
  switch (s) {
    case CardState::ok:
      return "ok";
    case CardState::unreadable:
      return "unreadable";
    default:
      return "missing";
  }
}

uint64_t totalBytes() { return s_mounted ? SD.totalBytes() : 0; }

uint64_t freeBytes() {
  if (!s_mounted) return 0;
  const uint64_t total = SD.totalBytes(), used = SD.usedBytes();
  return used < total ? total - used : 0;
}

bool format() {
  unmount();
  pinMode(SD_DET_PIN, INPUT_PULLUP);
  powerCycle();
  const uint8_t pdrv = sdcard_init(SD_CS_PIN, &spiBus(), kFast);
  if (pdrv == 0xFF) return false;
  char drv[3] = {static_cast<char>('0' + pdrv), ':', 0};
  // A big work buffer lets FatFs write the FATs many sectors at a time: a 128 GB card
  // formats in under a minute instead of many.
  const UINT workLen = 256 * 1024;
  void* work = heap_caps_malloc(workLen, MALLOC_CAP_SPIRAM);
  if (!work) {
    sdcard_uninit(pdrv);
    return false;
  }
  const uint32_t t0 = millis();
  FRESULT r = f_mkfs(drv, FM_FAT32, 0, work, workLen);
  if (r == FR_MKFS_ABORTED) r = f_mkfs(drv, FM_ANY, 0, work, workLen);  // too small for FAT32
  free(work);
  sdcard_uninit(pdrv);
  LOGF("card: format %s (FatFs %d) in %lu ms\n", r == FR_OK ? "done" : "failed", r, millis() - t0);
  return r == FR_OK && mount() == CardState::ok;
}

}  // namespace card
