# Global Video Reliability Platform — EKS + Observability + RDS

## Project Overview

This project demonstrates a **production-style SRE workflow** for a video background-processing pipeline deployed on AWS EKS and instrumented with Prometheus + Grafana.

The focus is not on "running services" — it's on **proving the system is observable, alertable, and behaves correctly under load.** Every component was validated end-to-end: from infrastructure provisioning through job processing to alert firing under real traffic spikes.

**Pipeline:** Upload Service (FastAPI) → Redis Queue → Worker Service → Prometheus Metrics → Grafana Dashboards + Alerts

---

## Architecture

![Architecture](screenshots/v2-architecture-eks-observability-rds.png)

**Infrastructure (Terraform-provisioned):**
- VPC with public/private subnets, NAT gateway, and Internet Gateway
- EKS cluster with managed node group in private subnets
- ECR repositories for container images
- RDS PostgreSQL in private subnets (provisioned for future integration)

**Kubernetes Workloads:**
- **Namespace: `app`** — upload-service, worker-service, Redis
- **Namespace: `monitoring`** — kube-prometheus-stack (Prometheus, Grafana, Alertmanager)

**Observability:**
- ServiceMonitor-based automatic scraping (no annotation hacks)
- Custom Grafana dashboard with upload volume, worker throughput, and active job tracking
- Alert rules for processing stalls and traffic spikes (4× and 5×)

---

## Design Decisions & Tradeoffs

**Redis over SQS for the queue** — I chose Redis because it keeps the queue layer in-cluster with zero AWS coupling, making the app portable and simpler to debug locally. In production, SQS or a managed Redis (ElastiCache) would be the right call for durability and scaling, but for this project the priority was demonstrating the observability workflow, not queue durability.

**Single NAT gateway instead of one per AZ** — This is a cost optimization for a dev environment. In production, I'd deploy one NAT per AZ to avoid cross-AZ traffic charges and eliminate a single point of failure for private subnet egress.

**RDS provisioned but not wired to the app** — I scoped this project to focus deeply on the observability pipeline (metrics → dashboards → alerts → validation under load). RDS is provisioned and secrets are created in Kubernetes to show the infrastructure is ready, but I deliberately deprioritized the database integration to go deeper on alerting and load testing. Wiring RDS for job persistence is the natural next step.

**Single replicas for all services** — This is a demo-scoped decision to keep costs down. In production, upload-service would run 2+ replicas behind an Ingress, and workers would autoscale using KEDA based on Redis queue depth.

**Grafana-managed alerts instead of PrometheusRule CRDs** — I used Grafana alerting because it allows faster iteration on alert thresholds through the UI during development. For a production setup, I'd codify alerts as PrometheusRule CRDs in version control for GitOps compatibility.

---

## Tech Stack

- **AWS**: EKS, ECR, RDS (PostgreSQL), VPC/IAM via Terraform
- **Terraform**: infrastructure provisioning (VPC, EKS, RDS, IAM)
- **Kubernetes + Helm**: workload deployments and monitoring stack
- **Python (FastAPI)**: upload-service (accepts jobs, enqueues to Redis, exposes metrics)
- **Python Worker**: background processor (dequeues, processes, exposes metrics)
- **Redis**: in-cluster queue backend
- **Prometheus Operator (kube-prometheus-stack)**: metrics scraping via ServiceMonitors
- **Grafana**: dashboards + alert rules

---

## Deployment & Validation

### Phase 1 — Infrastructure Provisioning

EKS cluster provisioned via Terraform with 2 worker nodes in private subnets. Namespaces created for workload isolation: `app` for services, `monitoring` for the observability stack.

![EKS Nodes Ready](screenshots/v2-01-eks-nodes-ready.png)
![Namespaces](screenshots/v2-02-namespaces.png)

---

### Phase 2 — Monitoring Stack Deployment

Deployed kube-prometheus-stack via Helm into the `monitoring` namespace. Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporters all running and healthy.

![Monitoring Pods Running](screenshots/v2-03-monitoring-pods-running.png)
![Grafana UI](screenshots/v2-04-grafana-ui.png)

---

### Phase 3 — Application Deployment

Redis deployed as the in-cluster queue. Application config loaded via ConfigMap, RDS credentials stored as a Kubernetes Secret. Container images built and pushed to ECR, then deployed to the `app` namespace.

![Redis Running](screenshots/v2-05-app-redis-running.png)
![App ConfigMap](screenshots/v2-06-app-configmap.png)
![DB Secret](screenshots/v2-07-db-secret-created.png)
![ECR Repos Created](screenshots/v2-08-ecr-repos-created.png)
![ECR Login](screenshots/v2-09-ecr-login-succeeded.png)
![Services Copied](screenshots/v2-10-services-copied.png)
![Upload Image Pushed](screenshots/v2-11-upload-image-pushed.png)
![Worker Image Pushed](screenshots/v2-12-worker-image-pushed.png)

---

### Phase 4 — Service Validation

All application pods running in the `app` namespace. Services and endpoints verified for internal connectivity — upload-service, worker-service, and Redis all reachable via ClusterIP.

