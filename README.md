<div align="center">

# 🔥 LocalSRE Lab

**Laboratorio personal de Site Reliability Engineering diseñado para practicar y demostrar conceptos de infraestructura, observabilidad, automatización, Kubernetes y resiliencia en un entorno 100% local.**

[![Status](https://img.shields.io/badge/Status-🟢_Operational-success)](#)
[![CI Pipeline](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?logo=github-actions&logoColor=white)](#-cicd-pipeline)
[![Kubernetes](https://img.shields.io/badge/Orchestration-Kubernetes_v1.30+-326CE5?logo=kubernetes&logoColor=white)](#-kubernetes-architecture)
[![Prometheus](https://img.shields.io/badge/Metrics-Prometheus-E6522C?logo=prometheus&logoColor=white)](#-observability--telemetry)
[![Grafana](https://img.shields.io/badge/Dashboard-Grafana_v11-F46800?logo=grafana&logoColor=white)](#-grafana-dashboards)
[![Chaos](https://img.shields.io/badge/Resilience-Chaos_Testing-black?logo=target)](#-chaos-engineering)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

*Python • Docker • Kubernetes • Prometheus • Grafana • Loki • GitHub Actions • Ansible*  
*Zero Cloud Bills. 100% Reproducible on your local workstation.*

</div>

---

## 🧭 ¿Qué es LocalSRE Lab?

**LocalSRE Lab** es un entorno práctico y reproducible de ingeniería de fiabilidad de sitios (SRE) montado íntegramente en local, sin dependencias de nubes públicas de pago (AWS/GCP/Azure).

El objetivo del proyecto no es construir una aplicación web compleja, sino **demostrar dominio real de los pilares fundamentales de la infraestructura moderna y la producción**:
1. **Orquestación en Kubernetes**: Primitivas declarativas de producción (Deployments, StatefulSets con PVC, Services, Ingress, HPA, Probes de ciclo de vida).
2. **Observabilidad Práctica**: Las 4 Señales Doradas (*Golden Signals*: Tráfico, Latencia, Errores y Saturación) instrumentadas con Prometheus y Grafana, más logs centralizados estructurados con Loki.
3. **Ingeniería del Caos (Chaos Engineering)**: Automatización de fallos inyectados intencionalmente para validar autorrecuperación (*self-healing*), escalado automático y desacoplamiento de dependencias caídas.
4. **Automatización de Sistemas**: Aprovisionamiento de nodos Linux con Ansible y despliegue local opcional con Docker Compose.
5. **Calidad y Seguridad CI/CD**: Pipelines de GitHub Actions con pruebas automáticas, escaneo de vulnerabilidades CVE con Trivy y validación client-side de esquemas de Kubernetes.

---

## 🏗️ Arquitectura del Sistema

```
                    ┌──────────────┐
                    │    NGINX     │
                    │   Ingress    │
                    └──────┬───────┘
                           │ (HTTP: localsre.local)
                    ┌──────▼───────┐
                    │  Kubernetes  │
                    │  Namespace:  │
                    │   localsre   │
                    │              │
                    │ ┌──────────┐ │
                    │ │ API x3   │◄┼─────── Horizontal Pod Autoscaler (HPA)
                    │ └──────────┘ │        (Escala: 3 -> 10 según CPU/RAM)
                    │ ┌──────────┐ │
                    │ │ Worker   │ │
                    │ └──────────┘ │
                    └──────┬───────┘
                           │
                 ┌─────────┴─────────┐
                 ▼                   ▼
          ┌─────────────┐     ┌─────────────┐
          │ PostgreSQL  │     │ Redis Cache │
          │(StatefulSet)│     │(Deployment) │
          └─────────────┘     └─────────────┘

    ==================== OBSERVABILIDAD ====================
     Prometheus (Scrapes /metrics) ──► Alertas (5xx, Latencia)
     Grafana (Dashboard RED Metrics & Golden Signals)
     Loki + Promtail (Logs Centralizados en JSON Estructurado)
    =======================================================
```

---

## 🧰 Stack Tecnológico

| Dominio | Tecnología | Propósito |
|---|---|---|
| **Contenedores** | Docker, Docker Compose | Imágenes multi-stage no-root, entorno local completo |
| **Orquestación** | Kubernetes (Docker Desktop / Minikube / Kind) | ReplicaSets, Deployments, StatefulSet, HPA, Probes, Ingress |
| **Backend** | Python 3.12, FastAPI, SQLAlchemy | API asíncrona, RED metrics, endpoints de inyección de caos |
| **Bases de Datos** | PostgreSQL 16, Redis 7 | Persistencia relacional con volúmenes dedicados y caché en memoria |
| **Métricas y Alertas** | Prometheus | Scrapes cada 5s y reglas de alerta para SLOs de error y latencia |
| **Visualización** | Grafana 11 | Dashboard con Golden Signals (Tráfico, Errores, Latencia, Saturación) |
| **Logs** | Loki + Promtail | Ingestión centralizada de logs en formato JSON estructurado |
| **Chaos Testing** | Bash (`chaos.sh`) & PowerShell (`chaos.ps1`) | Simulación automatizada de caídas de pods, estrés de CPU y errores |
| **Automatización** | Ansible | Playbooks de hardening de SO Linux, Docker CE y Node Exporter |
| **CI/CD** | GitHub Actions | Linting con Flake8, Pytest, Docker Buildx y Trivy Security Scan |

---

## 🚀 Guía de Despliegue y Checklist de Validación

El laboratorio permite dos modalidades de ejecución:

### Opción 1: Kubernetes Nativo (Recomendado para SRE & Chaos)

#### 1. Requisitos
- Docker Desktop con **Kubernetes activado** (Settings > Kubernetes > Enable Kubernetes), o un clúster local como **Minikube** o **Kind**.
- `kubectl` configurado en el path.

#### 2. Compilación de la imagen local
```bash
docker build -f docker/Dockerfile -t localsre-api:latest .
```

#### 3. Despliegue declarativo con Kustomize
```bash
kubectl apply -k k8s/
```

#### 4. Validación del estado del clúster
```bash
kubectl get pods -n localsre -o wide
kubectl get svc -n localsre
kubectl get hpa -n localsre
```
Salida esperada:
```
NAME                            READY   STATUS    RESTARTS   AGE
localsre-api-5c7475f464-4m2pl   1/1     Running   0          40s
localsre-api-5c7475f464-9k8xq   1/1     Running   0          40s
localsre-api-5c7475f464-txlw7   1/1     Running   0          40s
postgres-0                      1/1     Running   0          45s
redis-7669d5877f-nb5j4          1/1     Running   0          45s
```

#### 5. Acceso a los servicios
```bash
kubectl port-forward svc/localsre-api -n localsre 8000:80
```
- Swagger Docs: [http://localhost:8000/docs](http://localhost:8000/docs)
- Métricas Prometheus: [http://localhost:8000/metrics](http://localhost:8000/metrics)
- Liveness: [http://localhost:8000/healthz](http://localhost:8000/healthz)
- Readiness: [http://localhost:8000/readyz](http://localhost:8000/readyz)

---

### Opción 2: Docker Compose (Despliegue Rápido de Todo el Stack)

Para levantar la API junto con Postgres, Redis, Prometheus, Grafana, Loki y Promtail en un solo comando:

```bash
docker compose config
docker compose up -d --build
docker compose ps
```

Puntos de acceso:
- **API**: [http://localhost:8000/docs](http://localhost:8000/docs)
- **Prometheus**: [http://localhost:9090](http://localhost:9090)
- **Grafana**: [http://localhost:3000](http://localhost:3000) *(User: `admin` / Password: `admin`)*
- **Loki**: [http://localhost:3100](http://localhost:3100)

---

## 💀 Los Experimentos de Caos (Chaos Engineering)

Dispones de la suite de automatización tanto en Bash (`./chaos/chaos.sh`) como en PowerShell nativo (`.\chaos\chaos.ps1`):

### 1. Experimento #01: Self-Healing de Kubernetes (El experimento clave)
Simula la caída repentina de un pod en producción:

```powershell
# En una terminal: observa la reconciliación en tiempo real
kubectl get pods -n localsre -l app.kubernetes.io/name=localsre-api -w

# En otra terminal: ejecuta el kill
.\chaos\chaos.ps1 kill-api
# (o en bash: ./chaos/chaos.sh kill-api)
```

**Flujo observado**:
```
3 réplicas disponibles (3/3)
       ↓
Pod eliminado abruptamente (2/3)
       ↓
ReplicaSet detecta la discrepancia en < 1 segundo
       ↓
Crea un nuevo pod de reemplazo
       ↓
Pasan startupProbe y readinessProbe
       ↓
3 réplicas disponibles (3/3)
```
*Tiempo medio de recuperación: ~5 segundos con 0 peticiones de usuario caídas.*

---

### 2. Experimento #02: Saturación de CPU y Escalado con HPA
Demuestra la elasticidad automática del servicio:

```powershell
# Observa el estado del autoscaler
kubectl get hpa localsre-api-hpa -n localsre -w

# Inyecta carga de cómputo intensivo
.\chaos\chaos.ps1 cpu-stress -Duration 20 -Concurrency 5
```

**Flujo observado**:
```
NAME               MINPODS   MAXPODS   REPLICAS
localsre-api-hpa   3         10        3
       ↓ (CPU supera umbral del 60%)
localsre-api-hpa   3         10        5
       ↓ (Pico superado + ventana de estabilización)
localsre-api-hpa   3         10        3
```

---

### 3. Experimento #03: Ola de Errores 500 y Alertado en Grafana/Prometheus
```powershell
.\chaos\chaos.ps1 error-spike -Count 100
```
- Dispara peticiones al endpoint de fallo simulado.
- Provoca la activación de la alerta `HighHttp5xxErrorRate` en Prometheus.
- El panel *Error Rate (5xx %)* en el Dashboard de Grafana sube instantáneamente marcando la anomalía.

---

### 4. Experimento #04: Desacoplamiento de Dependencias (Readiness vs Liveness)
```powershell
.\chaos\chaos.ps1 partition-db -Duration 25
```
- Hace fallar intencionalmente el `/readyz` del pod.
- Comprobación: Kubernetes cambia el pod a `READY 0/1` y **lo saca inmediatamente del Service Endpoint** (`kubectl get endpoints localsre-api -n localsre`).
- El contenedor **no se destruye ni entra en CrashLoopBackOff**, evitando tormentas de reinicios.

> Informes postmortem y fichas completas de cada experimento en [`chaos/experiments/`](chaos/experiments/).

---

## 📊 Dashboard de Observabilidad (Grafana)

El dashboard [`monitoring/grafana/dashboards/localsre-dashboard.json`](monitoring/grafana/dashboards/localsre-dashboard.json) viene pre-provisionado automáticamente con:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        LocalSRE Lab Dashboard                          │
├───────────────────┬───────────────────┬────────────────────────────────┤
│ Request Rate      │ Error Rate (5xx)  │ P95 Latency    │ Healthy Pods  │
│ 145 req/s         │ 0.00 %            │ 38 ms          │ 3 / 3         │
├───────────────────┴───────────────────┴────────────────────────────────┤
│                                                                        │
│                Traffic: Requests by Status Code                        │
│                📈📈📈📈📈📈📈📈📈📈📈📈📈📈                            │
│                                                                        │
├───────────────────────────────────┬────────────────────────────────────┤
│ Latency Percentiles (P50/P90/P99) │ CPU & Memory Saturation            │
│ ▃▄▅▆▇ (P99: 42ms)                 │ Pods al 28% CPU, 110MB RAM         │
├───────────────────────────────────┴────────────────────────────────────┤
│ Centralized Structured Logs (Loki)                                     │
│ [INFO] [pod: localsre-api-4m2pl] GET /items 200 OK (duration: 3.2ms)  │
│ [ERROR][pod: localsre-api-9k8xq] GET /chaos/error-spike 500 (CHAOS)   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Gestión de Secretos y Seguridad

> [!IMPORTANT]
> **Política Zero-Secrets en Git**:
> - Este repositorio **no almacena credenciales reales**.
> - En [`k8s/secret.yaml`](k8s/secret.yaml) se proporcionan exclusivamente valores de plantilla (`change-me-sre-password`).
> - En un entorno productivo real, estos valores se inyectan dinámicamente mediante soluciones como **HashiCorp Vault**, **Sealed Secrets** o **External Secrets Operator**.
> - El archivo `.gitignore` excluye cualquier archivo de entorno `.env`, certificados `*.pem` o ficheros `*.kubeconfig`.

---

## 💡 Preguntas Clave de Entrevistas SRE Demostradas en este Lab

### 1. "¿Por qué utilizaste StatefulSet para PostgreSQL en lugar de un Deployment?"
> *En un Deployment tradicional, los pods son efímeros y no tienen identidad de red persistente ni garantía de orden. Para bases de datos con almacenamiento en disco, un **StatefulSet** garantiza nombres ordinales estables (`postgres-0`), volumen persistente dedicado (`volumeClaimTemplates`) que no se desconecta accidentalmente al reprogramar el pod, y apagados/inicios ordenados para evitar corrupción de datos.*

### 2. "¿Cuál es la diferencia entre LivenessProbe y ReadinessProbe?"
> *Demostrado de forma práctica en el **Experimento #04**:*
> - **LivenessProbe (`/healthz`)**: Comprueba si el proceso está vivo. Si falla, el kubelet **mata y reinicia el contenedor**. Si una base de datos externa se cae y el liveness depende de ella, todos los pods se reiniciarán en bucle (*CrashLoopBackOff*).
> - **ReadinessProbe (`/readyz`)**: Comprueba si el contenedor está listo para recibir tráfico de usuarios (conexión a DB y Redis activa). Si falla, Kubernetes **retira el pod del Endpoints del Service**, evitando que los usuarios reciban errores 500, pero **sin matar el contenedor**, permitiendo que se recupere en cuanto la dependencia vuelva a estar disponible.

### 3. "¿Cómo funciona internamente el Horizontal Pod Autoscaler (HPA)?"
> *Demostrado en el **Experimento #02**: El HPA consulta periódicamente al API de métricas del clúster (`metrics.k8s.io`). Calcula el número de réplicas deseadas con la fórmula estándar:*
> $$\text{desiredReplicas} = \left\lceil \text{currentReplicas} \times \left( \frac{\text{currentMetricValue}}{\text{targetMetricValue}} \right) \right\rceil$$
> *Además, definimos políticas de `behavior` con ventanas de estabilización para evitar el efecto "flapping" o sobreoscilación de réplicas.*

### 4. "¿Por qué no utilizar Terraform para un laboratorio 100% local?"
> *Terraform está diseñado para interactuar con APIs de nubes públicas mediante control de estado. En un entorno 100% local en tu ordenador, simular recursos cloud mediante proveedores ficticios suele ser un artificio poco natural. Utilizar manifiestos nativos de Kubernetes con **Kustomize**, orquestación de contenedores y **Ansible** para configuración de sistemas demuestra un conocimiento genuino y reproducible sin inflar el proyecto artificialmente.*

---

## 📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT. Consulta el archivo [LICENSE](LICENSE) para más detalles.
