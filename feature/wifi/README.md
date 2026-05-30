# Smart Speaker WiFi Provisioning

This feature implements WiFi provisioning for a headless Smart Speaker device based on Raspberry Pi.

The main goal is to allow users to configure WiFi without using a monitor, keyboard, or SSH. When the device cannot connect to a saved WiFi network, it starts its own setup hotspot and web portal so the user can enter a new SSID and password.

---

## 1. Problem

A Smart Speaker is usually a headless embedded device. It does not have a screen or keyboard, so the user needs another way to provide WiFi credentials.

The device must handle these cases:

* First boot: no WiFi has been configured yet.
* Normal boot: a saved WiFi profile exists and should reconnect automatically.
* Recovery case: saved WiFi exists but the router is unavailable, password changed, or the device moved to another location.
* Wrong password: user enters incorrect WiFi credentials during provisioning.
* Safe rollback: if connecting to the new WiFi fails, the device must return to setup mode instead of becoming unreachable.

---

## 2. Design Overview

The feature uses two main operating modes:

### Client Mode

In client mode, the Raspberry Pi connects to a normal WiFi router as a client.

Example:

```text
Router WiFi: Home_WiFi
Raspberry Pi IP: 192.168.1.x
NetworkManager profile: SmartSpeaker-Client
```

This is the normal operating mode of the Smart Speaker.

### AP / Provisioning Mode

In provisioning mode, the Raspberry Pi creates its own WiFi hotspot.

Example:

```text
AP SSID: SmartSpeaker-Setup
Gateway IP: 192.168.4.1
Web portal: Flask application
```

The user connects a phone or laptop to this hotspot, opens the setup page, and enters the target WiFi SSID and password.

---

## 3. Directory Structure

```text
wifi/
├── connect_wifi.sh
├── flask_app.py
├── provision_worker.sh
├── start_ap.sh
├── stop_ap.sh
├── systemd
│   ├── smart-speaker-connect.service
│   ├── smart-speaker-web.service
│   └── wifi-check.service
└── wifi_manager.sh
```

---

## 4. Components

### `wifi_manager.sh`

This is the main WiFi mode manager.

It is called by `wifi-check.service` during boot.

Responsibilities:

* Validate NetworkManager and WiFi interface.
* Check whether the client profile `SmartSpeaker-Client` exists.
* If no client profile exists, start provisioning AP mode.
* If the client profile exists, check whether it is already active and has an IPv4 address.
* If not active, retry connecting to the saved client profile.
* If reconnect fails, enter recovery provisioning mode.

Main decision flow:

```text
Boot
  |
  v
wifi-check.service
  |
  v
wifi_manager.sh
  |
  +--> No SmartSpeaker-Client profile
  |       |
  |       v
  |   Start AP provisioning mode
  |
  +--> SmartSpeaker-Client exists
          |
          v
      Check active connection + IPv4
          |
          +--> OK
          |     |
          |     v
          |  Keep client mode
          |
          +--> Failed
                |
                v
          Retry connection
                |
                +--> Success: keep client mode
                |
                +--> Failed: start AP provisioning mode
```

---

### `start_ap.sh`

This script starts the provisioning hotspot.

Responsibilities:

* Ensure the AP profile `SmartSpeaker-Setup` exists.
* Start the AP/hotspot on `wlan0`.
* Assign the setup gateway IP, usually `192.168.4.1`.
* Start the Flask setup web server through `smart-speaker-web.service`.

Expected result:

```text
SSID: SmartSpeaker-Setup
Gateway: 192.168.4.1
Web portal: running
```

---

### `stop_ap.sh`

This script stops the provisioning hotspot.

It supports multiple modes:

```bash
sudo ./stop_ap.sh --only
```

Stop only the AP/hotspot and keep the Flask web server running.

This mode is used by `connect_wifi.sh` before trying to connect to a new WiFi network. The reason is that `wlan0` must leave AP mode before it can connect as a WiFi client.

```bash
sudo ./stop_ap.sh
```

Stop the AP and stop the setup web server. Then ask NetworkManager to reconnect using a saved profile.

```bash
sudo ./stop_ap.sh "PROFILE_NAME"
```

Stop the AP, stop the setup web server, and explicitly reconnect to a given saved profile.

---

### `smart-speaker-web.service`

This systemd service runs the Flask web portal.

Responsibilities:

* Start `flask_app.py`.
* Provide a simple web interface for the user to enter SSID and password.
* Run only during provisioning mode.

The Flask web server should not run permanently after WiFi setup succeeds.

---

### `flask_app.py`

This is the WiFi setup web portal.

Responsibilities:

