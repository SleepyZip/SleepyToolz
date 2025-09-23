// ==========================================================
// Scroll Tester + Mouse Diagram (hold timers, dbl-click flash)
// - Windowed P2D (80% x 70% of display)
// - Scroll tracer (no glow, crisp white line)
// - Green/red vertical bars on wheel
// - Trail fade with gamma
// - HUD for counts/persistence/tick height
// - Mouse diagram on the right with L/M/R buttons,
//   hold-time badges (ms), press flash, double-click outline
// - Scroll-wheel slit pulses green/red on recent scroll
// ==========================================================

import processing.event.MouseEvent;

// ===== Glow config (disabled by default) =====
boolean glowOn = false;   // tracer/bars glow disabled
final int    GLOW_LAYERS = 3;
final float  GLOW_MULT   = 3.0f;
final int    GLOW_ALPHA  = 28;

// ===== Positions (Scroll Tester) =====
float x, y;
float prevx;

// ===== Visual scaling (shared by both UIs) =====
float tickHeight, strokeW, hudTextSize, hudPad;
PFont hudFont;

// ===== Trail fade control =====
int fadeAlpha;
int fadeAlphaDefault;
final int FADE_MIN = 0;
final int FADE_MAX = 50;
final int FADE_STEP = 1;
final float TRAIL_GAMMA = 1.6f;

// ===== State / HUD =====
int upCount = 0, downCount = 0;
int skipDotFrames = 0;

// ==========================================================
// Mouse Diagram state
// ==========================================================
final int FLASH_FRAMES       = 10;
final int DBL_FLASH_FRAMES   = 60;
final int DOUBLE_CLICK_MS    = 300;

boolean leftHeld   = false;
boolean middleHeld = false;
boolean rightHeld  = false;

int leftFlash  = 0;
int midFlash   = 0;
int rightFlash = 0;

int leftDblFlash  = 0;
int midDblFlash   = 0;
int rightDblFlash = 0;

int lastLeftReleaseMs  = -100000;
int lastMidReleaseMs   = -100000;
int lastRightReleaseMs = -100000;

int leftStartMs  = -1;
int midStartMs   = -1;
int rightStartMs = -1;

int leftHeldMs   = 0;
int midHeldMs    = 0;
int rightHeldMs  = 0;

// --- Wheel notch pulse (slit color) ---
int wheelPulseFrames = 0;   // counts down for fade
int wheelDir = 0;           // +1 = up (green), -1 = down (red)

// ==========================================================

void settings() {
  size(int(displayWidth * 0.8), int(displayHeight * 0.7), P2D);
}

void setup() {
  x = width * 0.15f;
  y = height * 0.5f;
  prevx = x;

  float S = min(width, height);
  tickHeight   = max(2,   S * 0.03f);
  strokeW      = max(1,   S * 0.003f);
  hudTextSize  = max(10,  S * 0.025f);
  hudPad       = max(6,   S * 0.008f);

  hudFont = createFont("Monospaced", hudTextSize, true);
  textFont(hudFont);

  strokeWeight(strokeW);
  strokeCap(SQUARE);
  frameRate(60);

  fadeAlphaDefault = 25;
  fadeAlpha = fadeAlphaDefault;

  surface.setTitle("Scroll Tester + Mouse Diagram");
}

void draw() {
  // === TRAIL FADE ===
  float xAlpha = fadeAlpha / (float)FADE_MAX;
  int effectiveAlpha = int(FADE_MAX * pow(xAlpha, TRAIL_GAMMA));
  noStroke();
  fill(0, effectiveAlpha);
  rect(0, 0, width, height);

  // === HORIZONTAL TRACER (no glow) ===
  if (skipDotFrames == 0) {
    stroke(255);
    strokeWeight(strokeW);
    strokeCap(SQUARE);
    line(prevx, y, x, y);
  }

  prevx = x;
  x += max(1, strokeW);
  if (x >= width) {
    x = 0;
    prevx = x;
  }
  if (skipDotFrames > 0) skipDotFrames--;

  updateHoldTimers();
  tickMouseAnimations();     // includes wheelPulseFrames countdown

  drawHUD();
  drawMouseDiagram();
}

// ==========================================================
// Input handling
// ==========================================================
void mousePressed() {
  if (mouseButton == LEFT)   { leftHeld = true;   leftFlash = FLASH_FRAMES; }
  if (mouseButton == CENTER) { middleHeld = true; midFlash  = FLASH_FRAMES; }
  if (mouseButton == RIGHT)  { rightHeld = true;  rightFlash = FLASH_FRAMES; }
}

void mouseReleased() {
  int now = millis();
  if (mouseButton == LEFT) {
    leftHeld = false;
    if (now - lastLeftReleaseMs <= DOUBLE_CLICK_MS) leftDblFlash = DBL_FLASH_FRAMES;
    lastLeftReleaseMs = now;
  }
  if (mouseButton == CENTER) {
    middleHeld = false;
    if (now - lastMidReleaseMs <= DOUBLE_CLICK_MS) midDblFlash = DBL_FLASH_FRAMES;
    lastMidReleaseMs = now;
  }
  if (mouseButton == RIGHT) {
    rightHeld = false;
    if (now - lastRightReleaseMs <= DOUBLE_CLICK_MS) rightDblFlash = DBL_FLASH_FRAMES;
    lastRightReleaseMs = now;
  }
}

