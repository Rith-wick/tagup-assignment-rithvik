# Fleet Telemetry – Kubernetes Assignment

This project implements a simple **fleet telemetry system** running on a local Kubernetes cluster.

The system models a fleet of assets (for example, aircraft, helicopters, tanks, or other defense platforms) that periodically emit telemetry data such as temperature, vibration, and pressure.

It consists of **three separate pods**:
- **Database**: PostgreSQL storing telemetry readings
- **API**: FastAPI service that writes to and reads from the database
- **Client**: A background worker that generates telemetry on a fixed cadence (every 10s)

The API computes a **risk score and risk level** for an asset based on the **latest N telemetry readings**.

---

## Prerequisites

Required on both Windows and macOS:

- Docker (Docker Desktop)
- Kubernetes CLI: `kubectl`
- Kind (Kubernetes in Docker)

Additional:
- **Windows**: PowerShell (built-in)
- **macOS**: PowerShell (`pwsh`)
  ```bash
  brew install powershell
  ```

---

## Quick Start (recommended)

### Windows
```powershell
.\run.ps1
```

### macOS
```bash
./run.sh
```
or

```bash
make up
```

This will:
- Create a local Kind cluster (if needed)
- Deploy database, API, and client pods
- Wait until everything is ready
- Print next steps

---

## Using the system

### 1. Open the API (Swagger UI)

Windows:
```powershell
.\run.ps1 -PortForward
```
macOS:
```bash
./run.sh -PortForward
```
or

```bash
make port-forward
```

Open:
```
http://127.0.0.1:8000/docs
```

In Swagger:

**POST `/telemetry`**
- Create a telemetry record
- Use an asset ID such as:
  ```
  aircraft-C130-017
  ```

**GET `/telemetry/latest`**
- Use the same `asset_id`
- Set `limit=5`
- Response includes:
  - latest telemetry rows from the database
  - computed `risk_score` and `risk_level`

---

### 2. Observe client cadence and risk computation

Windows:
```powershell
.\run.ps1 -Logs
```
macOS:
```bash
./run.sh -Logs
```
or

```bash
make logs
```

Client logs show:
- telemetry values being posted
- latest DB-backed readings being retrieved
- risk score and level changing over time

This confirms:
- client → API communication
- API → DB reads
- rolling window logic

---

### 3. Inspect database directly (optional)

Windows:
```powershell
.\run.ps1 -Psql
```
macOS:
```bash
./run.sh -Psql
```
or

```bash
make psql
```

Example query:
```sql
SELECT *
FROM asset_telemetry
ORDER BY recorded_at DESC
LIMIT 5;
```

---

## Management commands

- Stop client only `-Down`
- Reset app + wipe DB `-Reset`
- Delete entire cluster `-Nuke`

Example:

Windows:
```powershell
.\run.ps1 -Down
```
macOS:
```bash
./run.sh -Down
```
or

```bash
make down
```

---

## Manual setup (fallback)

If needed, everything can be run manually:

```bash
kind create cluster --name tagup
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres.yaml -n fleet
kubectl apply -f k8s/api.yaml -n fleet
kubectl apply -f k8s/client.yaml -n fleet
kubectl wait --for=condition=Ready pod --all -n fleet
```

Port-forward API:
```bash
kubectl port-forward -n fleet svc/fleet-api 8000:8000
```

Tail client logs:
```bash
kubectl logs -n fleet -f deployment/fleet-client
```

---

## Assignment checklist

- Local Kubernetes cluster (Kind)
- 3 separate pods for database, API, and client
- API connects to database
- Client queries API on a cadence

All requirements are implemented and observable via logs, API responses, and database state.
