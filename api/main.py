from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

import os
import psycopg2
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field


app = FastAPI(title="Fleet Telemetry API", version="1.0")


# ---------
# Models
# ---------
class TelemetryIn(BaseModel):
    asset_id: str = Field(..., min_length=1, examples=["aircraft-C130-017"])
    temperature_c: float
    vibration_rms: float
    pressure_psi: float


# ---------
# DB helper
# ---------
def get_conn():
    """
    Creates a new DB connection per request.
    """
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "fleetdb"),
        user=os.getenv("DB_USER", "fleetuser"),
        password=os.getenv("DB_PASSWORD", "fleetpass"),
        connect_timeout=3,
    )


# ---------
# Risk scoring
# ---------
def compute_risk(readings: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """
    Calculates risk score and risk level based on the average of the readings.
    """
    if not readings:
        return None

    avg_temp = sum(r["temperature_c"] for r in readings) / len(readings)
    avg_vib = sum(r["vibration_rms"] for r in readings) / len(readings)
    avg_pressure = sum(r["pressure_psi"] for r in readings) / len(readings)

    risk_points = 0
    max_points = 6  # 2 points per metric

    # Temperature
    if avg_temp > 95:
        risk_points += 2
    elif avg_temp > 85:
        risk_points += 1

    # Vibration
    if avg_vib > 3.5:
        risk_points += 2
    elif avg_vib > 2.5:
        risk_points += 1

    # Pressure
    if avg_pressure < 30 or avg_pressure > 60:
        risk_points += 2
    elif avg_pressure < 35 or avg_pressure > 55:
        risk_points += 1

    risk_score = round(risk_points / max_points, 2)

    if risk_points <= 2:
        risk_level = "LOW"
    elif risk_points <= 4:
        risk_level = "MEDIUM"
    else:
        risk_level = "HIGH"

    return {
        "risk_score": risk_score,
        "risk_points": risk_points,
        "risk_level": risk_level,
        "window_used": len(readings),
        "averages": {
            "temperature_c": round(avg_temp, 2),
            "vibration_rms": round(avg_vib, 2),
            "pressure_psi": round(avg_pressure, 2),
        }
    }


# ---------
# Endpoints
# ---------
@app.get("/health")
def health() -> Dict[str, Any]:
    """
    Health endpoint that checks API + DB connectivity.
    """
    ts = datetime.now(timezone.utc).isoformat()

    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.fetchone()
        cur.close()
        conn.close()

        return {"status": "ok", "db": "ok", "ts": ts}

    except Exception as e:
        return {"status": "degraded", "db": "unreachable", "ts": ts, "error": str(e)}


@app.post("/telemetry", status_code=201)
def create_telemetry(payload: TelemetryIn) -> Dict[str, Any]:
    """
    Inserts one telemetry reading into Postgres.
    """
    try:
        conn = get_conn()
        cur = conn.cursor()

        cur.execute(
            """
            INSERT INTO asset_telemetry (asset_id, temperature_c, vibration_rms, pressure_psi)
            VALUES (%s, %s, %s, %s)
            RETURNING id, recorded_at
            """,
            (
                payload.asset_id,
                payload.temperature_c,
                payload.vibration_rms,
                payload.pressure_psi,
            ),
        )

        row = cur.fetchone()
        conn.commit()

        cur.close()
        conn.close()

        return {"id": row[0], "recorded_at": row[1].isoformat()}

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"db_insert_failed: {str(e)}")


@app.get("/telemetry/latest")
def get_latest_telemetry(
    asset_id: str = Query(..., min_length=1),
    limit: int = Query(5, ge=1, le=50),
) -> Dict[str, Any]:
    """
    Returns latest N telemetry rows for an asset 
    and a risk score and risk level computed over those rows.
    """
    try:
        conn = get_conn()
        cur = conn.cursor()

        cur.execute(
            """
            SELECT id, asset_id, temperature_c, vibration_rms, pressure_psi, recorded_at
            FROM asset_telemetry
            WHERE asset_id = %s
            ORDER BY recorded_at DESC
            LIMIT %s
            """,
            (asset_id, limit),
        )

        rows = cur.fetchall()

        cur.close()
        conn.close()

        readings = []
        for r in rows:
            readings.append(
                {
                    "id": r[0],
                    "asset_id": r[1],
                    "temperature_c": float(r[2]),
                    "vibration_rms": float(r[3]),
                    "pressure_psi": float(r[4]),
                    "recorded_at": r[5].isoformat(),
                }
            )

        risk = compute_risk(readings)

        return {
            "asset_id": asset_id,
            "window_requested": limit,
            "window_used": len(readings),
            "count": len(readings),
            "readings": readings,
            "risk": risk,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"db_read_failed: {str(e)}")