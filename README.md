# Two-Tier Flask Application Deployment on AWS EKS

A complete guide to deploying a production-ready Flask + MySQL application on Amazon Elastic Kubernetes Service (EKS).

![Architecture Diagram](https://img.shields.io/badge/AWS-EKS-orange) ![Flask](https://img.shields.io/badge/Flask-2.0.1-green) ![MySQL](https://img.shields.io/badge/MySQL-5.7-blue) ![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-purple)

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Step-by-Step Deployment Guide](#step-by-step-deployment-guide)
- [Accessing the Application](#accessing-the-application)
- [Common Issues & Solutions](#common-issues--solutions)
- [Cleanup](#cleanup)

---

## 🎯 Project Overview

This project demonstrates deploying a **two-tier web application** on AWS EKS:
- **Frontend**: Flask web application with a modern, animated UI
- **Backend**: MySQL database for persistent storage

Users can submit messages through a web interface, which are stored in MySQL and displayed in real-time.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                             │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Amazon EKS Cluster                        │ │
│  │                                                        │ │
│  │  ┌──────────────────────┐  ┌──────────────────────┐  │ │
│  │  │   Load Balancer      │  │   Load Balancer      │  │ │
│  │  │   Service            │  │   (External)         │  │ │
│  │  └──────────┬───────────┘  └──────────┬───────────┘  │ │
│  │             │                          │              │ │
│  │  ┌──────────▼───────────┐  ┌──────────▼───────────┐  │ │
│  │  │  Flask App Pod       │  │  Flask App Pod       │  │ │
│  │  │  (Port 5000)         │  │  (Port 5000)         │  │ │
│  │  │  ┌────────────────┐  │  │  ┌────────────────┐  │  │ │
│  │  │  │ Container      │  │  │  │ Container      │  │  │ │
│  │  │  │ Flask + Python │  │  │  │ Flask + Python │  │  │ │
│  │  │  └────────────────┘  │  │  └────────────────┘  │  │ │
│  │  └──────────┬───────────┘  └──────────┬───────────┘  │ │
│  │             │                          │              │ │
│  │             └──────────┬───────────────┘              │ │
│  │                        │                              │ │
│  │             ┌──────────▼───────────┐                  │ │
│  │             │  ClusterIP Service   │                  │ │
│  │             │  mysql:3306          │                  │ │
│  │             └──────────┬───────────┘                  │ │
│  │                        │                              │ │
│  │             ┌──────────▼───────────┐                  │ │
│  │             │   MySQL Pod          │                  │ │
│  │             │   (Port 3306)        │                  │ │
│  │             │  ┌────────────────┐  │                  │ │
│  │             │  │  MySQL 5.7     │  │                  │ │
│  │             │  │  Database      │  │                  │ │
│  │             │  └────────────────┘  │                  │ │
│  │             └──────────────────────┘                  │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
└───────────────────────────────────────────────────────────────┘

Internet → Load Balancer → Flask Pods → MySQL Pod
```

### Components:
- **EKS Cluster**: Managed Kubernetes cluster on AWS
- **Flask Application**: Multiple replicas for high availability
- **MySQL Database**: Single pod with persistent storage
- **Load Balancer**: AWS ELB for external access
- **ConfigMaps & Secrets**: Configuration and credential management

---

## 🛠️ Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| **Cloud Provider** | AWS (EKS) | - |
| **Container Orchestration** | Kubernetes | 1.28+ |
| **Web Framework** | Flask | 2.0.1 |
| **Database** | MySQL | 5.7 |
| **Programming Language** | Python | 3.9 |
| **Container Runtime** | Docker | 20.10+ |
| **CLI Tools** | kubectl, eksctl, AWS CLI | Latest |

### Python Dependencies:
- Flask 2.0.1
- Flask-MySQLdb 0.2.0
- requests 2.26.0
- Werkzeug 2.2.2

---

## 📋 Prerequisites

Before starting, ensure you have the following installed and configured:

### 1. AWS Account
- Active AWS account with appropriate permissions
- IAM user with EKS, EC2, and VPC permissions

### 2. Required Tools

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verify installations
aws --version
kubectl version --client
eksctl version
```

### 3. Configure AWS CLI

```bash
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (e.g., us-east-1)
# - Default output format (json)
```

### 4. Docker Hub Account
- Create account at https://hub.docker.com
- Note your username for pushing images

---

## 🚀 Step-by-Step Deployment Guide

### **Step 1: Clone the Repository**

```bash
git clone <your-repository-url>
cd two-tier-flask-app
```

### **Step 2: Build and Push Docker Image**

```bash
# Login to Docker Hub
docker login

# Build the Docker image
docker build -t <your-dockerhub-username>/flask-app:latest .

# Push to Docker Hub
docker push <your-dockerhub-username>/flask-app:latest
```

**Note**: If you want to use the existing image, you can skip this step and use `ujwalnagrikar/pythonapp:latest`

### **Step 3: Create EKS Cluster**

```bash
# Create EKS cluster (takes 15-20 minutes)
eksctl create cluster \
  --name two-tier-cluster \
  --region us-east-1 \
  --nodegroup-name two-tier-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 3 \
  --managed

# Verify cluster creation
eksctl get cluster --name two-tier-cluster --region us-east-1

# Update kubeconfig
aws eks update-kubeconfig --name two-tier-cluster --region us-east-1

# Verify connection
kubectl get nodes
```

**Expected Output:**
```
NAME                           STATUS   ROLES    AGE   VERSION
ip-192-168-xx-xx.ec2.internal  Ready    <none>   2m    v1.28.x
ip-192-168-xx-xx.ec2.internal  Ready    <none>   2m    v1.28.x
```

### **Step 4: Create Namespace (Optional)**

```bash
# Create namespace for organization
kubectl create namespace two-tier-app

# Set as default namespace
kubectl config set-context --current --namespace=two-tier-app
```

### **Step 5: Deploy MySQL Database**

Navigate to the Kubernetes manifests directory:

```bash
cd eks-manifests
```

#### 5.1 Create MySQL Secret

```bash
kubectl apply -f mysql-secrets.yml
```

**Verify:**
```bash
kubectl get secrets
```

#### 5.2 Create MySQL ConfigMap

```bash
kubectl apply -f mysql-configmap.yml
```

**Verify:**
```bash
kubectl get configmap
```

#### 5.3 Deploy MySQL

```bash
kubectl apply -f mysql-deployment.yml
```

**Verify:**
```bash
kubectl get pods
kubectl logs <mysql-pod-name>
```

#### 5.4 Create MySQL Service

```bash
kubectl apply -f mysql-svc.yml
```

**Verify:**
```bash
kubectl get svc
```

**Wait for MySQL to be ready:**
```bash
kubectl wait --for=condition=ready pod -l app=mysql --timeout=300s
```

### **Step 6: Deploy Flask Application**

#### 6.1 Update Deployment YAML (if using custom image)

Edit `two-tier-app-deployment.yml`:

```yaml
image: <your-dockerhub-username>/flask-app:latest
```

#### 6.2 Deploy Flask Application

```bash
kubectl apply -f two-tier-app-deployment.yml
```

**Verify:**
```bash
kubectl get pods
kubectl logs <flask-app-pod-name>
```

#### 6.3 Create Flask Service (LoadBalancer)

```bash
kubectl apply -f two-tier-app-svc.yml
```

**Verify:**
```bash
kubectl get svc two-tier-app-service
```

**Wait for LoadBalancer (2-3 minutes):**
```bash
kubectl get svc two-tier-app-service --watch
```

---

## 🌐 Accessing the Application

### **Get LoadBalancer URL**

```bash
kubectl get svc two-tier-app-service
```

**Output Example:**
```
NAME                   TYPE           CLUSTER-IP      EXTERNAL-IP                                                              PORT(S)        AGE
two-tier-app-service   LoadBalancer   10.100.200.50   a1b2c3d4e5f6g7h8-1234567890.us-east-1.elb.amazonaws.com   80:32000/TCP   5m
```

### **Access the Application**

Open your browser and navigate to:
```
http://<EXTERNAL-IP>
```

Example:
```
http://a1b2c3d4e5f6g7h8-1234567890.us-east-1.elb.amazonaws.com
```

### **Test the Application**

1. You should see a beautiful animated web interface
2. Type a message in the input field
3. Click "Send Message ✨"
4. Your message should appear in the messages list
5. Refresh the page - your message persists (stored in MySQL)

---

## 🔍 Common Issues & Solutions

### **Issue 1: Pods in CrashLoopBackOff**

**Symptom:**
```bash
kubectl get pods
# NAME                            READY   STATUS             RESTARTS   AGE
# two-tier-app-xxxxxxxxx-xxxxx    0/1     CrashLoopBackOff   5          10m
```

**Solution:**
```bash
# Check pod logs
kubectl logs <pod-name>

# Check pod description
kubectl describe pod <pod-name>

# Common fixes:
# 1. Verify MySQL is running
kubectl get pods -l app=mysql

# 2. Check MySQL service
kubectl get svc mysql

# 3. Verify environment variables
kubectl describe deployment two-tier-app
```

### **Issue 2: Cannot Connect to MySQL**

**Symptom:**
```
Error: Can't connect to MySQL server on 'mysql'
```

**Solution:**
```bash
# Check MySQL pod status
kubectl get pods -l app=mysql

# Test MySQL connectivity from Flask pod
kubectl exec -it <flask-pod-name> -- sh
ping mysql
telnet mysql 3306

# Verify MySQL service endpoints
kubectl get endpoints mysql

# Check MySQL logs
kubectl logs <mysql-pod-name>
```

### **Issue 3: LoadBalancer Stuck in Pending**

**Symptom:**
```bash
kubectl get svc
# NAME                   TYPE           EXTERNAL-IP   PORT(S)
# two-tier-app-service   LoadBalancer   <pending>     80:32000/TCP
```

**Solution:**
```bash
# Check AWS Load Balancer Controller
kubectl get pods -n kube-system

# Verify IAM permissions
aws sts get-caller-identity

# Check service events
kubectl describe svc two-tier-app-service

# Alternative: Use NodePort temporarily
kubectl edit svc two-tier-app-service
# Change type: LoadBalancer to type: NodePort
```

### **Issue 4: Application Shows 502 Bad Gateway**

**Solution:**
```bash
# Check if Flask pods are running
kubectl get pods -l app=two-tier-app

# Verify Flask application logs
kubectl logs <flask-pod-name>

# Check if port 5000 is accessible
kubectl port-forward <flask-pod-name> 5000:5000
# Then access http://localhost:5000

# Restart deployment
kubectl rollout restart deployment two-tier-app
```

### **Issue 5: Database Table Not Created**

**Solution:**
```bash
# Connect to MySQL pod
kubectl exec -it <mysql-pod-name> -- mysql -uroot -padmin

# Check database
SHOW DATABASES;
USE mydb;
SHOW TABLES;

# If table missing, create manually
CREATE TABLE messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message TEXT
);

# Exit MySQL
exit
```

### **Issue 6: Image Pull Error**

**Symptom:**
```
Failed to pull image "your-image:latest": rpc error: code = Unknown
```

**Solution:**
```bash
# Verify image exists in Docker Hub
docker pull <your-image>

# Use correct image name in deployment
kubectl edit deployment two-tier-app

# Or use the public image
image: ujwalnagrikar/pythonapp:latest

# Apply changes
kubectl rollout restart deployment two-tier-app
```

### **Issue 7: EKS Cluster Creation Failed**

**Solution:**
```bash
# Delete failed cluster
eksctl delete cluster --name two-tier-cluster --region us-east-1

# Check AWS CloudFormation for errors
aws cloudformation describe-stacks --region us-east-1

# Retry with verbose logging
eksctl create cluster --name two-tier-cluster --region us-east-1 --verbose 4

# Check IAM permissions
aws iam get-user
```

---

## 🔄 Scaling the Application

### **Scale Flask Pods**

```bash
# Scale to 3 replicas
kubectl scale deployment two-tier-app --replicas=3

# Verify scaling
kubectl get pods -l app=two-tier-app

# Auto-scale based on CPU
kubectl autoscale deployment two-tier-app --min=2 --max=5 --cpu-percent=70
```

### **Check Application Metrics**

```bash
# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# View resource usage
kubectl top nodes
kubectl top pods
```

---

## 📊 Monitoring & Debugging

### **View Logs**

```bash
# Flask application logs
kubectl logs -f deployment/two-tier-app

# MySQL logs
kubectl logs -f deployment/mysql

# All pods logs
kubectl logs -f -l app=two-tier-app
```

### **Check Pod Status**

```bash
# Get all resources
kubectl get all

# Detailed pod information
kubectl describe pod <pod-name>

# Get events
kubectl get events --sort-by=.metadata.creationTimestamp
```

### **Execute Commands in Pod**

```bash
# Access Flask container
kubectl exec -it <flask-pod-name> -- /bin/bash

# Access MySQL container
kubectl exec -it <mysql-pod-name> -- /bin/bash

# Run MySQL commands
kubectl exec -it <mysql-pod-name> -- mysql -uroot -padmin mydb
```

---

## 🧹 Cleanup

### **Delete All Kubernetes Resources**

```bash
# Delete in reverse order
kubectl delete -f two-tier-app-svc.yml
kubectl delete -f two-tier-app-deployment.yml
kubectl delete -f mysql-svc.yml
kubectl delete -f mysql-deployment.yml
kubectl delete -f mysql-configmap.yml
kubectl delete -f mysql-secrets.yml

# Or delete everything at once
kubectl delete -f eks-manifests/
```

### **Delete EKS Cluster**

```bash
# Delete cluster (takes 10-15 minutes)
eksctl delete cluster --name two-tier-cluster --region us-east-1

# Verify deletion
eksctl get cluster --name two-tier-cluster --region us-east-1
```

### **Verify AWS Resources Cleaned Up**

```bash
# Check EC2 instances
aws ec2 describe-instances --region us-east-1 --filters "Name=tag:Name,Values=*two-tier*"

# Check Load Balancers
aws elbv2 describe-load-balancers --region us-east-1

# Check CloudFormation stacks
aws cloudformation list-stacks --region us-east-1
```

---

## 📝 Project Structure

```
two-tier-flask-app/
│
├── app.py                          # Flask application
├── requirements.txt                # Python dependencies
├── Dockerfile                      # Container image definition
├── docker-compose.yml              # Local development setup
├── message.sql                     # Database schema
│
├── templates/
│   └── index.html                  # Frontend UI
│
└── eks-manifests/
    ├── mysql-secrets.yml           # MySQL credentials (base64)
    ├── mysql-configmap.yml         # Database initialization
    ├── mysql-deployment.yml        # MySQL pod configuration
    ├── mysql-svc.yml               # MySQL service (ClusterIP)
    ├── two-tier-app-deployment.yml # Flask pod configuration
    └── two-tier-app-svc.yml        # Flask service (LoadBalancer)
```

---

## 🎓 Learning Outcomes

After completing this deployment, you will have learned:

✅ Creating and managing AWS EKS clusters
✅ Deploying multi-tier applications on Kubernetes
✅ Working with Kubernetes resources (Pods, Deployments, Services)
✅ Managing secrets and configurations in Kubernetes
✅ Exposing applications using LoadBalancer
✅ Troubleshooting common Kubernetes issues
✅ Connecting frontend and backend applications
✅ Scaling applications in Kubernetes

---

## 🤝 Contributing

Feel free to fork this project and submit pull requests for improvements!

---

## 📧 Support

If you encounter any issues:
1. Check the [Common Issues & Solutions](#common-issues--solutions) section
2. Review pod logs: `kubectl logs <pod-name>`
3. Check AWS CloudWatch for EKS logs
4. Open an issue in the repository

---

## ⭐ Star This Repository

If you found this guide helpful, please star this repository!

---

**Happy Learning! 🚀**

Deploy with confidence on AWS EKS!