* Display a web page for entering WiFi SSID and password.
* Receive WiFi credentials from the user.
* Trigger `smart-speaker-connect.service` to process the connection.
* Show connection status to the user.

The Flask app should not directly perform the WiFi switching logic. Switching `wlan0` from AP mode to client mode can break the current web connection. Therefore, the connection task is delegated to a separate systemd service.

---

### `smart-speaker-connect.service`

This systemd service runs the WiFi connection worker.

Responsibilities:

* Execute the connection flow outside of the Flask request handler.
* Call `connect_wifi.sh`.
* Allow Flask to remain available while the connection attempt is running.

This separation avoids a dangerous situation where the web server kills its own network path before the connection process is complete.

---

### `connect_wifi.sh`

This script connects the Smart Speaker to the WiFi network provided by the user.

Responsibilities:

* Receive SSID and password.
* Write provisioning status to `/run/smart-speaker-wifi-status`.
* Remove the old `SmartSpeaker-Client` profile if needed.
* Stop AP mode using `stop_ap.sh --only`.
* Scan for WiFi networks.
* Create and activate a new `SmartSpeaker-Client` profile using NetworkManager.
* Enable autoconnect for the new profile.
* Verify that the active profile is `SmartSpeaker-Client`.
* Verify that the interface has an IPv4 address.
* Stop the Flask web server after successful provisioning.
* Restore AP mode if the connection fails.

Success flow:

```text
User submits SSID/password
  |
  v
connect_wifi.sh
  |
  v
Write status: connecting
  |
  v
Stop AP only
  |
  v
Connect to new WiFi
  |
  v
Verify active profile + IPv4
  |
  v
Stop Flask web server
  |
  v
Client mode ready
```

Failure flow:

```text
User submits wrong SSID/password
  |
  v
connect_wifi.sh
  |
  v
Connection failed
  |
  v
Write status: error
  |
  v
Restore SmartSpeaker-Setup AP
  |
  v
User can reconnect and try again
```

---

## 5. NetworkManager Profiles

This feature uses NetworkManager profiles instead of hardcoding SSIDs.

### `SmartSpeaker-Client`

This is the internal client profile name used by the project.

It is not the actual router SSID.

Example:

```text
Profile name: SmartSpeaker-Client
Real SSID: Home_WiFi
Password: user-provided password
Interface: wlan0
Autoconnect: yes
```

The real SSID and password are provided by the user through the web portal.

### `SmartSpeaker-Setup`

This is the AP/hotspot profile used for provisioning.

Example:

```text
Profile name: SmartSpeaker-Setup
AP SSID: SmartSpeaker-Setup
Gateway IP: 192.168.4.1
```

---

## 6. Why NetworkManager?

NetworkManager is used because it provides a unified way to manage Linux network connections.

Benefits:

* Manage saved WiFi profiles.
* Enable autoconnect.
* Set connection priority.
* Switch between client mode and hotspot mode.
* Check active connections.
* Scan WiFi networks.
* Avoid manually combining `wpa_supplicant`, `dhcpcd`, `hostapd`, `dnsmasq`, and raw `ip addr` commands.

Without NetworkManager, the project would need to manually coordinate:

```text
wpa_supplicant  -> WiFi client connection
dhcpcd          -> DHCP client
hostapd         -> AP mode
dnsmasq         -> DHCP server for AP clients
ip addr         -> IP address configuration
route/DNS       -> routing and DNS behavior
systemd         -> service ordering
```

Trade-offs:

* NetworkManager is heavier than a minimal manual setup.
* It must be configured carefully to avoid conflicts with other network tools.
* On very small embedded Linux systems, it may be too large.
* Developers must understand profile state, active connection state, autoconnect, and interface ownership.

---

## 7. Important Concepts

### Saved Profile vs Active Connection

A saved profile only means NetworkManager has stored connection settings.

It does not mean the WiFi is currently connected.

```text
Saved profile exists != WiFi connected
```

### Active Connection vs Usable Network

An active connection means the profile is active on an interface.

It does not always mean the network is fully usable.

```text
Active connection != IPv4 assigned
Active connection != Internet available
```

The current implementation checks:

```text
Active profile == SmartSpeaker-Client
IPv4 address is not empty
```

This is enough for the current project stage, but a production version could also check gateway, DNS, or Internet reachability.

### AP Mode vs Provisioning Mode

AP mode is a WiFi interface mode.

Provisioning mode is a product state.

In this project, provisioning mode includes:

```text
AP mode
+ Flask web portal
+ User credential input
+ Connection worker
+ Rollback logic
```

AP mode alone is not enough to be considered a complete provisioning flow.

---

## 8. Systemd Services

### `wifi-check.service`

Runs at boot.

Purpose:

```text
Start wifi_manager.sh and decide the WiFi operating mode.
```

