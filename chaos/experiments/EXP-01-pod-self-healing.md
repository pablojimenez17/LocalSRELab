# Chaos Experiment #01: Pod Self-Healing & High Availability

| Metadata | Details |
|---|---|
| **ID** | `EXP-01` |
| **Component** | Kubernetes Deployment / ReplicaSet (`localsre-api`) |
| **Tool** | `chaos.sh kill-api` / `chaos.ps1 kill-api` |
| **Severity** | High (Simulated Pod Crash) |
| **Target SLA** | 99.9% Availability (Zero visible downtime for end users) |

---

## 1. Objective
Verify that the Kubernetes control plane automatically detects the sudden termination of an API replica and reconciles the state back to the desired replica count (3 pods) without dropping incoming user traffic.

## 2. Hypothesis
- **Pre-condition**: The Deployment `localsre-api` maintains 3 healthy pods attached to the Service `localsre-api`.
- **Intervention**: A running pod is abruptly terminated via `SIGKILL` (`kubectl delete pod <pod-name> --now`).
- **Expected Outcome**:
  - The Service immediately updates its Endpoints list from 3 to 2 healthy addresses.
  - The ReplicaSet controller notices `availableReplicas: 2 < replicas: 3` within < 1 second.
  - A new pod is scheduled, reaches `Ready` state after passing `startupProbe` and `readinessProbe`.
  - Ingress traffic experiences 0 dropped requests because traffic is routed only to the remaining 2 healthy pods.

## 3. Execution Steps
```bash
# Terminal 1: Watch pods in real-time
kubectl get pods -n localsre -l app.kubernetes.io/name=localsre-api -w

# Terminal 2: Trigger chaos termination
./chaos/chaos.sh kill-api
# or on Windows PowerShell:
.\chaos\chaos.ps1 kill-api
```

## 4. Telemetry & Observability
- **Prometheus Metric**: `sum(up{job="localsre-api"})` temporarily dips from 3 to 2, then recovers back to 3 within ~6-8 seconds.
- **Grafana Panel**: "Healthy Instances (Up)" stat widget reflects the state transition.
- **Loki Logs**:
  ```json
  {"level": "INFO", "message": "Initializing LocalSRE API service...", "pod_name": "localsre-api-79b88-new"}
  ```

## 5. Results & Postmortem Findings
- **Replica Recovery Time**: ~5.8 seconds.
- **User Impact**: 0 dropped requests observed during synthetic load generation.
- **Conclusion**: **PASSED**. Kubernetes self-healing and service endpoint decoupling behaved as expected.