void mouseWheel(MouseEvent event) {
  int steps = (int) round(event.getCount());
  if (steps == 0) return;

  color barColor = (steps < 0) ? color(0, 255, 0) : color(255, 0, 0);
  if (steps < 0) upCount += abs(steps);
  else           downCount += abs(steps);

  float newY = y + steps * tickHeight;

  // Crisp vertical bar only
  stroke(barColor);
  strokeWeight(strokeW);
  strokeCap(SQUARE);
  drawVerticalBarWithWrap(x, y, newY);

  y = wrapY(newY);
  skipDotFrames = 2;

  // --- Pulse the mouse slit color ---
  wheelDir = (steps < 0) ? +1 : -1; // up = green, down = red
  wheelPulseFrames = 30;            // ~0.5s at 60fps
}

// ==========================================================
// Scroll tester helpers
// ==========================================================
void drawVerticalBarWithWrap(float xLine, float yStart, float yEnd) {
  if (yEnd >= 0 && yEnd < height) {
    line(xLine, yStart, xLine, yEnd);
    return;
  }
  float dest = wrapY(yEnd);
  if (yEnd >= height) {
    line(xLine, yStart, xLine, height - 1);
    line(xLine, 0, xLine, dest);
  } else {
    line(xLine, yStart, xLine, 0);
    line(xLine, height - 1, xLine, dest);
  }
}

float wrapY(float v) {
  float h = (float) height;
  float m = v % h;
  if (m < 0) m += h;
  return m;
}

void keyPressed() {
  if (keyCode == UP || key == '+')    fadeAlpha = max(FADE_MIN, fadeAlpha - FADE_STEP);
  if (keyCode == DOWN || key == '-')  fadeAlpha = min(FADE_MAX, fadeAlpha + FADE_STEP);
  if (key == '0')                     fadeAlpha = 0;
  if (key == 'r' || key == 'R')       fadeAlpha = fadeAlphaDefault;

  if (keyCode == RIGHT) tickHeight = min(tickHeight * 1.1f, 100);
  if (keyCode == LEFT)  tickHeight = max(1, tickHeight / 1.1f);

  if (key == 'g' || key == 'G') glowOn = !glowOn; // still toggle-able if you re-add glow later
}

void drawHUD() {
  pushStyle();
  textFont(hudFont);
  textSize(hudTextSize);

  int persistence = int(map(fadeAlpha, FADE_MIN, FADE_MAX, 100, 0));
  String trailText = (fadeAlpha == 0)
    ? "Trail: 100% (Infinite)"
    : "Trail: " + persistence + "%";

  String line1 = "Up: " + upCount + "    Down: " + downCount;
  String line2 = trailText + "   TickHeight: " + nf(tickHeight, 0, 1);

  float w = max(textWidth(line1), textWidth(line2)) + hudPad * 2;
  float h = hudTextSize * 2 + hudPad * 3;

  noStroke();
  fill(0, 170);
  rect(hudPad, hudPad, w, h, hudPad * 0.5f);

  fill(255);
  float ty = hudPad + hudTextSize + hudPad * 0.5f;
  text(line1, hudPad * 2, ty);
  text(line2, hudPad * 2, ty + hudTextSize + hudPad * 0.5f);
  popStyle();
}

// ==========================================================
// Mouse Diagram — state updates
// ==========================================================
void updateHoldTimers() {
  int now = millis();
  if (leftHeld) {
    if (leftStartMs < 0) leftStartMs = now;
    leftHeldMs = now - leftStartMs;
  } else { leftStartMs = -1; leftHeldMs = 0; }
  if (middleHeld) {
    if (midStartMs < 0) midStartMs = now;
    midHeldMs = now - midStartMs;
  } else { midStartMs = -1; midHeldMs = 0; }
  if (rightHeld) {
    if (rightStartMs < 0) rightStartMs = now;
    rightHeldMs = now - rightStartMs;
  } else { rightStartMs = -1; rightHeldMs = 0; }
}

void tickMouseAnimations() {
  if (leftFlash  > 0) leftFlash--;
  if (midFlash   > 0) midFlash--;
  if (rightFlash > 0) rightFlash--;
  if (leftDblFlash  > 0) leftDblFlash--;
  if (midDblFlash   > 0) midDblFlash--;
  if (rightDblFlash > 0) rightDblFlash--;

  // fade the scroll slit pulse
  if (wheelPulseFrames > 0) wheelPulseFrames--;
}

