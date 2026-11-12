# Deploy and Manage Intent Classifier Model on AWS

This guide outlines the complete infrastructure setup for deploying the Intent Classifier machine learning model using an **Application Load Balancer (ALB)** and an **Auto Scaling Group (ASG)** via the **AWS Management Console**, along with resource cleanup procedures using both the Console and **AWS CloudShell**.

---

## Architecture

```text
                        [ Users / Internet ]
                                 |
                                 v
                     +-----------------------+
                     |   Internet Gateway    |
                     +-----------------------+
                                 |
+--------------------------------|--------------------------------+
|  VPC (10.10.0.0/16)            v                                |
|                    +-----------------------+                    |
|                    | Application Load      |                    |
|                    | Balancer (ALB)        |                    |
|                    +-----------------------+                    |
|                       /                 \                       |
|                      /                   \                      |
|                     v                     v                     |
|   +-------------------------+     +-------------------------+   |
|   | Availability Zone A     |     | Availability Zone B     |   |
|   | +---------------------+ |     | +---------------------+ |   |
|   | | Public Subnet 1     | |     | | Public Subnet 2     | |   |
|   | |                     | |     | |                     | |   |
|   | |  +---------------+  | |     | |  +---------------+  | |   |
|   | |  | EC2 Instance  |  | |     | |  | EC2 Instance  |  | |   |
|   | |  | (Intent Model)|  | |     | |  | (Intent Model)|  | |   |
|   | |  +---------------+  | |     | |  +---------------+  | |   |
|   | +---------------------+ |     | +---------------------+ |   |
|   +-------------------------+     +-------------------------+   |
|                      \                   /                      |
|                       \                 /                       |
|                    +-----------------------+                    |
|                    | Auto Scaling Group &  |                    |
|                    | Target Group          |                    |
|                    +-----------------------+                    |
+-----------------------------------------------------------------+

``

---

## Part 1: Resource Creation via AWS Management Console

### 1. Configure VPC Networking

1. Navigate to the **VPC** service, select **Your VPCs**, and click **Create VPC**:
* **Name tag:** `intent-vpc`
* **IPv4 CIDR block:** `10.10.0.0/16`


2. Navigate to **Subnets** and click **Create subnet** to create two public subnets across different Availability Zones:
* **Subnet 1:** Name `intent-public-subnet-1` | CIDR `10.10.1.0/24` | AZ `eu-north-1a`
* **Subnet 2:** Name `intent-public-subnet-2` | CIDR `10.10.2.0/24` | AZ `eu-north-1b`
* Select each subnet, open **Actions -> Edit subnet settings**, and check **Enable auto-assign public IPv4 address**.


3. Navigate to **Internet gateways**, click **Create internet gateway** named `intent-igw`, then click **Attach to a VPC** and attach it to `intent-vpc`.
4. Navigate to **Route tables**, click **Create route table** named `intent-public-rtb` inside `intent-vpc`:
* Under the **Routes** tab, add a route with **Destination** `0.0.0.0/0` pointing to **Target** `intent-igw`.
* Under the **Subnet associations** tab, associate both `intent-public-subnet-1` and `intent-public-subnet-2`.



### 2. Configure Security Group

1. Navigate to **EC2 -> Security Groups** and click **Create security group**:
* **Name:** `intent-sg` | **VPC:** `intent-vpc`


2. Add two rules under **Inbound rules**:
* **HTTP (Port 80)** from source `0.0.0.0/0`
* **SSH (Port 22)** from source `0.0.0.0/0`



### 3. Create Launch Template

1. Under **Instances**, select **Launch Templates** and click **Create launch template** named `mlops-template`.
2. **AMI:** Select **Ubuntu Server 24.04 LTS** or **20.04 LTS**.
3. **Instance type:** Select `t3.micro` (or an instance size suited for your model).
4. **Key pair:** Select your SSH key pair.
5. **Network settings:** Leave **Subnet** unselected, choose **Select existing security group**, and pick `intent-sg`.
6. **Advanced details -> User data:** Paste the following bootstrap script to automatically install dependencies and start Gunicorn and Nginx:

```bash
#!/bin/bash
set -e

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

APP_DIR="/opt/intent-app"
REPO_URL="[https://github.com/AbdullrahmanEissa/Intent-Classifier-Model-Trained](https://github.com/AbdullrahmanEissa/Intent-Classifier-Model-Trained)"

apt-get update -y
apt-get install -y git python3 python3-venv python3-pip nginx

mkdir -p "$APP_DIR"
git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

if [ ! -f "$APP_DIR/model/artifacts/intent_model.pkl" ]; then
    python3 model/train.py
fi

chown -R ubuntu:ubuntu "$APP_DIR"

