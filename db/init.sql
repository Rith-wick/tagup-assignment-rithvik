-- db/init.sql
-- Stores periodic telemetry readings for fleet assets (defense simulation).

CREATE TABLE IF NOT EXISTS asset_telemetry (
  id SERIAL PRIMARY KEY,
  asset_id TEXT NOT NULL,            -- e.g. "aircraft-C130-017"
  temperature_c DOUBLE PRECISION NOT NULL,
  vibration_rms DOUBLE PRECISION NOT NULL,
  pressure_psi DOUBLE PRECISION NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast retrieval of recent readings per asset
CREATE INDEX IF NOT EXISTS idx_asset_telemetry_asset_time
ON asset_telemetry (asset_id, recorded_at DESC);
