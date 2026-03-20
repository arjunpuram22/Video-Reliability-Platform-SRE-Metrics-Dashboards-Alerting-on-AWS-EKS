# Global Video Reliability Platform - EKS + Observability + RDS (Terraform)

## 1) Project Overview

This project demonstrates a production-style reliability workflow for a simplified video background-processing pipeline deployed on **AWS EKS** and instrumented with **Prometheus + Grafana**.

Instead of focusing only on “running services,” the emphasis is on **SRE-style validation**:
- confirming the system is healthy (pods/services)
- proving end-to-end job processing works
- scraping and querying metrics
- visualizing behavior in Grafana dashboards
- triggering alerts for abnormal conditions (stall + traffic spikes)

---

## 2) Problem Statement

Large-scale video platforms (uploads, transcodes, metadata extraction) rely heavily on **asynchronous background jobs**. Under traffic spikes:
- queues can grow fast
- workers can stall or fall behind
- failures may not be visible without observability

This project shows how to:
- run the workload on Kubernetes (EKS)
- expose application metrics
- scrape metrics automatically (ServiceMonitor)
- build dashboards for visibility
- configure alert rules based on real traffic patterns

---

## 3) Architecture

![Architecture](screenshots/v2-architecture-eks-observability-rds.png)

Key components:
- **Terraform (IaC)**: provisions AWS infrastructure
- **EKS Cluster**: runs application + monitoring namespaces
- **ECR**: stores container images for workloads
- **RDS PostgreSQL**: provisioned database (marked as future integration in the architecture)
- **Namespace: app**: upload-service, worker-service, redis
- **Namespace: monitoring**: kube-prometheus-stack (Prometheus + Grafana)
- **Grafana Alerting**: rules for stall + spike detection

---

## 4) Tech Stack

- **AWS**: EKS, ECR, RDS (PostgreSQL), VPC/IAM via Terraform  
- **Terraform**: infrastructure provisioning  
- **Kubernetes + Helm**: deployments and monitoring stack  
- **Python (FastAPI)**: upload-service  
- **Python Worker**: background processor  
- **Redis**: queue backend  
- **Prometheus Operator (kube-prometheus-stack)**: metrics scraping + ServiceMonitors  
- **Grafana**: dashboards + alert rules  

---

## 5) Deployment + Validation Steps (with Evidence)

> Each step below includes a short explanation and a screenshot as proof.

---

### Step 1 - EKS Cluster is Ready (Nodes Online)

First, I verified the EKS cluster was provisioned successfully and worker nodes joined the cluster.

![EKS Nodes Ready](screenshots/v2-01-eks-nodes-ready.png)

---

### Step 2 - Kubernetes Namespaces Created

I separated workloads into two namespaces to keep production services and monitoring cleanly isolated:
- `app` for application components
- `monitoring` for observability stack

![Namespaces](screenshots/v2-02-namespaces.png)

---

### Step 3 - Monitoring Stack Running (kube-prometheus-stack)

I deployed the Prometheus Operator stack using Helm and confirmed core monitoring components are healthy (Prometheus, Grafana, Alertmanager).

![Monitoring Pods Running](screenshots/v2-03-monitoring-pods-running.png)

---

### Step 4 - Grafana Accessible

Grafana was exposed locally using port-forward and verified via UI access.

![Grafana UI](screenshots/v2-04-grafana-ui.png)

---

### Step 5 - Redis Queue Running in `app` Namespace

Redis acts as the in-cluster queue backend for job buffering and decoupled processing.

![Redis Running](screenshots/v2-05-app-redis-running.png)

---

### Step 6 - Application Config Loaded (ConfigMap)

I created a ConfigMap to store application-level settings (ports, service names, metrics paths) used by the Kubernetes manifests.

![App ConfigMap](screenshots/v2-06-app-configmap.png)

---

### Step 7 - Database Secret Created (RDS Credentials)

RDS PostgreSQL is provisioned via Terraform. I created a Kubernetes Secret in the `app` namespace to store DB credentials for future integration.

![DB Secret](screenshots/v2-07-db-secret-created.png)

---

### Step 8 - ECR Repositories Created

I created separate ECR repositories to store container images for the upload and worker services.

![ECR Repos Created](screenshots/v2-08-ecr-repos-created.png)

---

### Step 9 - ECR Login Succeeded

I authenticated Docker to ECR to enable secure pushes of application container images.

![ECR Login](screenshots/v2-09-ecr-login-succeeded.png)

---

### Step 10 - Services Copied into V2 Repo (K8s + ECR Ready)

I prepared the codebase structure for Kubernetes deployment by organizing service folders for image build/push and manifests.

![Services Copied](screenshots/v2-10-services-copied.png)

---

### Step 11 - Upload Service Image Pushed to ECR

The upload-service image was built and pushed to ECR (linux/amd64), ready for EKS nodes to pull and run.

![Upload Image Pushed](screenshots/v2-11-upload-image-pushed.png)

---

### Step 12 - Worker Service Image Pushed to ECR

The worker-service image was built and pushed to ECR (linux/amd64), ready for EKS nodes to pull and run.

![Worker Image Pushed](screenshots/v2-12-worker-image-pushed.png)