This service is suitable for `Type=oneshot` because it only needs to run once during boot and then exit.

### `smart-speaker-web.service`

Runs the Flask web portal.

Purpose:

```text
Provide the WiFi setup page during provisioning mode.
```

This service should stay running while the web portal is needed.

### `smart-speaker-connect.service`

Runs the WiFi connection job.

Purpose:

```text
Handle WiFi switching outside of the Flask request.
```

This prevents the Flask app from directly disrupting its own network path.

---

## 9. Debug Commands

Check WiFi manager service:

```bash
sudo systemctl status wifi-check.service --no-pager -l
sudo journalctl -b -u wifi-check.service --no-pager
```

Check active NetworkManager connections:

```bash
nmcli --escape no -t -f NAME,TYPE,DEVICE connection show --active
```

Check WiFi device state:

```bash
nmcli device status
```

Check active connection on `wlan0`:

```bash
nmcli --escape no -g GENERAL.CONNECTION device show wlan0
```

Check IPv4 address:

```bash
nmcli --escape no -g IP4.ADDRESS device show wlan0
ip addr show wlan0
```

Check Flask web service:

```bash
sudo systemctl status smart-speaker-web.service --no-pager -l
sudo journalctl -b -u smart-speaker-web.service --no-pager -l
```

Check whether Flask is listening on port 5000:

```bash
sudo ss -ltnp | grep 5000
```

Expected when web portal is running:

```text
0.0.0.0:5000
```

If it only listens on `127.0.0.1:5000`, external devices connected to the AP may not be able to access it.

---

## 10. Typical Test Scenarios

### First Boot

Expected behavior:

```text
No SmartSpeaker-Client profile
-> Start SmartSpeaker-Setup AP
-> Start Flask web portal
```

### Valid WiFi Credentials

Expected behavior:

```text
User enters correct SSID/password
-> Stop AP only
-> Connect to target WiFi
-> Create SmartSpeaker-Client profile
-> Enable autoconnect
-> Verify IPv4
-> Stop Flask
-> Client mode ready
```

### Wrong WiFi Password

Expected behavior:

```text
User enters wrong password
-> Connection fails
-> Write error status
-> Restore SmartSpeaker-Setup AP
-> User can try again
```

### Move Device to Another Location

Expected behavior:

```text
SmartSpeaker-Client exists
-> Try reconnecting saved profile
-> Reconnect fails
-> Start recovery provisioning mode
-> User enters new WiFi credentials
```

---

## 11. Current Limitations

The current implementation is suitable for learning and project demonstration, but it is not yet a production-grade provisioning system.

Known limitations:

* It verifies IPv4 but does not fully verify Internet access.
* It may delete the old client profile before the new WiFi is fully confirmed.
* Web portal security is still basic.
* AP provisioning timeout is not fully implemented.
* Error classification can be improved.
* No physical factory reset button yet.
* No LED/audio feedback yet.

---

## 12. Future Improvements

Possible improvements:

* Add AP password or provisioning token.
* Add timeout for provisioning mode.
* Add factory reset or config button.
* Add LED feedback for WiFi states.
* Add audio feedback for setup success/failure.
* Show available SSIDs in the web portal.
* Improve status reporting: wrong password, SSID not found, DHCP timeout, DNS failure.
* Keep old WiFi profile as fallback until the new connection is verified.
* Implement a clearer state machine.
* Add structured logs with severity levels.

Example future state machine:

```text
INIT
CHECK_PROFILE
CLIENT_CONNECTING
CLIENT_CONNECTED
AP_STARTING
PROVISIONING
CONNECTING_NEW_WIFI
ROLLBACK_AP
ERROR
```

---

## 13. Lessons Learned

Key lessons from this feature:

* WiFi provisioning is not just about connecting to WiFi.
* A headless device must always keep a recovery path.
* AP mode should not stay enabled forever.
* Hardcoding SSID is not suitable for real devices.
* NetworkManager profiles make the design more flexible.
* `systemd` is better than `.bashrc` for boot-time service behavior.
* Active WiFi connection does not always mean usable network.
* Rollback is critical when switching from AP mode to client mode.
* Provisioning mode is a product state, not just a WiFi mode.

---

## 14. Summary

This WiFi provisioning feature allows the Smart Speaker to configure WiFi without a screen or keyboard.

It combines:

```text
NetworkManager
systemd
Flask web portal
AP mode
Client mode
Connection profiles
Status file
Retry logic
Rollback logic
```

The most important design point is safety:

```text
If client WiFi fails, the device must return to AP provisioning mode so the user can recover it.
```

This makes the feature closer to a real embedded/headless product behavior, not just a simple WiFi connection script.
