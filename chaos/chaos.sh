#!/usr/bin/env bash
# ==============================================================================
# LocalSRE Lab - Chaos Engineering Toolkit
# ==============================================================================
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-localsre}"
API_URL="${API_URL:-http://localhost:8000}"

COLOR_RESET="\033[0m"
COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_BLUE="\033[1;34m"
COLOR_CYAN="\033[1;36m"

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1"
}

banner() {
    echo -e "${COLOR_CYAN}"
    echo "================================================================"
    echo "            🔥 LocalSRE Lab - Chaos Engineering Suite          "
    echo "================================================================"
    echo -e "${COLOR_RESET}"
}

usage() {
    banner
    echo "Usage: $0 [command]"
    echo ""
    echo "Available Commands:"
    echo "  kill-api       Randomly terminates one API pod to verify self-healing"
    echo "  cpu-stress     Injects heavy CPU load to observe HPA autoscaling"
    echo "  error-spike    Fires continuous HTTP 500 errors to trigger Prometheus alerts"
    echo "  partition-db   Forces pod unready state to verify traffic isolation"
    echo "  status         Checks pod health, endpoints, and probe statuses"
    echo "  help           Displays this help screen"
    echo ""
}

cmd_status() {
    log_info "Checking Kubernetes resources in namespace: ${NAMESPACE}"
    if command -v kubectl &> /dev/null; then
        kubectl get pods,svc,hpa -n "${NAMESPACE}" -o wide || true
        echo ""
        log_info "Active Endpoints in Service 'localsre-api':"
        kubectl get endpoints localsre-api -n "${NAMESPACE}" || true
    fi

    echo ""
    log_info "Probing API at ${API_URL}..."
    if command -v curl &> /dev/null; then
        echo -n "Liveness (/healthz): "
        curl -s "${API_URL}/healthz" || echo "Unreachable"
        echo ""
        echo -n "Readiness (/readyz): "
        curl -s "${API_URL}/readyz" || echo "Unreachable"
        echo ""
    fi
}

cmd_kill_api() {
    banner
    log_warn "Experiment #01: Pod Self-Healing & High Availability"
    log_info "Targeting namespace: ${NAMESPACE}"

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl command not found in PATH."
        exit 1
    fi

    PODS=($(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=localsre-api -o jsonpath='{.items[*].metadata.name}'))

    if [ ${#PODS[@]} -eq 0 ]; then
        log_error "No API pods found in namespace ${NAMESPACE}. Is the lab deployed?"
        exit 1
    fi

    # Select random pod
    TARGET_POD=${PODS[$RANDOM % ${#PODS[@]}]}

    log_warn "Killing random API pod: ${TARGET_POD}..."
    kubectl delete pod "${TARGET_POD}" -n "${NAMESPACE}" --wait=false

    echo ""
    log_info "Observing Kubernetes ReplicaSet recreation in real-time (10s watch)..."
    kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=localsre-api -w --timeout=15s || true

    echo ""
    log_success "Pod termination completed. Kubernetes automatically recreated a healthy replica."
}

cmd_cpu_stress() {
    banner
    log_warn "Experiment #02: CPU Stress & Horizontal Pod Autoscaler (HPA)"
    DURATION="${1:-15}"
    CONCURRENCY="${2:-5}"

    log_info "Injecting intensive CPU calculation on ${API_URL}/chaos/cpu-stress"
    log_info "Running with ${CONCURRENCY} parallel workers for ${DURATION}s..."

    for i in $(seq 1 "${CONCURRENCY}"); do
        (
            curl -s -X POST "${API_URL}/chaos/cpu-stress?duration_seconds=${DURATION}" > /dev/null &
        )
    done

    log_info "Workload generated. Monitoring HPA metrics (press Ctrl+C to stop)..."
    if command -v kubectl &> /dev/null; then
        for _ in $(seq 1 6); do
            kubectl get hpa localsre-api-hpa -n "${NAMESPACE}" || true
            sleep 3
        done
    fi
    log_success "CPU stress experiment complete."
}

cmd_error_spike() {
    banner
    log_warn "Experiment #03: HTTP 500 Error Spike & Prometheus Alerting"
    REQUESTS="${1:-100}"

    log_info "Dispatching ${REQUESTS} simulated error requests to ${API_URL}/chaos/error-spike..."
    SUCCESS_COUNT=0
    ERROR_COUNT=0

    for i in $(seq 1 "${REQUESTS}"); do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/chaos/error-spike?error_rate=1.0" || echo "000")
        if [ "$STATUS" == "500" ]; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
        else
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
        echo -n "."
    done
    echo ""

    log_info "Requests dispatched: ${REQUESTS} (Errors 500: ${ERROR_COUNT}, Other: ${SUCCESS_COUNT})"
    log_info "Check Grafana 'Error Rate' panel and Prometheus Alert 'HighHttp5xxErrorRate'."
}

cmd_partition_db() {
    banner
    log_warn "Experiment #04: Dependency Degradation & Service Decoupling"
    DURATION="${1:-20}"

    log_info "Sending chaos command to set pod UNREADY for ${DURATION} seconds..."
    curl -s -X POST "${API_URL}/chaos/unready?duration_seconds=${DURATION}" || true
    echo ""

    log_info "Verifying probe response (/readyz should be 503):"
    curl -s -w "\nHTTP Status: %{http_code}\n" "${API_URL}/readyz" || true

    log_info "Service Endpoints in Kubernetes:"
    if command -v kubectl &> /dev/null; then
        kubectl get endpoints localsre-api -n "${NAMESPACE}" || true
    fi

    log_success "Notice that Kubernetes traffic stops routing to this pod while it is unready."
}

# Entrypoint routing
COMMAND="${1:-help}"

case "${COMMAND}" in
    kill-api|kill-pod)
        cmd_kill_api
        ;;
    cpu-stress)
        cmd_cpu_stress "${2:-15}" "${3:-5}"
        ;;
    error-spike)
        cmd_error_spike "${2:-100}"
        ;;
    partition-db|unready)
        cmd_partition_db "${2:-20}"
        ;;
    status)
        cmd_status
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: ${COMMAND}"
        usage
        exit 1
        ;;
esac
