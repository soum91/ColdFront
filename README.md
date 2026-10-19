# Equinox

(Repo and bundle ID still say ColdFront so installs update in place.)

A clean, ad-free iOS controller for Hisense portable air conditioners (and other ConnectLife ACs). It uses the same cloud backend as the official ConnectLife app, so anything bound to your ConnectLife account shows up here.

## Features

Power, mode (Cool / Dry / Fan, plus Heat on models that have it), a thermostat-style Auto that you set a temperature for and that flips the unit between Cool and Heat around it (Cool and Fan on cool-only units). It switches only when the room is ±3°C / ±5°F off target (adjustable), the reading has held for 5 minutes, and the last flip was at least 30 minutes ago; it never re-sends a command, since every command makes the unit beep, a drag dial and +/- buttons for the setpoint, fan speed (Auto / Quiet / Low / Med / High), Eco, Sleep, Turbo, Silent and Swing toggles (only shown if your unit reports them), indoor temperature and humidity, live wattage, energy use for today / this week / this month, water-tank-full and filter alerts, and C/F switching. Status polls every 20 seconds while the app is in the foreground, and commands update the UI instantly with rollback if the server rejects them.

## Smart Auto limits

The unit's own auto mode picks its own setpoint, so ColdFront's Auto replaces it with app-side logic. It runs every poll while the app is open and on iOS background refresh when it's closed, which iOS schedules on its own terms (often every 15 to 60+ minutes, less if you rarely open the app). For true 24/7 auto switching it has to run on something always on.

## Build

No Xcode needed locally. Push to `main` (or run the workflow manually) and GitHub Actions builds an unsigned `ColdFront.ipa` and publishes it as a GitHub Release (latest is always at the top of the Releases page). Sideload it with AltStore or Sideloadly.

Local build if you ever want it: `brew install xcodegen && xcodegen generate`, then open `ColdFront.xcodeproj`.

## Account notes

Sign in with your ConnectLife email and password. Accounts made with Google/Apple SSO won't work; in the official app, sign out and use "Forgot password" to set a real password. Adding a new device and Wi-Fi provisioning still happen in the official app. If login fails with a terms message, open the official app once and accept the new Terms & Conditions.

## How it talks to the cloud

1. `accounts.eu1.gigya.com/accounts.login` with email/password, then `accounts.getJWT`
2. `oauth.hijuconn.com/oauth/authorize` (thirdType CDC) for a code, then `/oauth/token`
3. Signed calls to `clife-eu-gateway.hijuconn.com`: `get_device_status_list` to read, `device/pu/property/set` to write. Each request carries a random `randStr` and millisecond `timeStamp`; `sign` is RSA-PKCS1 encryption of SHA-256 over the sorted `key=value&...` string plus a fixed suffix.

Portable AC property map (device type 006): `t_power`, `t_work_mode` (0 fan, 1 heat, 2 cool, 3 dry, 4 auto), `t_temp`, `t_temp_type` (0 C, 1 F), `t_fan_speed` (0 auto, 2 low, 3 med, 4 high, 5 quiet), `t_eco`, `t_sleep`, `t_super`, `t_fan_mute`, `t_up_down`, `f_temp_in`, `f_humidity`, `f_power_display`, `f_e_waterfull`, `f-filter`.

Protocol research credit: [oyvindwe/connectlife](https://github.com/oyvindwe/connectlife) and [bilan/connectlife-api-connector](https://github.com/bilan/connectlife-api-connector). This is an independent Swift implementation. Not affiliated with Hisense or ConnectLife; unofficial API, use at your own risk.
