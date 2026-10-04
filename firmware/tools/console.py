#!/usr/bin/env python3
"""Talk to an Ink Frame over USB (firmware/src/provision/serial_console.h).

Opening the port resets the frame; it then listens for a command for 1.5 s. Run with
PlatformIO's Python, which has pyserial (README.md):

  console.py info                                   the frame and its memory card
  console.py provision --ssid Home --api-base-url https://<ref>.supabase.co/functions/v1 \\
      --pairing-token <token> [--erase-sd]          Wi-Fi password from WIFI_PASSWORD, or asked
  console.py sync [--full] | wifi_scan | erase_sd | reset
  console.py show image.png [--minutes 30]          draw a PNG as it is (calibration), then
                                                    sleep that long keeping it on screen
  console.py log [seconds]                          just the logs, after a reset
  console.py ota [--feed URL]                       a firmware update now (docs/ota.md); after
                                                    "installed", `log 90` shows its trial
"""
import argparse
import getpass
import json
import os
import sys
import time

import serial

DONE_STATES = {"ready", "error", "wifi_failed"}


def open_port(port):
    s = serial.Serial()
    s.port, s.baudrate, s.timeout = port, 115200, 0.2
    s.dtr = False  # IO0 high: boot the firmware, not the ROM loader
    s.rts = False
    s.open()
    s.reset_output_buffer()  # anything left from an interrupted transfer
    s.rts = True  # EN low: reset
    time.sleep(0.1)
    s.rts = False
    return s


def lines(s, until):
    buf = b""
    while time.time() < until:
        buf += s.read(4096)
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            yield line.decode("utf-8", "replace").rstrip("\r")


def run(port, command, finished, timeout, show_logs):
    s = open_port(port)
    sent = False
    for line in lines(s, time.time() + timeout):
        if line.startswith("@ "):
            reply = json.loads(line[2:])
            print(json.dumps(reply))
            if finished(reply):
                s.write(b'{"cmd":"run"}\n')
                return 0
        elif show_logs or not sent:
            print(f"  {line}", file=sys.stderr)
        if not sent and line.startswith("Ink Frame "):
            s.write((json.dumps(command) + "\n").encode())
            sent = True
    print("timed out" if sent else "the frame didn't start (power switch on?)", file=sys.stderr)
    return 1


def show(port, path, minutes, show_logs):
    data = open(path, "rb").read()
    s = open_port(port)
    state = "boot"
    for line in lines(s, time.time() + 120):
        if line.startswith("@ "):
            reply = json.loads(line[2:])
            if state == "sent" and reply.get("ready"):
                s.write(data)  # the frame reads exactly len(data) raw bytes
                state = "data"
                print(f"sending {len(data)} bytes…", file=sys.stderr)
            elif "shown" in reply:
                print(json.dumps(reply))
                if not reply["shown"]:
                    s.write(b'{"cmd":"run"}\n')
                    return 1
                s.write((json.dumps({"cmd": "sleep", "minutes": minutes}) + "\n").encode())
                print(f"on the screen; the frame sleeps {minutes} min (a button wakes it)", file=sys.stderr)
                return 0
        elif show_logs or state == "boot":
            print(f"  {line}", file=sys.stderr)
        if state == "boot" and line.startswith("Ink Frame "):
            s.write((json.dumps({"cmd": "show", "bytes": len(data)}) + "\n").encode())
            state = "sent"
    print("timed out" if state != "boot" else "the frame didn't start (power switch on?)", file=sys.stderr)
    return 1


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", default=os.environ.get("INKFRAME_PORT", "/dev/cu.usbserial-110"))
    p.add_argument("--logs", action="store_true", help="show the frame's logs too")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info")
    sub.add_parser("wifi_scan")
    sub.add_parser("erase_sd")
    sub.add_parser("reset")
    sp = sub.add_parser("sync")
    sp.add_argument("--full", action="store_true")
    pp = sub.add_parser("provision")
    pp.add_argument("--ssid", required=True)
    pp.add_argument("--api-base-url", required=True)
    pp.add_argument("--pairing-token", required=True)
    pp.add_argument("--erase-sd", action="store_true")
    shp = sub.add_parser("show")
    shp.add_argument("image")
    shp.add_argument("--minutes", type=int, default=30)
    op = sub.add_parser("ota")
    op.add_argument("--feed", help="a test feed (http:// allowed), else the real one")
    lp = sub.add_parser("log")
    lp.add_argument("seconds", nargs="?", type=float, default=20)
    a = p.parse_args()

    if a.cmd == "log":
        s = open_port(a.port)
        for line in lines(s, time.time() + a.seconds):
            print(line)
        return 0
    if a.cmd == "show":
        return show(a.port, a.image, a.minutes, a.logs)
    if a.cmd == "provision":
        password = os.environ.get("WIFI_PASSWORD")
        if password is None:
            password = getpass.getpass(f"Password for {a.ssid} (empty for an open network): ")
        cmd = {"cmd": "provision", "ssid": a.ssid, "password": password, "api_base_url": a.api_base_url,
               "pairing_token": a.pairing_token, "erase_sd": a.erase_sd}
        return run(a.port, cmd, lambda r: r.get("state") in DONE_STATES, 300, a.logs)
    if a.cmd == "wifi_scan":
        return run(a.port, {"cmd": "wifi_scan"}, lambda r: r.get("done"), 60, a.logs)
    if a.cmd == "sync":
        return run(a.port, {"cmd": "sync", "full": a.full}, lambda r: "sync" in r, 600, a.logs)
    if a.cmd == "ota":
        cmd = {"cmd": "ota", **({"feed": a.feed} if a.feed else {})}
        return run(a.port, cmd, lambda r: "ota" in r, 300, a.logs)
    timeouts = {"erase_sd": 300}
    return run(a.port, {"cmd": a.cmd}, lambda r: True, timeouts.get(a.cmd, 30), a.logs)


if __name__ == "__main__":
    sys.exit(main())
