#!/bin/bash
# retro-weather — opens weather.com/retro once a day, the first moment
# between START and END that the screen is on and unlocked (you're there):
#   - at START if you're already at the screen, or
#   - when you wake/unlock the screen later in the window.
# Opens a new maximized Chrome window, switches to °C, unmutes and starts the RetroCast.
# Never more than once per day.
#
# Usage:
#   bash retro-weather.sh install    copy itself into ~/Library and start the background job
#   retro-weather now                open it right now through the background job, ignores time window
#   retro-weather status             job running? last opened? is the screen awake+unlocked right now?
#   retro-weather uninstall          stop the job and remove everything
#   retro-weather run                what the background job calls every 15 s

# ---------- settings ----------
URL="https://weather.com/retro/"
START="1100"        # HHMM: earliest it may open. Set it earlier to have it open as soon as you wake the screen
END="1400"          # HHMM: latest it may open (so an evening screen wake doesn't trigger it)
BROWSER="Google Chrome"
UNITS="m"           # m = °C / km/h,  e = °F / mph
AUTOSTART="yes"     # click "Unmute audio" and "Start RetroCast" (skips the countdown)
CHIME=""            # e.g. "/System/Library/Sounds/Glass.aiff" for an extra chime
SET_VOLUME=""       # e.g. "40" to unmute and set system volume first; "" leaves volume alone
# ------------------------------

LABEL="com.$(id -un).retroweather"
APP_DIR="$HOME/Library/Application Support/RetroWeather"
INSTALLED="$APP_DIR/retro-weather.sh"
STAMP="$APP_DIR/last-opened"
FORCE="$APP_DIR/force-now"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/retro-weather.log"
BIN_LINK="/usr/local/bin/retro-weather"
DOMAIN="gui/$(id -u)"

log() { echo "$(date '+%F %T') $*"; }

# Prints "present" if the display is awake and the screen is unlocked
# (and this user is the one on screen), otherwise "away".
screen_state() {
  local out
  out=$(osascript -l JavaScript 2>&1 <<'JS'
ObjC.import('CoreGraphics');
const asleep = $.CGDisplayIsAsleep($.CGMainDisplayID());
const ref = $.CGSessionCopyCurrentDictionary();
const d = ref ? ObjC.deepUnwrap(ObjC.castRefToObject(ref)) : {};
const locked = !!(d && d.CGSSessionScreenIsLocked);
const notOnConsole = d && d.kCGSSessionOnConsoleKey === false;
(asleep || locked || notOnConsole) ? 'away' : 'present';
JS
)
  case "$out" in
    present|away) echo "$out" ;;
    *) log "screen check failed, assuming present: $out" >&2; echo present ;;
  esac
}

# New maximized browser window, units cookie, unmute + start.
# Exits non-zero only if it couldn't even make the window (caller falls back to `open`).
open_in_browser() {
  RW_URL="$URL" RW_UNITS="$UNITS" RW_BROWSER="$BROWSER" RW_AUTOSTART="$AUTOSTART" \
  osascript -l JavaScript 2>&1 <<'JS'
ObjC.import('AppKit');
const env = $.NSProcessInfo.processInfo.environment;
const get = k => ObjC.unwrap(env.objectForKey(k));
const url = get('RW_URL'), units = get('RW_UNITS'), browser = get('RW_BROWSER'), autostart = get('RW_AUTOSTART') === 'yes';

// Usable area of the screen you're on (minus menu bar and Dock), in top-left coordinates.
let scr = $.NSScreen.mainScreen;
if (!scr || scr.isNil()) scr = $.NSScreen.screens.objectAtIndex(0);
const vf = scr.visibleFrame;
const H = $.NSScreen.screens.objectAtIndex(0).frame.size.height;

const app = Application(browser);
app.activate();
app.Window().make();
delay(0.3);
const id = app.windows[0].id();
const win = () => app.windows.byId(id);
win().bounds = { x: vf.origin.x, y: H - vf.origin.y - vf.size.height, width: vf.size.width, height: vf.size.height };
win().activeTab.url = url;

function waitLoad() {
  const end = Date.now() + 30000;
  delay(1);
  while (win().activeTab.loading() && Date.now() < end) delay(0.5);
}
const js = code => win().activeTab.execute({ javascript: code });

let result = 'window opened';
try {
  waitLoad();
  if (units) {
    const r = js(`(() => {
      if (/(^|; )unitOfMeasurement=${units}(;|$)/.test(document.cookie) &&
          !/(^|; )unitOfMeasurement=(?!${units})/.test(document.cookie)) return 'ok';
      const c = 'unitOfMeasurement=${units}; path=/; max-age=31536000; SameSite=Lax';
      document.cookie = c; document.cookie = c + '; domain=.weather.com';
      return 'set';
    })()`);
    if (r === 'set') { win().activeTab.reload(); waitLoad(); result += ', units set'; }
  }
  if (autostart) {
    let status = 'not found';
    for (let i = 0; i < 30; i++) {
      status = js(`(() => {
        const b = [...document.querySelectorAll('button')];
        const label = e => (e.getAttribute('aria-label') || e.innerText || '').trim();
        const unmute = b.find(e => /^unmute audio$/i.test(label(e)));
        const start = b.find(e => /^start retrocast$/i.test(label(e)));
        if (unmute) unmute.click();
        if (start) start.click();
        return (unmute || start) ? 'clicking' : 'done';
      })()`);
      if (status === 'done' && i > 0) break;
      delay(1);
    }
    result += ', autostart ' + status;
  }
} catch (e) {
  result += ', but page scripting failed: ' + e.message +
    ' (in Chrome: View > Developer > Allow JavaScript from Apple Events)';
}
result;
JS
}

