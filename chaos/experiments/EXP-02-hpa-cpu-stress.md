# Chaos Experiment #02: CPU Stress & Horizontal Pod Autoscaler (HPA)

| Metadata | Details |
|---|---|
| **ID** | `EXP-02` |
| **Component** | Kubernetes HPA + Metrics Server |
| **Tool** | `chaos.sh cpu-stress` / `chaos.ps1 cpu-stress` |
| **Severity** | Medium (Resource Saturation) |
| **Target Metric** | Average CPU utilization threshold: 60% |

---

## 1. Objective
Validate that sustained synthetic CPU spikes trigger horizontal autoscaling from the baseline of 3 pods up to the configured limit (up to 10 pods), distributing the load and keeping latency percentiles within SLA.

## 2. Hypothesis
- When CPU usage per pod exceeds 60% of resource requests (100m) for over 15 seconds, HPA scales out the deployment (`scaleUp` policy: +100% or +2 pods).
- Once the computational burst finishes, the stabilization window (60s) prevents thrashing before scaling back down gradually to 3 replicas.

## 3. Execution Steps
```bash
# Watch HPA status
kubectl get hpa localsre-api-hpa -n localsre -w

# Trigger heavy arithmetic calculation across 5 concurrent workers
./chaos/chaos.sh cpu-stress 20 5
# or on Windows PowerShell:
.\chaos\chaos.ps1 cpu-stress -Duration 20 -Concurrency 5
```

## 4. Telemetry & Observability
- **Prometheus Metric**: `sum(rate(container_cpu_usage_seconds_total[1m])) by (pod)`
- **Grafana Panel**: "Total Request Rate" and "CPU Saturation".
- **HPA Output**:
  ```
  NAME               REFERENCE                 TARGETS        MINPODS   MAXPODS   REPLICAS
  localsre-api-hpa   Deployment/localsre-api   142% / 60%     3         10        5
  ```

## 5. Results & Conclusion
- **Initial Replicas**: 3
- **Peak Replicas**: 5 pods during saturation
- **Recovery Time to 3 Replicas**: ~90 seconds (controlled by downscale stabilization window)
- **Conclusion**: **PASSED**. HPA effectively insulated the service from starvation.
