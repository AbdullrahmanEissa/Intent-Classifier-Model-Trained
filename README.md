# Deploy Intent Classifier Model on Amazon ECS (Fargate)

End-to-end guide to build the Docker image, push it to Docker Hub, create an Amazon ECS Fargate cluster, deploy the container, and clean up all resources via **AWS Console** or **AWS CloudShell**.

---

## 1. Build & Push Docker Image to Docker Hub

```bash
# Build the image from the Dockerfile
docker build -t abdueissa/intent-classifier-model:latest .

# Test locally on port 8080 -> 6000
docker run -d -p 8080:6000 --name intent-app abdueissa/intent-classifier-model:latest
docker ps

# Stop local test container
docker rm -f intent-app

# Log in and push to Docker Hub
docker login
docker push abdueissa/intent-classifier-model:latest
```

---

## 2. Deploy to Amazon ECS (Choose One Method)

### Method A: Create Cluster & Deploy via AWS Console

#### Step 1: Create ECS Cluster
1. Open the **Amazon ECS Console** and select your region (e.g., `eu-north-1`).
2. Click **Clusters** > **Create cluster**.
3. **Cluster name**: `intent-classifier-cluster`
4. **Infrastructure**: Keep **AWS Fargate (serverless)** selected and click **Create**.

#### Step 2: Create Task Definition
1. Go to **Task definitions** > **Create new task definition**.
2. **Task definition family**: `intent-classifier-task`
3. **Launch type**: **AWS Fargate** | **CPU**: `0.5 vCPU` | **Memory**: `1 GB`
4. Under **Container - 1**:
   - **Name**: `intent-app`
   - **Image URI**: `abdueissa/intent-classifier-model:latest`
   - **Container port**: `6000` (`TCP`)
5. Click **Create**.

#### Step 3: Run Service / Task
1. Open **`intent-classifier-cluster`** > **Services** tab > **Create**.
2. **Family**: Select `intent-classifier-task` | **Service name**: `intent-app-service` | **Desired tasks**: `1`
3. Expand **Networking**:
   - Keep default **VPC** and **Subnets** selected.
   - **Security group**: Create a new security group allowing **Custom TCP** on port **`6000`** from **`0.0.0.0/0`** (Anywhere).
   - **Public IP**: Keep **Turned on**.
4. Click **Create** and wait ~2 minutes until task status is **Running**.
5. Click the running task > **Configuration** > copy the **Public IP** and open `http://<PUBLIC-IP>:6000`.

---

### Method B: Create Cluster & Deploy via AWS CloudShell (CLI Commands)

Open **AWS CloudShell** (`>_` icon in top toolbar) and run:

```bash
export REGION=eu-north-1
export CLUSTER=intent-classifier-cluster

# 1. Create ECS Fargate Cluster
aws ecs create-cluster --cluster-name CLUSTER --region REGION

# 2. Ensure ecsTaskExecutionRole exists
aws iam create-role --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"://amazonaws.com"},"Action":"sts:AssumeRole"}]}' 2>/dev/null || true
aws iam attach-role-policy --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text)

# 3. Register Task Definition
aws ecs register-task-definition \
  --region \$REGION \
  --family intent-classifier-task \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu "512" \
  --memory "1024" \
  --execution-role-arn arn:aws:iam::\$ACCOUNT_ID:role/ecsTaskExecutionRole \
  --container-definitions '[{
    "name": "intent-app",
    "image": "abdueissa/intent-classifier-model:latest",
    "essential": true,
    "portMappings": [{"containerPort": 6000, "protocol": "tcp"}]
  }]'

# 4. Create Security Group allowing port 6000 & launch ECS Service
VPC_ID=\$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text --region \$REGION)
SUBNETS=(aws ec2 describe-subnets --filters Name=vpc-id,Values=VPC_ID --query "Subnets[0:2].SubnetId" --output text --region \$REGION | tr '\t' ',')
SG_ID=\$(aws ec2 create-security-group --group-name intent-ecs-sg --description "Allow port 6000" --vpc-id \(VPC_ID --region\)REGION --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id \$SG_ID --protocol tcp --port 6000 --cidr 0.0.0.0/0 --region \$REGION

aws ecs create-service \
  --region \$REGION \
  --cluster \$CLUSTER \
  --service-name intent-app-service \
  --task-definition intent-classifier-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[\(SUBNETS],securityGroups=[\)SG_ID],assignPublicIp=ENABLED}"
```

### Get Your Public IP (CloudShell)
Wait ~1–2 minutes for the task to start, then retrieve its Public IP:
```bash
TASK_ARN=\$(aws ecs list-tasks --cluster intent-classifier-cluster --region eu-north-1 --query "taskArns[0]" --output text)
ENI_ID=(aws ecs describe-tasks --cluster intent-classifier-cluster --tasks TASK_ARN --region eu-north-1 --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)
PUBLIC_IP=(aws ec2 describe-network-interfaces --network-interface-ids ENI_ID --region eu-north-1 --query "NetworkInterfaces[0].Association.PublicIp" --output text)
echo "App URL: http://\$PUBLIC_IP:6000"
```

---

## 3. Cleanup / Delete Cluster (Stop Billing)

### Option A: Delete via AWS Console
1. Open **Amazon ECS Console** > **Clusters** > **`intent-classifier-cluster`**.
2. Select **`intent-app-service`** > **Delete** (check **Force delete** if prompted).
3. Once the service is deleted, click **Delete cluster** in the top right and confirm.

### Option B: Delete via AWS CloudShell
```bash
export REGION=eu-north-1
export CLUSTER=intent-classifier-cluster

# Delete service, cluster, and security group
aws ecs delete-service --cluster CLUSTER --service intent-app-service --force --region REGION
aws ecs delete-cluster --cluster CLUSTER --region REGION
aws ec2 delete-security-group --group-name intent-ecs-sg --region \$REGION 2>/dev/null || true
```
