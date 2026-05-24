import os
import subprocess

from flask import Flask, request, render_template_string
from markupsafe import escape

app = Flask(__name__)

CREDENTIAL_FILE = "/run/smart-speaker-wifi-credentials"
STATUS_FILE = "/run/smart-speaker-wifi-status"
CONNECT_SERVICE = "smart-speaker-connect.service"

HTML_FORM = """
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Smart Speaker Setup</title>
</head>
<body>
    <h1>Smart Speaker WiFi Setup</h1>

    {% if error_message %}
        <div style="padding: 12px; margin-bottom: 16px; border: 1px solid #cc0000; color: #cc0000;">
            <strong>Connect failedi.</strong><br>
            {{ error_message }}
        </div>
    {% endif %}

    <form method="POST" action="/connect">
        <label for="ssid">WiFi SSID:</label><br>
        <input id="ssid" type="text" name="ssid" value="{{ previous_ssid }}" required><br><br>

        <label for="password">Password:</label><br>
        <input id="password" type="password" name="password" required><br><br>

        <button type="submit">Connect</button>
    </form>
</body>
</html>
"""


def provisioning_job_is_running():
    result = subprocess.run(
        ["/usr/bin/systemctl", "is-active", "--quiet", CONNECT_SERVICE],
        check=False
    )
    return result.returncode == 0


def read_provisioning_status():
    try:
        with open(STATUS_FILE, "r", encoding="utf-8") as status_file:
            lines = status_file.read().splitlines()
    except FileNotFoundError:
        return "", ""

    state = lines[0] if len(lines) >= 1 else ""
    ssid = lines[1] if len(lines) >= 2 else ""

    return state, ssid


def save_credentials(ssid, password):
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(CREDENTIAL_FILE, flags, 0o600)

    with os.fdopen(fd, "w", encoding="utf-8") as credential_file:
        credential_file.write(ssid + "\n")
        credential_file.write(password + "\n")
        credential_file.flush()
        os.fsync(credential_file.fileno())

    os.chmod(CREDENTIAL_FILE, 0o600)


@app.route("/", methods=["GET"])
def index():
    state, previous_ssid = read_provisioning_status()

    error_message = ""
    if state == "error":
        error_message = (
            f"Unable to connect to WiFi '{previous_ssid}'. "
            "Please double-check your password and try again."
        )

    return render_template_string(
        HTML_FORM,
        error_message=error_message,
        previous_ssid=previous_ssid if state == "error" else ""
    )


@app.route("/connect", methods=["POST"])
def connect():
    ssid = request.form.get("ssid", "").strip()
    password = request.form.get("password", "")

    if not ssid:
        return "SSID is required", 400

    if not password:
        return "Password is required", 400

    if "\n" in ssid or "\r" in ssid or "\n" in password or "\r" in password:
        return "Invalid WiFi information", 400

    if provisioning_job_is_running():
        return """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
            <meta charset="UTF-8">
            <title>Connecting</title>
        </head>
        <body>
            <h1>Connection is already in progress</h1>
            <p>Please wait while Smart Speaker connects to WiFi.</p>
        </body>
        </html>
        """, 409

    try:
        save_credentials(ssid, password)

        result = subprocess.run(
            [
                "/usr/bin/systemctl",
                "start",
                "--no-block",
                CONNECT_SERVICE,
            ],
            check=False,
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            try:
                os.remove(CREDENTIAL_FILE)
            except FileNotFoundError:
                pass

            return "Unable to start WiFi connection job", 500

    except OSError:
        try:
            os.remove(CREDENTIAL_FILE)
        except FileNotFoundError:
            pass

        return "Unable to save WiFi information", 500

    safe_ssid = escape(ssid)

    return f"""
    <!DOCTYPE html>
    <html lang="vi">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Connecting WiFi</title>
    </head>
    <body>
        <h1>Connecting to WiFi</h1>
        <p>Smart Speaker is connecting to: <strong>{safe_ssid}</strong></p>
        <p>The setup WiFi network may disappear in a few seconds.</p>
        <p>Please reconnect your phone or laptop to the selected WiFi network.</p>
    </body>
    </html>
    """


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
