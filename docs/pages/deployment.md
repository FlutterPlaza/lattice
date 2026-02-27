# Deployment

Lattice includes an interactive deployment CLI (`tools/deploy`) that guides you through deploying the server to local Docker, AWS ECS, Azure Container Apps, GCP Cloud Run, or Firebase Cloud Run.

For platform-specific storage backends (Firebase Firestore, Serverpod PostgreSQL, Supabase), see the [Platform Integrations](#platforms) page.

## Overview

The deployment tool handles:

- Building the Docker image
- Pushing to container registries
- Provisioning cloud infrastructure
- Configuring networking and scaling
- Starting the service

## Prerequisites

Depending on your target environment:

| Target | Requirements |
|--------|-------------|
| Local Docker | Docker installed and running |
| AWS ECS | AWS CLI configured, Docker |
| Azure Container Apps | Azure CLI (`az`) configured, Docker |
| GCP Cloud Run | Google Cloud SDK (`gcloud`) configured, Docker |
| Firebase Cloud Run | Firebase CLI + Google Cloud SDK, Docker |

## Running the Deployment CLI

```bash
dart run tools/deploy/bin/deploy.dart
```

The interactive CLI will prompt you through configuration steps.

## Local Docker Deployment

The simplest deployment option runs the server in a local Docker container.

### Build

```bash
docker build -t lattice-server -f packages/lattice_server/Dockerfile .
```

### Run

```bash
# In-memory storage (data lost on restart)
docker run -d --name lattice -p 8080:8080 \
  lattice-server --host 0.0.0.0

# With persistent storage
docker run -d --name lattice -p 8080:8080 \
  -v lattice-data:/data \
  lattice-server --host 0.0.0.0 --storage-path /data
```

### Verify

```bash
curl http://localhost:8080/api/v1/health
# {"status":"ok","uptime":5,"version":"0.1.0"}
```

## AWS ECS Deployment

### 1. Create an ECR repository

```bash
aws ecr create-repository --repository-name lattice-server --region us-east-1
```

### 2. Build and push the image

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Tag and push
docker tag lattice-server:latest \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/lattice-server:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/lattice-server:latest
```

### 3. Create an ECS cluster and service

```bash
# Create cluster
aws ecs create-cluster --cluster-name lattice-cluster

# Register task definition (see task-definition.json below)
aws ecs register-task-definition --cli-input-json file://task-definition.json

# Create service
aws ecs create-service \
  --cluster lattice-cluster \
  --service-name lattice-service \
  --task-definition lattice-server \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

### Task definition example

```json
{
  "family": "lattice-server",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "lattice-server",
      "image": "<account-id>.dkr.ecr.us-east-1.amazonaws.com/lattice-server:latest",
      "portMappings": [
        { "containerPort": 8080, "protocol": "tcp" }
      ],
      "command": ["--host", "0.0.0.0", "--port", "8080"],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/lattice-server",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

## Azure Container Apps Deployment

### 1. Create a resource group and container registry

```bash
az group create --name lattice-rg --location eastus
az acr create --resource-group lattice-rg --name latticeacr --sku Basic
```

### 2. Build and push

```bash
az acr login --name latticeacr
docker tag lattice-server:latest latticeacr.azurecr.io/lattice-server:latest
docker push latticeacr.azurecr.io/lattice-server:latest
```

### 3. Deploy to Container Apps

```bash
az containerapp env create \
  --name lattice-env \
  --resource-group lattice-rg \
  --location eastus

az containerapp create \
  --name lattice-server \
  --resource-group lattice-rg \
  --environment lattice-env \
  --image latticeacr.azurecr.io/lattice-server:latest \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 5 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --command "--host" "0.0.0.0" "--port" "8080"
```

## GCP Cloud Run Deployment

### 1. Build and push

```bash
gcloud auth configure-docker
docker tag lattice-server:latest gcr.io/<project-id>/lattice-server:latest
docker push gcr.io/<project-id>/lattice-server:latest
```

### 2. Deploy to Cloud Run

```bash
gcloud run deploy lattice-server \
  --image gcr.io/<project-id>/lattice-server:latest \
  --platform managed \
  --region us-central1 \
  --port 8080 \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 10 \
  --memory 512Mi \
  --cpu 1 \
  --args="--host,0.0.0.0,--port,8080"
```

## Scaling Configuration

All cloud providers support auto-scaling. Key considerations:

- **InMemoryStorage** does not support multi-instance deployments because each instance has its own state. Use an external database or shared file system for production.
- **FileStorage** works for single-instance deployments with a mounted volume.
- For multi-instance production, implement the `Storage` interface with a shared backend (e.g., PostgreSQL, Redis, DynamoDB).

### Recommended scaling parameters

| Parameter | Development | Production |
|-----------|------------|------------|
| Min instances | 0-1 | 1-2 |
| Max instances | 1 | 5-20 |
| CPU | 0.25 vCPU | 0.5-1 vCPU |
| Memory | 256 MB | 512 MB - 1 GB |

## Configuration Persistence

For persistent deployments, mount a volume for FileStorage:

| Provider | Volume Type |
|----------|-------------|
| Docker | Named volume or bind mount |
| AWS ECS | EFS mount |
| Azure | Azure Files share |
| GCP | Persistent disk or Filestore |

| Firebase | Firestore (no volume needed) |

Example with Docker named volume:

```bash
docker volume create lattice-data
docker run -p 8080:8080 -v lattice-data:/data \
  lattice-server --host 0.0.0.0 --storage-path /data
```

## Firebase Cloud Run Deployment

Firebase Cloud Run combines Google Cloud Run for compute with Firebase Hosting for proxying API requests.

### Prerequisites

```bash
npm install -g firebase-tools
firebase login
```

### Deploy

```bash
# Using the CLI
dart run tools/deploy/bin/deploy.dart deploy --target firebase

# Or manually
docker build -t lattice-server -f packages/lattice_server/Dockerfile .
gcloud builds submit --tag gcr.io/<project-id>/lattice-server
gcloud run deploy lattice-server \
  --image gcr.io/<project-id>/lattice-server \
  --platform managed --region us-central1 \
  --port 8080 --allow-unauthenticated
firebase deploy --only hosting
```

### Firebase Hosting Proxy

Add to your `firebase.json` to proxy API calls to Cloud Run:

```json
{
  "hosting": {
    "public": "public",
    "rewrites": [
      {
        "source": "/api/**",
        "run": {
          "serviceId": "lattice-server",
          "region": "us-central1"
        }
      }
    ]
  }
}
```

For Firestore storage and other platform-specific integrations, see [Platform Integrations](#platforms).