---

### Step 13 - Application Pods Running (Upload + Worker + Redis)

After deploying manifests, I validated that all application pods are running and healthy inside the `app` namespace.

![App Pods Running](screenshots/v2-13-app-pods-running.png)

---

### Step 14 - Services and Endpoints Verified

I confirmed Kubernetes Services and Endpoints are correctly wired for internal service discovery:
- upload-service reachable via ClusterIP
- worker-service reachable for metrics scraping
- redis reachable for queue operations

![Services and Endpoints](screenshots/v2-14-app-services-endpoints.png)

---

### Step 15 - End-to-End Proof (Request → Queue → Worker → Metrics)

I validated the full pipeline end-to-end:
- sent a job request to upload-service
- job was accepted (queue depth increased)
- worker processed the job successfully
- metrics endpoint was reachable

![End-to-End Proof](screenshots/v2-15-end-to-end-proof.png)

---

### Step 16 - Prometheus Scraping Confirmed (Targets Up)

I verified Prometheus is scraping the application endpoints successfully (targets are UP).

![Prometheus Targets App Scrape](screenshots/v2-16-prometheus-targets-app-scrape.png)

---

### Step 17 - Prometheus App Metric Queries Verified

I queried key application metrics directly in Prometheus to confirm that metrics are collected and updating:
- `upload_requests_total`
- `jobs_processed_total`
- `worker_active_jobs`

![Prometheus App Metrics Query](screenshots/v2-17-prometheus-app-metrics-query.png)

---

### Step 18 - ServiceMonitor Targets Visible (Prometheus Operator)

I validated Prometheus Operator discovery by confirming ServiceMonitor-based targets exist for both services.

![ServiceMonitor Targets](screenshots/v2-19-prometheus-targets-app-servicemonitors.png)

---

### Step 19 - Grafana Prometheus Datasource Working

Grafana’s Prometheus datasource was tested successfully and confirmed it can query the Prometheus API.

![Grafana Prometheus Datasource](screenshots/v2-20-grafana-prometheus-datasource.png)

---

### Step 20 - Kubernetes Namespace Dashboard (Visibility Into Pods)

I used the built-in Kubernetes dashboards to confirm Grafana can visualize workload and resource behavior for the `app` namespace.

![Grafana K8s Namespace Pods Dashboard](screenshots/v2-21-grafana-k8s-namespace-pods-dashboard.png)

---

### Step 21 - Custom Application Dashboard Created

I created a clean app dashboard focused on SRE signals:
- Upload request volume
- Worker processing throughput
- Worker active job behavior

![Grafana App Dashboard](screenshots/v2-22-grafana-app-dashboard.png)

---

### Step 22 - Worker Processing Stall Alert (FIRING Proof)

I configured a reliability alert to detect processing stalls and captured the FIRING state as validation.

![Stall Alert Firing](screenshots/v2-23-alert-firing.png)

---

### Step 23 - Baseline System State (Before Load)

Before triggering traffic, I captured baseline behavior in Grafana to show the system is stable under no/low load.

![Before Load](screenshots/v2-24-grafana-before-load.png)

---

### Step 24 - Metrics During Load Spike

I generated traffic and observed the metrics increase in Grafana (workload spike visibility).

![During Load](screenshots/v2-25-grafana-during-load.png)

---

### Step 25 - Recovery After Load

After the spike ended, I observed the system returning to steady state, confirming recovery behavior.

![After Load](screenshots/v2-26-grafana-after-load.png)

---

### Step 26 - 4x Spike Alert (FIRING Proof)

I implemented a spike-based alert using a real traffic baseline and validated that it fires when request rate crosses the 4× threshold.

![4x Spike Alert Firing](screenshots/v2-27-alert-4x-spike-FIRING.png)

---

### Step 27 - 5x Spike Alert (FIRING Proof)

I created a stricter 5× spike alert to detect larger bursts and validated the FIRING state.

![5x Spike Alert Firing](screenshots/v2-28-alert-5x-spike-firing.png)

---

### Step 28 - Alert Rules Summary (All Custom Rules)

Finally, I captured the alert list filtered to my rules to show the final alerting coverage in one view.

![Alert Rules List](screenshots/v2-29-alert-rules-my-rules.png)

---

## Key Takeaways

- Provisioned a production-style setup using **Terraform + AWS (EKS, ECR, RDS PostgreSQL)**.
- Deployed an **async job pipeline** on Kubernetes: Upload → Redis queue → Worker.
- Enabled **automatic metrics scraping** using Prometheus Operator **ServiceMonitors**.
- Built Grafana dashboards to validate **baseline → spike → recovery** behavior.
- Implemented and validated alert rules for **processing stalls** and **traffic spikes (4× / 5×)**.

---

## Future Scope (Short)

- Wire the app to **RDS PostgreSQL** to persist job status/history.
- Add **autoscaling** (HPA/KEDA) for workers based on load/queue depth.
- Add **Ingress + TLS** for a real endpoint and production-style routing.
- Introduce **SLOs / error budgets** and more advanced alerting (burn-rate).
- Add **tracing (OpenTelemetry)** and basic **CI/CD** for ECR + deploy.
