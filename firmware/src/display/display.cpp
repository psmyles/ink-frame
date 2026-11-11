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
// How bright each one looks on the panel (Rec. 601 luma of the spectra6 `color`s in
// shared/presets.json; orange, which the app never sends, between red and yellow), and
// halfway between its black and white: the battery number goes white below that.
static const uint8_t PALETTE_BRIGHTNESS[] = {37, 202, 97, 73, 59, 177, 118};
static const uint8_t kDarkBelow = 120;

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
  // PNGdec keeps two rows in a fixed buffer (PNG_MAX_BUFFERED_PIXELS) but checks only one
  // against it: refuse anything larger than the screen or with rows too wide for it
  // (a 16-bit one, say) rather than let it overwrite memory.
  static const uint8_t kChannels[] = {1, 0, 3, 1, 2, 0, 4};  // by PNG colour type
  const int type = s_png.getPixelType();
  const int channels = type >= 0 && type <= 6 ? kChannels[type] : 0;
  const int w = s_png.getWidth(), h = s_png.getHeight();
  const int pitch = (w * channels * s_png.getBpp() + 7) / 8;
  if (channels == 0 || w > SCREEN_WIDTH || h > SCREEN_HEIGHT || (pitch + 1) * 2 > PNG_MAX_BUFFERED_PIXELS) {
    LOGF("display: %s is %dx%d, type %d, %d bits: not drawn\n", path, w, h, type, s_png.getBpp());
    s_png.close();
    pngClose(nullptr);
    return false;
  }
  rc = s_png.decode(nullptr, 0);
  s_png.close();
  if (rc != PNG_SUCCESS) LOGF("display: can't decode %s (%d)\n", path, rc);
  return rc == PNG_SUCCESS;
}

// The battery number: the classic GFX font, whose digits and % are 5 × 7 pixels with a
// 6-pixel advance (about 1.4 mm tall on this panel), so it reads up close but not from
// across the room. Its digits' top-left, 4 pixels in from the corner.
static const int kGlyphH = 7, kAdvance = 6, kInset = 4;
static const int kNumberX = kInset, kNumberY = SCREEN_HEIGHT - kInset - kGlyphH;
static const int kDot = 5, kDotGap = 2;  // the failed-check mark after it

void showPhoto(int batteryPct, overlay::Battery battery, bool checkFailed) {
  begin();
  s_shown = kPhoto;
  const bool asNumber = battery == overlay::Battery::number;
  char number[8] = "";
  if (asNumber && batteryPct >= 0) snprintf(number, sizeof number, "%d%%", batteryPct);
  const int numberW = number[0] ? static_cast<int>(strlen(number)) * kAdvance - 1 : 0;
  // White digits over a dark part of the photo, black over a light one (the photo just
  // around them included).
  const bool white = number[0] && overlay::darkUnder(s_frame, SCREEN_WIDTH, SCREEN_HEIGHT, kNumberX - 1, kNumberY - 1,
                                                     numberW + 2, kGlyphH + 2, PALETTE_BRIGHTNESS,
                                                     sizeof PALETTE_BRIGHTNESS, kDarkBelow);
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
    if (!asNumber) {
      // The bar: the bottom row, black for the charge left, white for the rest; the
      // failed-check mark over its left end.
      if (batteryPct >= 0) {
        const int left = overlay::barLength(SCREEN_WIDTH, batteryPct);
        for (int x = 0; x < SCREEN_WIDTH; x++) epd.drawPixel(x, SCREEN_HEIGHT - 1, x < left ? GxEPD_BLACK : GxEPD_WHITE);
      }
      if (checkFailed) epd.fillRect(0, SCREEN_HEIGHT - 4, 24, 4, GxEPD_RED);
    } else {
      if (number[0]) {
        epd.setFont(nullptr);
        epd.setTextSize(1);
        epd.setTextColor(white ? GxEPD_WHITE : GxEPD_BLACK);  // no background: the photo shows between
        epd.setCursor(kNumberX, kNumberY);
        epd.print(number);
      }
      // The failed-check mark: a small red dot just after the number, level with it.
      if (checkFailed) {
        epd.fillRect(number[0] ? kNumberX + numberW + kDotGap : kNumberX, kNumberY + 1, kDot, kDot, GxEPD_RED);
      }
    }
  } while (epd.nextPage());
  LOGF("display: photo shown (battery %s)\n", asNumber ? "number" : "bar");
}

// ── Screens ─────────────────────────────────────────────────────────────────────

// Text centred on x = cx (the screen's middle by default), baseline at y.
static void centered(const char* text, int y, const GFXfont* font, uint16_t colour = GxEPD_BLACK,
                     int cx = SCREEN_WIDTH / 2) {
  epd.setFont(font);
  epd.setTextColor(colour);
  int16_t x1, y1;
  uint16_t w, h;
  epd.getTextBounds(text, 0, y, &x1, &y1, &w, &h);
  epd.setCursor(cx - static_cast<int>(w) / 2 - x1, y);
  epd.print(text);
}

// A framed box, like the app's "Is this your frame?" (app-flow §6.1).
static void box(int x, int y, int w, int h) {
  epd.drawRoundRect(x, y, w, h, 12, GxEPD_BLACK);
  epd.drawRoundRect(x + 1, y + 1, w - 2, h - 2, 11, GxEPD_BLACK);
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
      box(SCREEN_WIDTH / 2 - 120, y + 2, 240, 84);
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

void showSetup(const String& suffix, const String& name, uint32_t passkey) {
  char code[8];
  snprintf(code, sizeof code, "%03u %03u", static_cast<unsigned>(passkey / 1000), static_cast<unsigned>(passkey % 1000));
  if (already(kSetup, hash(suffix + code))) return;
  begin();
  epd.setFullWindow();
  epd.firstPage();
  do {
    epd.fillScreen(GxEPD_WHITE);
    centered(name.c_str(), 80, &FreeSansBold18pt7b);
    // The 4 characters the app asks you to match, and the code your phone asks for.
    const int w1 = 220, w2 = 300, gap = 40, x1 = (SCREEN_WIDTH - w1 - gap - w2) / 2, x2 = x1 + w1 + gap;
    box(x1, 115, w1, 90);
    box(x2, 115, w2, 90);
    centered(suffix.c_str(), 178, &FreeSansBold24pt7b, GxEPD_BLACK, x1 + w1 / 2);
    centered(code, 178, &FreeSansBold24pt7b, GxEPD_BLACK, x2 + w2 / 2);
    centered("This frame", 240, &FreeSans12pt7b, GxEPD_BLACK, x1 + w1 / 2);
    centered("Code", 240, &FreeSans12pt7b, GxEPD_BLACK, x2 + w2 / 2);
    centered("Open the Ink Frame app and choose Set up a frame,", 310, &FreeSans12pt7b);
    centered("or Connect the frame in an album you already have.", 346, &FreeSans12pt7b);
    centered("Your phone asks for the code.", 382, &FreeSans12pt7b);
  } while (epd.nextPage());
}

void showSetupAsleep(const String& suffix, const String& name) {
  if (already(kSetup, hash(suffix + "asleep"))) return;
  screen(name.c_str(), suffix.c_str(), "Asleep to save battery.", "Press the green button to set it up.");
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