![App Pods Running](screenshots/v2-13-app-pods-running.png)
![Services and Endpoints](screenshots/v2-14-app-services-endpoints.png)

---

### Phase 5 — End-to-End Pipeline Proof

This is the key validation. I sent a job request to upload-service, confirmed it was accepted and enqueued (queue depth increased), verified the worker picked it up and processed it successfully, and confirmed the metrics endpoint was updating. This proves the full pipeline works: **request → queue → worker → metrics**.

![End-to-End Proof](screenshots/v2-15-end-to-end-proof.png)

---

### Phase 6 — Observability Validation

Prometheus is scraping both application endpoints via ServiceMonitors (targets show UP). Key application metrics confirmed in Prometheus: `upload_requests_total`, `jobs_processed_total`, `worker_active_jobs`. Grafana's Prometheus datasource verified and working.

![Prometheus Targets App Scrape](screenshots/v2-16-prometheus-targets-app-scrape.png)
![Prometheus App Metrics Query](screenshots/v2-17-prometheus-app-metrics-query.png)
![ServiceMonitor Targets](screenshots/v2-19-prometheus-targets-app-servicemonitors.png)
![Grafana Prometheus Datasource](screenshots/v2-20-grafana-prometheus-datasource.png)

---

### Phase 7 — Dashboards & Alerting

**Custom application dashboard** built with three panels focused on SRE signals: upload request volume, worker processing throughput, and worker active job count.

![Grafana K8s Namespace Pods Dashboard](screenshots/v2-21-grafana-k8s-namespace-pods-dashboard.png)
![Grafana App Dashboard](screenshots/v2-22-grafana-app-dashboard.png)

**Worker stall alert** — Configured to fire when `worker_active_jobs` drops below 1 while the queue has pending work. This detects the failure mode where a worker pod is running but not processing. Validated by capturing the FIRING state.

![Stall Alert Firing](screenshots/v2-23-alert-firing.png)

---

### Phase 8 — Load Testing & Spike Alerts

I captured the system's behavior across three states to prove observability under real conditions:

**Baseline (before load)** — System stable, flat metrics, no alerts firing.

![Before Load](screenshots/v2-24-grafana-before-load.png)

**During load spike** — Generated burst traffic. Upload request rate spiked from ~2 to ~20 req/min, worker throughput increased proportionally, active jobs rose as the worker processed the backlog.

![During Load](screenshots/v2-25-grafana-during-load.png)

**Recovery (after load)** — Traffic stopped. System returned to steady state — worker drained the queue and metrics settled. This confirms the system recovers cleanly from burst traffic without manual intervention.

![After Load](screenshots/v2-26-grafana-after-load.png)

**4× spike alert** — Fires when `60 * rate(upload_requests_total[2m])` exceeds 80 (4× the baseline of ~20 req/min). Validated with FIRING state.

![4x Spike Alert Firing](screenshots/v2-27-alert-4x-spike-FIRING.png)

**5× spike alert** — Fires when the same rate exceeds 100. Validated with FIRING state at 228 req/min.

![5x Spike Alert Firing](screenshots/v2-28-alert-5x-spike-firing.png)

**Alert rules summary** — All custom alert rules visible under the `sre-eval` folder.

![Alert Rules List](screenshots/v2-29-alert-rules-my-rules.png)

---

## Production Considerations

If I were taking this to production, here's what I'd prioritize:

- **Health/readiness probes** — Upload-service already exposes `/health`; I'd wire this as a readiness probe and add a TCP probe on the worker's metrics port to enable proper pod lifecycle management.
- **Dependency pinning** — I'd pin all Python packages to exact versions and use a lockfile to guarantee reproducible builds across environments.
- **Terraform remote state** — I'd add an S3 + DynamoDB backend for state locking, enabling safe collaboration and CI/CD-driven infrastructure changes.
- **Worker graceful shutdown** — I'd implement a processing list pattern in Redis (move jobs to an in-progress list, remove on completion) so interrupted jobs are automatically retried instead of lost.
- **CI/CD pipeline** — I'd add GitHub Actions to automate image builds, ECR pushes, and Kubernetes deployments on every merge to main.
- **Smarter stall detection** — The current alert fires on `worker_active_jobs < 1`, which triggers during legitimate idle periods. I'd refine this to correlate queue depth with worker activity, so it only fires when there's pending work and no processing.

---

## Future Scope

- **RDS integration** — Wire upload-service and worker-service to PostgreSQL to persist job status, processing history, and failure records. The infrastructure and secrets are already in place.
- **Worker autoscaling with KEDA** — Add KEDA ScaledObject targeting Redis list length (`video_jobs`) so workers scale proportionally to queue backpressure. This directly addresses the "stall under load" problem the alerts detect.
- **Ingress + TLS** — Add an AWS ALB Ingress Controller with ACM certificate for a production-grade endpoint instead of port-forwarding.
- **SLOs and burn-rate alerting** — Define SLOs (e.g., 99.5% of jobs processed within 30s) and implement multi-window burn-rate alerts instead of static thresholds.
- **Distributed tracing (OpenTelemetry)** — Add trace context propagation from upload-service through Redis to worker-service to enable end-to-end request tracing in Grafana Tempo.