// ==========================================================
// Mouse Diagram — drawing
// ==========================================================
void drawMouseDiagram() {
  pushStyle();
  float margin = max(hudPad * 2f, 12f);
  float H = min(width, height);
  float mouseW = max(90, H * 0.14f);
  float mouseH = mouseW * 1.5f;
  float xRight = width - margin;
  float yTop   = margin;
  float mx = xRight - mouseW;
  float my = yTop;

  float radius = mouseW * 0.30f;
  noStroke();
  fill(20, 20, 20, 200);
  rect(mx, my, mouseW, mouseH, radius);

  float safeInset = max(mouseW * 0.10f, radius * 0.35f);
  float rowTop    = my + safeInset;
  float rowPadX   = safeInset;
  float rowW      = mouseW - rowPadX * 2;
  float rowH      = mouseH * 0.26f;
  float gap   = rowW * 0.06f;
  float midW  = rowW * 0.20f;
  float lrW   = (rowW - midW - 2 * gap) / 2f;

  float lx = mx + rowPadX;
  float mxr = lx + lrW + gap;
  float rx = mxr + midW + gap;
  float ly = rowTop;

  int base  = color(60, 60, 60, 220);
  int heldC = color(255, 255, 255, 230);
  int flashC= color(180, 180, 180, 220);
  int dblC  = color(0, 180, 255, 220);

  float br = radius * 0.22f;
  drawButton(lx,  ly,  lrW, rowH, leftHeld,   leftFlash,  leftDblFlash,  base, flashC, heldC, dblC, br);
  drawButton(mxr, ly, midW, rowH, middleHeld, midFlash,   midDblFlash,   base, flashC, heldC, dblC, br * 0.8f);
  drawButton(rx,  ly,  lrW, rowH, rightHeld,  rightFlash, rightDblFlash, base, flashC, heldC, dblC, br);

  drawHoldBadge(lx,  ly,  lrW, rowH, leftHeldMs,   leftHeld);
  drawHoldBadge(mxr, ly, midW, rowH, midHeldMs,    middleHeld);
  drawHoldBadge(rx,  ly,  lrW, rowH, rightHeldMs,  rightHeld);

  // --- Wheel notch slit with green/red pulse on recent scroll ---
  float notchX = mxr + midW / 2f;
  if (wheelPulseFrames > 0) {
    float a = map(wheelPulseFrames, 0, 30, 0, 255);
    if (wheelDir > 0) stroke(0, 255, 0, a);   // up = green
    else              stroke(255, 0, 0, a);   // down = red
  } else {
    stroke(120);                               // idle gray
  }
  strokeWeight(max(1, strokeW * 0.9f));
  line(notchX, ly + rowH * 0.18f, notchX, ly + rowH * 0.82f);

  textFont(hudFont);
  textSize(hudTextSize * 0.8f);
  fill(255);
  String label = "Mouse";
  float tw = textWidth(label);
  text(label, mx + (mouseW - tw) / 2f, my + mouseH - safeInset * 0.5f);

  int dblAny = max(leftDblFlash, max(midDblFlash, rightDblFlash));
  if (dblAny > 0) {
    float alpha = map(dblAny, 0, DBL_FLASH_FRAMES, 0, 255);
    textAlign(CENTER, TOP);
    textSize(hudTextSize * 0.9f);
    fill(0, 255, 255, alpha);
    float cx = mx + mouseW / 2f;
    float cy = my + mouseH + (hudPad * 0.3f);
    text("Double-Click!", cx, cy);
  }
  popStyle();
}

void drawButton(float x, float y, float w, float h,
                boolean isHeld, int flashFrames, int dblFrames,
                int base, int flashCol, int heldCol, int dblCol, float r) {
  noStroke();
  fill(isHeld ? heldCol : base);
  rect(x, y, w, h, r);

  if (flashFrames > 0) {
    float a = map(flashFrames, 0, FLASH_FRAMES, 0, 180);
    fill(255, 255, 255, a);
    rect(x, y, w, h, r);
  }
  if (dblFrames > 0) {
    float a = map(dblFrames, 0, DBL_FLASH_FRAMES, 0, 255);
    stroke(red(dblCol), green(dblCol), blue(dblCol), a);
    strokeWeight(max(2, strokeW * 1.6f));
    noFill();
    rect(x, y, w, h, r);
  }
}

void drawHoldBadge(float bx, float by, float bw, float bh, int ms, boolean show) {
  if (!show || ms <= 0) return;
  pushStyle();
  textFont(hudFont);
  float baseSize = min(bh * 0.35f, hudTextSize);
  textSize(baseSize);
  textAlign(CENTER, TOP);

  String s = ms + " ms";
  float pad = bh * 0.10f;
  float cx  = bx + bw * 0.5f;
  float ty  = by + bh * 0.08f;

  float tw = textWidth(s);
  float th = textAscent() + textDescent();
  float pillW = tw + pad * 1.8f;
  float pillH = th + pad * 1.0f;

  noStroke();
  fill(0, 0, 0, 165);
  rectMode(CENTER);
  rect(cx, ty + pillH * 0.5f, pillW, pillH, pillH * 0.5f);

  fill(255);
  text(s, cx, ty + (pillH - th) * 0.5f);
  popStyle();
}