open_page() {
  [[ -n "$SET_VOLUME" ]] && osascript -e "set volume output volume $SET_VOLUME without output muted"
  [[ -n "$CHIME" ]] && afplay "$CHIME" &
  local out
  if open -Ra "$BROWSER" 2>/dev/null && out=$(open_in_browser); then
    log "$out"
  else
    log "couldn't drive $BROWSER (${out:-not installed}), using default browser"
    open "$URL"
  fi
}

cmd_run() {
  if [[ -f "$FORCE" ]]; then
    rm -f "$FORCE"
    log "opening $URL (manual)"
    open_page
    return
  fi
  local now today
  now=$(date +%H%M); today=$(date +%F)
  (( 10#$now < 10#$START || 10#$now > 10#$END )) && exit 0
  [[ "$(cat "$STAMP" 2>/dev/null)" == "$today" ]] && exit 0
  [[ "$(screen_state)" == "present" ]] || exit 0
  mkdir -p "$APP_DIR"
  echo "$today" > "$STAMP"
  log "opening $URL"
  open_page
}

# Runs through the background job (not this Terminal), so it tests exactly
# what happens on schedule, including macOS permission prompts.
cmd_now() {
  if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    mkdir -p "$APP_DIR"; touch "$FORCE"
    launchctl kickstart "$DOMAIN/$LABEL"
    echo "Triggered. Result will appear in: $LOG"
    sleep 20; tail -n 3 "$LOG"
  else
    echo "Job not installed; opening directly."
    open_page
  fi
}

cmd_install() {
  local self
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  [[ "$self" != "$INSTALLED" ]] && cp "$self" "$INSTALLED"
  chmod +x "$INSTALLED"

  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$INSTALLED</string><string>run</string></array>
  <key>StartInterval</key><integer>15</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null
  launchctl bootstrap "$DOMAIN" "$PLIST"

  # Short command name; needs admin once if /usr/local/bin isn't writable.
  if [[ -w "$(dirname "$BIN_LINK")" ]]; then
    ln -sf "$INSTALLED" "$BIN_LINK"
  elif [[ ! -L "$BIN_LINK" ]]; then
    echo "Creating the 'retro-weather' command needs your password:"
    sudo mkdir -p "$(dirname "$BIN_LINK")" && sudo ln -sf "$INSTALLED" "$BIN_LINK"
  fi

  echo "Installed to: $INSTALLED"
  echo "Opens daily between $START and $END, the first moment the screen is on and unlocked."
  echo "Try it now:   retro-weather now"
}

cmd_uninstall() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null
  rm -f "$PLIST" "$LOG"
  rm -rf "$APP_DIR"
  if [[ -L "$BIN_LINK" ]]; then
    rm -f "$BIN_LINK" 2>/dev/null || sudo rm -f "$BIN_LINK"
  fi
  echo "Removed."
}

cmd_status() {
  if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    echo "Job: running ($LABEL)"
  else
    echo "Job: not loaded"
  fi
  echo "Window: $START–$END"
  echo "Last opened: $(cat "$STAMP" 2>/dev/null || echo never)"
  echo "Screen right now: $(screen_state)"
  echo "Log: $LOG"
}

case "${1:-}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  run)       cmd_run ;;
  now)       cmd_now ;;
  status)    cmd_status ;;
  *)         sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
