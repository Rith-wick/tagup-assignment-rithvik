import os
import time
import random
import requests


API_BASE = os.getenv("API_BASE", "http://fleet-api:8000")
ASSET_ID = os.getenv("ASSET_ID", "aircraft-C130-017")
INTERVAL_SECONDS = int(os.getenv("INTERVAL_SECONDS", "10"))
WINDOW = int(os.getenv("WINDOW", "5"))


def make_reading():
    """
    Generates random telemetry values.
    """
    return {
        "asset_id": ASSET_ID,
        "temperature_c": round(random.uniform(70.0, 150.0), 1),
        "vibration_rms": round(random.uniform(1.0, 5.0), 2),
        "pressure_psi": round(random.uniform(20.0, 70.0), 1),
    }


def main():
    print(
        f"[client] starting. api={API_BASE} asset_id={ASSET_ID} "
        f"interval={INTERVAL_SECONDS}s window={WINDOW}",
        flush=True,
    )

    while True:
        payload = make_reading()

        # ---- POST telemetry ----
        try:
            r = requests.post(f"{API_BASE}/telemetry", json=payload, timeout=3)
            if r.status_code != 201:
                print(f"[client] POST /telemetry -> {r.status_code} {r.text}", flush=True)
                time.sleep(INTERVAL_SECONDS)
                continue

            post_data = r.json()
            post_id = post_data.get("id")
            post_ts = post_data.get("recorded_at")

            print(
                f"[client] POST /telemetry -> id={post_id} ts={post_ts} "
                f"temp={payload['temperature_c']} vib={payload['vibration_rms']} psi={payload['pressure_psi']}",
                flush=True,
            )

        except Exception as e:
            print(f"[client] POST /telemetry failed: {e}", flush=True)
            time.sleep(INTERVAL_SECONDS)
            continue

        # ---- GET latest telemetry + risk ----
        try:
            r = requests.get(
                f"{API_BASE}/telemetry/latest",
                params={"asset_id": ASSET_ID, "limit": WINDOW},
                timeout=3,
            )
            if r.status_code != 200:
                print(f"[client] GET /telemetry/latest -> {r.status_code} {r.text}", flush=True)
                time.sleep(INTERVAL_SECONDS)
                continue

            data = r.json()
            readings = data.get("readings") or []
            risk = data.get("risk") or {}

            latest = readings[0] if readings else {}

            print(
                f"[client] GET /telemetry/latest -> "
                f"latest_id={latest.get('id')} "
                f"window_used={data.get('window_used')} "
                f"latest_ts={latest.get('recorded_at')} "
                f"temp={latest.get('temperature_c')} "
                f"vib={latest.get('vibration_rms')} "
                f"psi={latest.get('pressure_psi')} "
                f"risk={risk.get('risk_score')} "
                f"level={risk.get('risk_level')}",
                flush=True,
            )

        except Exception as e:
            print(f"[client] GET /telemetry/latest failed: {e}", flush=True)

        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()