cat > /etc/systemd/system/intent_gunicorn.service << 'EOF'
[Unit]
Description=Gunicorn instance for Intent Classifier
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/intent-app
Environment="PATH=/opt/intent-app/.venv/bin"
ExecStart=/opt/intent-app/.venv/bin/gunicorn --workers 2 --bind 127.0.0.1:6000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/nginx/conf.d/intent_app.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass [http://127.0.0.1:6000](http://127.0.0.1:6000);
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 120s;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
nginx -t

systemctl daemon-reload
systemctl enable intent_gunicorn
systemctl start intent_gunicorn
systemctl enable nginx
systemctl restart nginx

```

### 4. Create Target Group and Application Load Balancer

1. Under **Load Balancing**, select **Target Groups** and click **Create target group**:
* **Target type:** `Instances` | **Name:** `mlops-target-group` | **Protocol/Port:** `HTTP : 80` | **VPC:** `intent-vpc`
* **Health check path:** `/health` (ensure success code is `200`).


2. Navigate to **Load Balancers** and click **Create load balancer** (**Application Load Balancer**):
* **Name:** `model-deployment` | **Scheme:** `Internet-facing`
* **Network mapping:** Select `intent-vpc` and enable both `intent-public-subnet-1` and `intent-public-subnet-2`.
* **Security groups:** Select `intent-sg`.
* **Listeners and routing:** Forward `HTTP : 80` to `mlops-target-group`.



### 5. Create Auto Scaling Group (ASG)

1. Under **Auto Scaling**, select **Auto Scaling Groups** and click **Create Auto Scaling group**:
* **Name:** `mlops-autoscaling` | **Launch template:** `mlops-template`.
* **Network:** Select `intent-vpc` and both public subnets.
* **Load balancing:** Select **Attach to an existing load balancer**, choose `mlops-target-group`, and enable **ELB health checks**.
* **Group size:** Set `Desired: 1`, `Min: 1`, `Max: 3`.


2. Once the instance status turns **Healthy** inside the **Target Group**, open the ALB **DNS name** in your browser.

---

## Part 2: Resource Deletion via AWS Management Console

Delete resources in the following reverse order to prevent dependency errors:

1. **Delete Auto Scaling Group:**
* Go to **EC2 -> Auto Scaling Groups**, select `mlops-autoscaling`, click **Actions -> Delete**, and confirm. Wait until all instances under **Instances** reach the **Terminated** state.


2. **Delete Load Balancer:**
* Go to **EC2 -> Load Balancers**, select `model-deployment`, and click **Actions -> Delete load balancer**.


3. **Delete Target Group:**
* Go to **EC2 -> Target Groups**, select `mlops-target-group`, and click **Actions -> Delete**.


4. **Delete Launch Template:**
* Go to **EC2 -> Launch Templates**, select `mlops-template`, and click **Actions -> Delete template**.


5. **Delete Security Group:**
* Go to **EC2 -> Security Groups**, select `intent-sg`, and click **Actions -> Delete security groups** (ensure all EC2 instances and the ALB are completely removed first).


6. **Delete VPC:**
* Go to **VPC -> Your VPCs**, select `intent-vpc`, and click **Actions -> Delete VPC**. AWS will automatically delete associated **Subnets**, **Route Tables**, and detach/delete the **Internet Gateway** in one step.



---

## Part 3: Resource Deletion via AWS CloudShell

Open **AWS CloudShell** from the top navigation bar and run the following commands sequentially:

```bash
export AWS_REGION="eu-north-1"

aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name mlops-autoscaling \
  --force-delete \
  --region $AWS_REGION

ALB_ARN=$(aws elbv2 describe-load-balancers --names model-deployment --query 'LoadBalancers[0].LoadBalancerArn' --output text --region$AWS_REGION)
TG_ARN=$(aws elbv2 describe-target-groups --names mlops-target-group --query 'TargetGroups[0].TargetGroupArn' --output text --region$AWS_REGION)

aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region $AWS_REGION
sleep 15
aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region $AWS_REGION

aws ec2 delete-launch-template \
  --launch-template-name mlops-template \
  --region $AWS_REGION

```

Wait approximately one minute for all EC2 instances to terminate and network interfaces to release, then delete the Security Group and VPC networking components:

```bash
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=intent-sg" --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION)
aws ec2 delete-security-group --group-id "$SG_ID" --region $AWS_REGION

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=cidr,Values=10.10.0.0/16" --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)

for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION); do
    aws ec2 delete-subnet --subnet-id "$subnet" --region $AWS_REGION
done

for rtb in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text --region $AWS_REGION); do
    aws ec2 delete-route-table --route-table-id "$rtb" --region $AWS_REGION
done

IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text --region $AWS_REGION)
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region $AWS_REGION
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region $AWS_REGION

aws ec2 delete-vpc --vpc-id "$VPC_ID" --region $AWS_REGION

```

Verify that no active resources remain in the region:

```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,pending,shutting-down" --query 'Reservations[*].Instances[*].InstanceId' --region $AWS_REGION
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerName' --region $AWS_REGION
aws ec2 describe-vpcs --filters "Name=cidr,Values=10.10.0.0/16" --region $AWS_REGION

```

```

```
