#include "display.h"

#include <Fonts/FreeSans12pt7b.h>
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeSansBold18pt7b.h>
#include <Fonts/FreeSansBold24pt7b.h>
#include <GxEPD2_7C.h>
#include <PNGdec.h>
#include <SD.h>
#include <esp_heap_caps.h>

#include "board/e1002.h"
#include "board/spi_bus.h"
#include "util/log.h"

// Paged drawing: the 7-colour driver uses 4 bits per pixel, so 16 KB is 40 rows a page.
#define MAX_DISPLAY_BUFFER_SIZE 16000
#define MAX_HEIGHT(EPD) \
  (EPD::HEIGHT <= (MAX_DISPLAY_BUFFER_SIZE * 2) / EPD::WIDTH ? EPD::HEIGHT : (MAX_DISPLAY_BUFFER_SIZE * 2) / EPD::WIDTH)

static GxEPD2_7C<GxEPD2_730c_GDEP073E01, MAX_HEIGHT(GxEPD2_730c_GDEP073E01)> epd(
    GxEPD2_730c_GDEP073E01(EPD_CS_PIN, EPD_DC_PIN, EPD_RES_PIN, EPD_BUSY_PIN));

namespace display {

// What's on the panel, kept through deep sleep so the same screen isn't redrawn.
enum Shown : uint8_t { kNothing, kPhoto, kSetup, kReady, kRemoved, kNoCard, kCardUnreadable, kError };
RTC_DATA_ATTR static uint8_t s_shown = kNothing;
RTC_DATA_ATTR static uint32_t s_shownKey = 0;

static bool s_ready = false;

static void begin() {
  if (s_ready) return;
  epd.epd2.selectSPI(spiBus(), SPISettings(2000000, MSBFIRST, SPI_MODE0));
  epd.init(0);
  epd.setRotation(0);
  s_ready = true;
}

static uint32_t hash(const String& s) {
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < s.length(); i++) h = (h ^ static_cast<uint8_t>(s[i])) * 16777619u;
  return h;
}

static bool already(uint8_t what, uint32_t key = 0) {
  if (s_shown == what && s_shownKey == key) return true;
  s_shown = what;
  s_shownKey = key;
  return false;
}

void forgetShown() { s_shown = kNothing; }

// ── Photos ──────────────────────────────────────────────────────────────────────

// Palette indices in the frame buffer, and their panel colours. The app's PNGs use the
// panel's device colours (shared/presets.json); any other colour maps to the nearest.
enum : uint8_t { PAL_BLACK, PAL_WHITE, PAL_GREEN, PAL_BLUE, PAL_RED, PAL_YELLOW, PAL_ORANGE };
static const uint16_t PALETTE_TO_EPD[] = {GxEPD_BLACK, GxEPD_WHITE,  GxEPD_GREEN, GxEPD_BLUE,
                                          GxEPD_RED,   GxEPD_YELLOW, GxEPD_ORANGE};
static const uint8_t PALETTE_RGB[][3] = {{0, 0, 0},   {255, 255, 255}, {0, 255, 0},  {0, 0, 255},
                                         {255, 0, 0}, {255, 255, 0},   {255, 128, 0}};

static uint8_t* s_frame = nullptr;  // one palette index per pixel, in PSRAM
static PNG s_png;
static File s_pngFile;

static uint8_t nearest(uint8_t r, uint8_t g, uint8_t b) {
  uint32_t best = UINT32_MAX;
  uint8_t idx = PAL_WHITE;
  for (uint8_t i = 0; i < 7; i++) {
    const int32_t dr = r - PALETTE_RGB[i][0], dg = g - PALETTE_RGB[i][1], db = b - PALETTE_RGB[i][2];
    const uint32_t d = dr * dr + dg * dg + db * db;
    if (d < best) {
      best = d;
      idx = i;
    }
  }
  return idx;
}

static void* pngOpen(const char* name, int32_t* size) {
  if (s_pngFile) s_pngFile.close();
  s_pngFile = SD.open(name, FILE_READ);
  if (!s_pngFile) return nullptr;
  *size = s_pngFile.size();
  return &s_pngFile;
}
static void pngClose(void*) {
  if (s_pngFile) s_pngFile.close();
}
static int32_t pngRead(PNGFILE*, uint8_t* buf, int32_t len) { return s_pngFile ? s_pngFile.read(buf, len) : 0; }
static int32_t pngSeek(PNGFILE*, int32_t pos) { return s_pngFile ? s_pngFile.seek(pos) : 0; }

static int pngDraw(PNGDRAW* d) {
  uint16_t line[SCREEN_WIDTH];
  s_png.getLineAsRGB565(d, line, PNG_RGB565_LITTLE_ENDIAN, 0xffffffff);
  if (!s_frame || d->y >= SCREEN_HEIGHT) return 1;
  uint8_t* row = s_frame + d->y * SCREEN_WIDTH;
  for (int x = 0; x < d->iWidth && x < SCREEN_WIDTH; x++) {
    const uint16_t p = line[x];
    row[x] = nearest(((p >> 11) & 0x1F) << 3, ((p >> 5) & 0x3F) << 2, (p & 0x1F) << 3);
  }
  return 1;
}

