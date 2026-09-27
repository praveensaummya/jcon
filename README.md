# JCON — ESP32-S3 Inverter Control App

Flutter companion app for the
[ESP32-S3 voice-controlled inverter firmware](https://github.com/praveensaummya/en_speech_commands_custom)
(`en_speech_commands_custom`). It discovers the device on the LAN, switches
its relays, toggles the on-device voice recognition, provisions Wi-Fi — over
**local HTTP first, with cloud MQTT as a fallback**.

> **Download the app:** prebuilt APKs are attached to the
> [Releases page](https://github.com/praveensaummya/jcon/releases) — built
> automatically from every `v*` tag by CI. See [Building](#building) to
> compile it yourself.

## Features

* **Automatic device discovery** — real mDNS resolution of
  `esp32-inverter.local` (with a cached-IP fast path and an OS-level
  `.local` fallback). Every candidate is verified with `GET /api/status`
  before it is trusted.
* **Subnet scanner** — parallel probe of all 254 hosts on the phone's
  subnet, port 8080, as a last-resort discovery option.
* **Hybrid relay & voice commands** — three communication modes
  (`auto` / `http` / `mqtt`):
  * `auto` (default): local HTTP first, automatic MQTT cloud fallback
  * `http`: local HTTP only
  * `mqtt`: direct cloud publish (works even when off the home LAN)
* **Wi-Fi provisioning** — walks the ESP32's `esp-wifi-manager` captive
  portal (AP scan → send credentials → join), no serial cable needed.
* **Customisable dashboard** — relay names, MQTT topics and JSON payload
  templates are user-editable and stored on the device.
* **Per-broker MQTT settings** — broker URI/username/password are saved on
  the phone and pushed to the firmware with `POST /api/config/mqtt`.

## Project layout (lib/)

| File | Role |
|---|---|
| `main.dart` | App entry point, Material 3 theme |
| `home_screen.dart` | Dashboard: relay cards, voice toggle, reachability, terminal log |
| `device_discovery_service.dart` | mDNS + cached-IP + `.local` discovery, `/api/status` verification |
| `subnet_scanner.dart` | Parallel 254-host port-8080 scanner |
| `relay_control_service.dart` | Hybrid command sender (HTTP/MQTT/auto) for relays + voice |
| `wifi_provisioning_service.dart` | Talks to the esp-wifi-manager AP endpoints |
| `mqtt_http_config_screen.dart` | Device IP/port, broker settings, comm mode |
| `mqtt_cmd_config_screen.dart` | Relay names, topics, payload templates |
| `wifi_setup_screen.dart` | Wi-Fi provisioning UI |
| `add_device_screen.dart` | "Device Settings" hub screen |
| `demo_service.dart` | 20-minute demo lock (**disabled** by default: `isDemoEnabled = false`) |
| `telemetry_ban_service.dart` | Educational security-demo module — **every switch is OFF by default**, see disclaimer in that file |

## Getting started (run from source)

Requirements: Flutter SDK (developed on **3.44.x** / Dart ≥ 3.12), Android
SDK + JDK 17 or newer (CI uses 17; Gradle 9.1 supports up to Java 25), and
an ESP32-S3 flashed with the
[firmware](https://github.com/praveensaummya/en_speech_commands_custom).

```bash
git clone https://github.com/praveensaummya/jcon.git
cd jcon
flutter pub get
flutter run          # debug build on a connected device/emulator
```

## Building

### Locally (one command)

```bash
./tool/build_release.sh               # release APK
./tool/build_release.sh --appbundle   # additionally build a Play Store .aab
./tool/build_release.sh --skip-analyze
```

The script runs `pub get` + `flutter analyze` + release build, then copies
the APK to `dist/jcon-v<version>-<yyyymmdd>.apk` with a `SHA256SUMS` file.

### CI (automatic releases)

`.github/workflows/release.yml` builds the APK on every `v*` tag and
attaches it to the GitHub Release:

```bash
git tag v1.0.1
git push origin v1.0.1
```

The APK then appears at
[github.com/praveensaummya/jcon/releases](https://github.com/praveensaummya/jcon/releases).
Manual builds: **Actions → Build & Release APK → Run workflow** (result is
uploaded as a workflow artifact).

## Default connection settings

All user-changeable in the app's *Device Settings* screens; defaults match
the firmware's `main/include/app_config.h`.

| Setting | Default | SharedPreferences key |
|---|---|---|
| Device host | `esp32-inverter.local` | `esp32_ip` |
| Device port | `8080` | `esp32_port` |
| Comm mode | `auto` | `comm_mode` |
| Relay command topic | `device/relays/command` | `mqtt_cmd_topic` |
| Voice command topic | `device/voice/command` | `mqtt_voice_topic` |
| MQTT broker | *(set in MQTT/HTTP config screen)* | `mqtt_uri` / `mqtt_user` / `mqtt_pass` |

## Firmware protocol

Every endpoint the app calls (with real payloads, CORS behaviour and mDNS
details) is documented from the firmware side in
[docs/JCON_APP.md](https://github.com/praveensaummya/en_speech_commands_custom/blob/main/docs/JCON_APP.md)
of the firmware repository. If you change the firmware API, update that
document and the services here in the same change.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Device not found | Phone & ESP32 on the same network (ESP32-S3 is **2.4 GHz only**); guest networks / AP isolation block mDNS — enter the device IP manually in Device Settings |
| `http` mode commands fail | Device offline/server down — switch to `auto` so MQTT fallback takes over |
| `mqtt` mode fails | Broker must be `mqtts://…` with TLS port (e.g. 8883); verify user/password in the MQTT/HTTP config screen |
| Subnet scan finds nothing | Some routers throttle simultaneous connections — rescan or use mDNS discovery instead |

## Security / educational disclaimer

`lib/telemetry_ban_service.dart` is a **teaching module** that simulates
spyware-style data-harvesting behaviour for security education. It ships
**fully disabled** (all compile-time switches `false`) and this app is not
intended for public store distribution. Read the disclaimer at the top of
that file before touching any of its switches.

