# Chaos Experiment #03: Dependency Failure & Readiness Decoupling

| Metadata | Details |
|---|---|
| **ID** | `EXP-03` |
| **Component** | Kubernetes Readiness Probe (`/readyz`) & Endpoint Controller |
| **Tool** | `chaos.sh partition-db` / `chaos.ps1 partition-db` |
| **Severity** | Critical (Backend Degraded) |
| **Target SLA** | No cascade failures: Unhealthy pods must not receive traffic |

---

## 1. Objective
Demonstrate the fundamental difference between **Liveness** (`/healthz`) and **Readiness** (`/readyz`). When a downstream dependency (PostgreSQL or Redis) becomes unreachable, the pod must:
1. **NOT** be killed/restarted by Kubernetes (liveness probe stays green, avoiding crash loops).
2. **Be instantly removed from the Service Endpoints** (readiness probe returns 503, preventing users from receiving broken 500 pages).

## 2. Hypothesis
- Calling `/chaos/unready` or stopping PostgreSQL will cause `/readyz` to return `HTTP 503 Service Unavailable`.
- Kubernetes will set `Ready: 0/1` for the degraded pod.
- `kubectl get endpoints localsre-api` will drop the IP of that specific pod.
- Other pods continue serving traffic uninterruptedly.

## 3. Execution Steps
```bash
# Terminal 1: Monitor Service Endpoints
kubectl get endpoints localsre-api -n localsre -w

# Terminal 2: Trigger temporary degradation
./chaos/chaos.sh partition-db 30
# or on Windows PowerShell:
.\chaos\chaos.ps1 partition-db -Duration 30
```

## 4. Telemetry & Observability
- **HTTP Status Check**:
  ```bash
  curl -i http://localhost:8000/readyz
  # HTTP/1.1 503 Service Unavailable
  # {"status":"degraded","reason":"chaos_forced_unready"}
  ```
- **Endpoints Controller**:
  `ENDPOINTS: 10.1.0.45:8000, 10.1.0.47:8000` (Degraded pod removed).

## 5. Results & Conclusion
- **CrashLoopBackOff occurred?**: No. Process stayed intact.
- **Traffic drop**: Traffic shifted seamlessly to surviving replicas.
- **Conclusion**: **PASSED**. Proves why separating liveness from readiness is essential SRE architecture.
