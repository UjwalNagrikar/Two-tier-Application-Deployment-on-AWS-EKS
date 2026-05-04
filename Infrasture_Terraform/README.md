# Multi-Region DevSecOps Deployment — Terraform IaC on GCP

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-623CE4?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)
[![GCP](https://img.shields.io/badge/GCP-Multi--Region-4285F4?style=for-the-badge&logo=googlecloud&logoColor=white)](https://cloud.google.com)
[![Cloud Armor](https://img.shields.io/badge/Cloud%20Armor-WAF-34A853?style=for-the-badge&logo=google&logoColor=white)](https://cloud.google.com/armor)

Scales the DevSecOps platform from a single GCP VM to a **globally distributed, auto-scaling, zero-downtime** deployment across 3 continents — fully managed by Terraform and driven by the Jenkins pipeline.

---

## Architecture

```
                        ┌──────────────────────────────────┐
                        │   Global Anycast IP (Cloud LB)   │
                        │      + Cloud Armor WAF           │
                        │      + Managed SSL Cert          │
                        └──────────────┬───────────────────┘
                                       │ geo-routing
               ┌───────────────────────┼───────────────────────┐
               ▼                       ▼                       ▼
    ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
    │  us-central1     │   │  europe-west1    │   │ asia-southeast1  │
    │  (Iowa)          │   │  (Belgium)       │   │  (Singapore)     │
    │                  │   │                  │   │                  │
    │  Regional MIG    │   │  Regional MIG    │   │  Regional MIG    │
    │  1–5 instances   │   │  1–5 instances   │   │  1–5 instances   │
    │  Autoscaler      │   │  Autoscaler      │   │  Autoscaler      │
    │  Cloud NAT       │   │  Cloud NAT       │   │  Cloud NAT       │
    └──────────────────┘   └──────────────────┘   └──────────────────┘
               │                       │                       │
               └───────────────────────┴───────────────────────┘
                                  Global VPC
```

## File Structure

```
terraform-multi-region/
│
├── main.tf                     # VPC, LB, Cloud Armor, module calls
├── variables.tf                # All input variables
├── outputs.tf                  # LB IP, SSL status, DNS instructions
├── terraform.tfvars.example    # Fill this and rename to terraform.tfvars
├── Jenkinsfile.multiregion     # Full CI/CD pipeline (security + deploy)
│
└── modules/
    └── regional-mig/           # Reusable regional module
        ├── main.tf             # Subnet, NAT, SA, template, MIG, autoscaler
        ├── variables.tf
        └── outputs.tf
```

## What Gets Created

| Resource | Count | Purpose |
|---|---|---|
| Global VPC | 1 | Unified network across all regions |
| Regional Subnets | 3 | Isolated CIDR per region |
| Cloud NAT | 3 | Outbound internet for Docker pulls |
| GCE Instance Templates | 3 | Immutable launch configs with startup script |
| Regional MIGs | 3 | Self-healing, rolling-update instance groups |
| Regional Autoscalers | 3 | CPU + request-rate based scaling (1–5 instances) |
| Global HTTP(S) LB | 1 | Geo-aware traffic distribution |
| Cloud Armor Policy | 1 | WAF: XSS, SQLi, LFI blocking + rate limiting |
| Managed SSL Certificate | 1 | Auto-provisioned TLS (no Certbot needed) |
| Global Static IP | 1 | Your DNS A record target |
| Service Accounts | 3 | Least-privilege IAM per region |
| Firewall Rules | 3 | Health-check, SSH, app port |

---

## Prerequisites

### 1 — Enable GCP APIs
```bash
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com
```

### 2 — Create Artifact Registry Repository
```bash
gcloud artifacts repositories create devsecops-repo \
  --repository-format=docker \
  --location=us-central1 \
  --description="DevSecOps Docker images"
```

### 3 — Create Terraform Service Account
```bash
# Create SA
gcloud iam service-accounts create terraform-sa \
  --display-name "Terraform Deployer"

# Grant required roles
SA="terraform-sa@YOUR_PROJECT.iam.gserviceaccount.com"

for role in \
  roles/compute.admin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/resourcemanager.projectIamAdmin \
  roles/artifactregistry.admin; do
  gcloud projects add-iam-policy-binding YOUR_PROJECT \
    --member="serviceAccount:${SA}" \
    --role="${role}"
done

# Download key (add to Jenkins as 'gcp-sa-key' credential)
gcloud iam service-accounts keys create sa-key.json \
  --iam-account="${SA}"
```

### 4 — Add Jenkins Credentials
In Jenkins → Manage Credentials → Add:
- **Kind**: Secret file
- **ID**: `gcp-sa-key`
- **File**: Upload the `sa-key.json` downloaded above

### 5 — Install Terraform on Jenkins Server
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor \
  | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform -y
terraform -version
```

---

## Deployment Steps

### Step 1 — Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID, domain, and image URI
```

### Step 2 — Initialize Terraform
```bash
terraform init
```

### Step 3 — Preview Changes
```bash
terraform plan -out=tfplan
```

### Step 4 — Apply (first deploy)
```bash
terraform apply tfplan
```
> Takes ~5–8 minutes. Instances start, Docker pulls image, MIGs register with LB.

### Step 5 — Configure DNS
```bash
terraform output dns_instructions
# Add the A record shown to your DNS provider
```

### Step 6 — Subsequent Deploys (via Jenkins)
Push to `main` branch → Jenkins runs all security stages → builds & pushes image → `terraform apply` with the new image tag → zero-downtime rolling update across all 3 regions.

---

## Autoscaling Behaviour

Each region scales **independently** based on:
- **CPU utilization** target: 70%
- **LB request rate** target: 80%
- **Min replicas**: 1 (cost control)
- **Max replicas**: 5 per region (15 total globally)
- **Cooldown**: 90 seconds between scale events

---

## Rolling Updates (Zero Downtime)

The `update_policy` in the MIG uses:
```hcl
type              = "PROACTIVE"
minimal_action    = "REPLACE"
max_surge_fixed   = 2      # Spin up 2 new before killing old
max_unavailable   = 0      # Never go below current capacity
```
Every `terraform apply` with a new image tag creates a new instance template, and the MIG rolls it out one batch at a time without downtime.

---

## Security Controls

| Layer | Tool | What It Does |
|---|---|---|
| Code | SonarQube | SAST, code smells, security hotspots |
| Dependencies | OWASP DC | CVE scan on all libraries |
| Filesystem | Trivy | OS + config vulnerabilities |
| Container image | Trivy | Image layer vulnerability scan |
| Network | Cloud Armor | WAF (XSS, SQLi, LFI) + rate limiting |
| TLS | Managed SSL | Auto-provisioned, auto-renewed certificate |
| IAM | Service Accounts | Least-privilege per region, no SSH keys |
| Compute | Shielded VMs | Secure Boot + vTPM + Integrity Monitoring |

---

## Cost Estimate (prod defaults)

| Resource | Cost/month (approx) |
|---|---|
| 3× e2-medium (min 1 each) | ~$45 |
| Global HTTP(S) LB | ~$18 |
| Cloud Armor (WAF rules) | ~$5 + $0.75/M requests |
| Artifact Registry | ~$0.10/GB stored |
| **Total at min scale** | **~$70/month** |

Scale to 5 instances/region (15 total): ~$195/month.

---

## Useful Commands

```bash
# See all outputs (LB IP, SSL status, DNS instructions)
terraform output

# Destroy everything (⚠️ irreversible)
terraform destroy

# Target one region only
terraform apply -target=module.region_us

# Force rolling update (e.g. after external image push)
terraform taint module.region_us.google_compute_instance_template.app
terraform apply

# Check MIG status in GCP console
gcloud compute instance-groups managed list
```

---

## Author

**Ujwal Nagrikar** — DevOps & Cloud Engineering  
G. H. Raisoni College of Engineering & Management, Nagpur
