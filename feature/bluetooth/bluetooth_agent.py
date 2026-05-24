#!/usr/bin/env python3

"""
SmartAudio Bluetooth pairing agent.

Development behavior:
- Registers a BlueZ NoInputNoOutput pairing agent.
- Automatically accepts pairing/authorization requests.
- Marks accepted devices as Trusted for future reconnects.

This is suitable for development of a speaker without screen or keyboard.
For production, pairing mode should only be enabled temporarily.
"""

import signal
import sys
from datetime import datetime

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib


BLUEZ_SERVICE = "org.bluez"
AGENT_INTERFACE = "org.bluez.Agent1"
AGENT_MANAGER_INTERFACE = "org.bluez.AgentManager1"
DEVICE_INTERFACE = "org.bluez.Device1"
DBUS_PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"

AGENT_PATH = "/com/smartaudio/bluetooth/agent"
AGENT_CAPABILITY = "NoInputNoOutput"


def log(message: str) -> None:
    """Print timestamped log message."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}", flush=True)


class Rejected(dbus.DBusException):
    """BlueZ rejection exception."""

    _dbus_error_name = "org.bluez.Error.Rejected"


class SmartAudioAgent(dbus.service.Object):
    """BlueZ pairing agent for SmartAudio."""

    def __init__(self, bus: dbus.SystemBus, object_path: str) -> None:
        super().__init__(bus, object_path)
        self.bus = bus

    def trust_device(self, device_path: dbus.ObjectPath) -> None:
        """Mark a BlueZ device as trusted for future reconnections."""
        try:
            device = self.bus.get_object(BLUEZ_SERVICE, device_path)
            properties = dbus.Interface(device, DBUS_PROPERTIES_INTERFACE)
            properties.Set(DEVICE_INTERFACE, "Trusted", dbus.Boolean(True))
            log(f"Device marked as trusted: {device_path}")
        except dbus.DBusException as error:
            log(f"WARNING: Could not mark device trusted: {error}")

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Release(self) -> None:
        log("Agent released by BlueZ.")

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device: dbus.ObjectPath) -> str:
        log(f"PIN code requested for {device}; returning 0000.")
        self.trust_device(device)
        return "0000"

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device: dbus.ObjectPath, pincode: str) -> None:
        log(f"Display PIN code for {device}: {pincode}")

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device: dbus.ObjectPath) -> dbus.UInt32:
        log(f"Passkey requested for {device}; returning 000000.")
        self.trust_device(device)
        return dbus.UInt32(0)

    @dbus.service.method(AGENT_INTERFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(
        self,
        device: dbus.ObjectPath,
        passkey: dbus.UInt32,
        entered: dbus.UInt16,
    ) -> None:
        log(f"Display passkey for {device}: {int(passkey):06d}, entered={int(entered)}")

    @dbus.service.method(AGENT_INTERFACE, in_signature="ou", out_signature="")
    def RequestConfirmation(
        self,
        device: dbus.ObjectPath,
        passkey: dbus.UInt32,
    ) -> None:
        log(f"Auto-confirming pairing for {device}, passkey={int(passkey):06d}.")
        self.trust_device(device)

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device: dbus.ObjectPath) -> None:
        log(f"Auto-authorizing pairing request from {device}.")
        self.trust_device(device)

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device: dbus.ObjectPath, uuid: str) -> None:
        log(f"Auto-authorizing service {uuid} for {device}.")
        self.trust_device(device)

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Cancel(self) -> None:
        log("Pairing request cancelled.")


def main() -> int:
    """Register the agent and run the GLib main loop."""
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    bus = dbus.SystemBus()
    agent = SmartAudioAgent(bus, AGENT_PATH)

    manager_object = bus.get_object(BLUEZ_SERVICE, "/org/bluez")
    manager = dbus.Interface(manager_object, AGENT_MANAGER_INTERFACE)

    try:
        manager.RegisterAgent(AGENT_PATH, AGENT_CAPABILITY)
        manager.RequestDefaultAgent(AGENT_PATH)
    except dbus.DBusException as error:
        log(f"ERROR: Could not register Bluetooth agent: {error}")
        return 1

    log("SmartAudio Bluetooth agent is running.")
    log(f"Agent capability: {AGENT_CAPABILITY}")
    log("Waiting for pairing requests. Press Ctrl+C to stop.")

    loop = GLib.MainLoop()

    def shutdown(_signum: int, _frame: object) -> None:
        log("Stopping Bluetooth agent.")
        try:
            manager.UnregisterAgent(AGENT_PATH)
        except dbus.DBusException:
            pass
        loop.quit()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    try:
        loop.run()
    finally:
        # Keep a reference alive while the loop is active.
        _ = agent

    return 0


if __name__ == "__main__":
    sys.exit(main())
