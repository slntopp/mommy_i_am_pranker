# retro-weather

Opens [weather.com/retro](https://weather.com/retro/) once a day, the first moment between `START` and `END` that the Mac's screen is on and unlocked. Opens a new maximized Chrome window, switches to °C, unmutes and starts the RetroCast immediately.

```sh
bash retro-weather.sh install   # installs to ~/Library/Application Support/RetroWeather + launchd job
retro-weather now               # trigger it right now through the job
retro-weather status
retro-weather uninstall
```

Settings (time window, units, browser, chime) are at the top of the script. Edit the installed copy to change them, no reinstall needed.

One-time Chrome setup:
- View → Developer → **Allow JavaScript from Apple Events** (needed to press the buttons and set units)
- `chrome://settings/content/sound` → add `weather.com` under **Allowed to play sound**

Log: `~/Library/Logs/retro-weather.log`