bool decodePhoto(const char* path) {
  if (!s_frame) s_frame = static_cast<uint8_t*>(heap_caps_malloc(SCREEN_WIDTH * SCREEN_HEIGHT, MALLOC_CAP_SPIRAM));
  if (!s_frame) {
    LOGLN("display: no PSRAM for the frame buffer");
    return false;
  }
  memset(s_frame, PAL_WHITE, SCREEN_WIDTH * SCREEN_HEIGHT);
  digitalWrite(EPD_CS_PIN, HIGH);
  int rc = s_png.open(path, pngOpen, pngClose, pngRead, pngSeek, pngDraw);
  if (rc != PNG_SUCCESS) {
    LOGF("display: can't open %s (%d)\n", path, rc);
    pngClose(nullptr);
    return false;
  }
  rc = s_png.decode(nullptr, 0);
  s_png.close();
  if (rc != PNG_SUCCESS) LOGF("display: can't decode %s (%d)\n", path, rc);
  return rc == PNG_SUCCESS;
}

void showPhoto(int batteryPct, bool checkFailed) {
  begin();
  s_shown = kPhoto;
  epd.setFullWindow();
  epd.firstPage();
  do {
    epd.fillScreen(GxEPD_WHITE);
    for (int y = 0; y < SCREEN_HEIGHT; y++) {
      const uint8_t* row = s_frame + y * SCREEN_WIDTH;
      for (int x = 0; x < SCREEN_WIDTH; x++) {
        if (row[x] != PAL_WHITE) epd.drawPixel(x, y, PALETTE_TO_EPD[row[x]]);
      }
    }
    // Battery bar: the bottom row, green for the charge left, red for the rest.
    const int green = (SCREEN_WIDTH * batteryPct) / 100;
    for (int x = 0; x < SCREEN_WIDTH; x++) epd.drawPixel(x, SCREEN_HEIGHT - 1, x < green ? GxEPD_GREEN : GxEPD_RED);
    if (checkFailed) epd.fillRect(0, SCREEN_HEIGHT - 4, 24, 4, GxEPD_RED);
  } while (epd.nextPage());
  LOGLN("display: photo shown");
}

// ── Screens ─────────────────────────────────────────────────────────────────────

static void centered(const char* text, int y, const GFXfont* font, uint16_t colour = GxEPD_BLACK) {
  epd.setFont(font);
  epd.setTextColor(colour);
  int16_t x1, y1;
  uint16_t w, h;
  epd.getTextBounds(text, 0, y, &x1, &y1, &w, &h);
  epd.setCursor((SCREEN_WIDTH - static_cast<int>(w)) / 2 - x1, y);
  epd.print(text);
}

// A title, up to three lines of text, and an optional big word (the frame's XXXX).
static void screen(const char* title, const char* big, const char* l1, const char* l2 = nullptr,
                   const char* l3 = nullptr) {
  begin();
  epd.setFullWindow();
  epd.firstPage();
  do {
    epd.fillScreen(GxEPD_WHITE);
    int y = big ? 120 : 170;
    centered(title, y, &FreeSansBold18pt7b);
    y += 40;
    if (big) {
      // Framed, like the app's "Is this your frame?" (app-flow §6.1).
      epd.drawRoundRect(SCREEN_WIDTH / 2 - 120, y + 2, 240, 84, 12, GxEPD_BLACK);
      epd.drawRoundRect(SCREEN_WIDTH / 2 - 119, y + 3, 238, 82, 11, GxEPD_BLACK);
      centered(big, y + 62, &FreeSansBold24pt7b);
      y += 130;
    } else {
      y += 30;
    }
    for (const char* l : {l1, l2, l3}) {
      if (!l) continue;
      centered(l, y, &FreeSans12pt7b);
      y += 36;
    }
  } while (epd.nextPage());
}

void showSetup(const String& suffix, const String& name) {
  if (already(kSetup, hash(suffix))) return;
  screen(name.c_str(), suffix.c_str(), "Ready to be set up.", "Open the Ink Frame app and choose Set up a frame,",
         "or Connect the frame in an album you already have.");
}

void showReady() {
  if (already(kReady)) return;
  screen("Ready", nullptr, "Add photos to its album in the Ink Frame app.",
         "They appear at the frame's next check, or press its green button.");
}

void showRemoved() {
  if (already(kRemoved)) return;
  // Its album was deleted, or the frame was disconnected from it (410).
  screen("Not connected to an album", nullptr, "Hold the green button for 3 seconds,",
         "then connect it in the Ink Frame app.");
}

void showNoCard() {
  if (already(kNoCard)) return;
  screen("No memory card", nullptr, "Put a microSD card in the frame,", "then press the green button.");
}

void showCardUnreadable() {
  if (already(kCardUnreadable)) return;
  screen("Can't read the memory card", nullptr, "Erase it when you connect the frame in the app,",
         "or format it as FAT32 on a computer.", "Then press the green button.");
}

void showError(const char* line1, const char* line2) {
  if (already(kError, hash(String(line1) + line2))) return;
  screen("Something went wrong", nullptr, line1, line2);
}

void sleep() {
  if (s_ready) epd.hibernate();
  s_ready = false;
}

}  // namespace display
