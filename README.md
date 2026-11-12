```markdown
# نشر وإدارة نموذج تصنيف النوايا (Intent Classifier) على AWS

يوضح هذا الدليل خطوات بناء البنية التحتية الكاملة لنشر نموذج التعلم الآلي باستخدام **Application Load Balancer (ALB)** و **Auto Scaling Group (ASG)** عبر **AWS Management Console**، بالإضافة إلى طرق حذف جميع الموارد سواء من خلال الواجهة الرسومية أو عبر **AWS CloudShell**.

---

## المعمارية الهندسية (Architecture)

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

```

---

## القسم الأول: إنشاء الموارد عبر AWS Management Console

### 1. إعداد الشبكة (VPC Networking)

1. انتقل إلى خدمة **VPC** ثم اختر **Your VPCs** واضغط **Create VPC**:
* **Name tag:** `intent-vpc`
* **IPv4 CIDR block:** `10.10.0.0/16`


2. انتقل إلى **Subnets** واضغط **Create subnet** لإنشاء شبكتين عامتين في منطقتين مختلفتين:
* الشبكة الأولى: الاسم `intent-public-subnet-1` | النطاق `10.10.1.0/24` | المنطقة `eu-north-1a`.
* الشبكة الثانية: الاسم `intent-public-subnet-2` | النطاق `10.10.2.0/24` | المنطقة `eu-north-1b`.
* من قائمة **Actions** لكل شبكة، اختر **Edit subnet settings** وفعّل خيار **Enable auto-assign public IPv4 address**.


3. انتقل إلى **Internet gateways** واضغط **Create internet gateway** باسم `intent-igw`، ثم اضغط **Attach to a VPC** واربطه بـ `intent-vpc`.
4. انتقل إلى **Route tables** واضغط **Create route table** باسم `intent-public-rtb` داخل `intent-vpc`:
* من تبويب **Routes** أضف مساراً جديداً: **Destination** `0.0.0.0/0` يشير إلى **Target** `intent-igw`.
* من تبويب **Subnet associations** اربط الشبكتين `intent-public-subnet-1` و `intent-public-subnet-2`.



### 2. إعداد جدار الحماية (Security Group)

1. انتقل إلى خدمة **EC2** ثم **Security Groups** واضغط **Create security group**:
* **Name:** `intent-sg` | **VPC:** `intent-vpc`


2. أضف قاعدتين في **Inbound rules**:
* **HTTP (Port 80)** من المصدر `0.0.0.0/0`
* **SSH (Port 22)** من المصدر `0.0.0.0/0`



### 3. إنشاء قالب التشغيل (Launch Template)

1. من قسم **Instances** اختر **Launch Templates** واضغط **Create launch template** باسم `mlops-template`.
2. **AMI:** اختر **Ubuntu Server 24.04 LTS** أو **20.04 LTS**.
3. **Instance type:** اختر `t3.micro` (أو الحجم المناسب للنموذج).
4. **Key pair:** اختر مفتاح الدخول الخاص بك.
5. **Network settings:** اترك **Subnet** على وضع عدم التحديد، واختر **Select existing security group** وحدد `intent-sg`.
6. **Advanced details -> User data:** الصق سكربت التهيئة التالي لتثبيت التطبيق وتشغيل Gunicorn و Nginx تلقائياً:

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

### 4. إنشاء Target Group و Application Load Balancer

1. من قسم **Load Balancing** اختر **Target Groups** واضغط **Create target group**:
* **Target type:** `Instances` | **Name:** `mlops-target-group` | **Protocol/Port:** `HTTP : 80` | **VPC:** `intent-vpc`
* **Health check path:** `/health` (مع التأكد أن كود النجاح `200`).


2. انتقل إلى **Load Balancers** واضغط **Create load balancer** من نوع **Application Load Balancer**:
* **Name:** `model-deployment` | **Scheme:** `Internet-facing`
* **Network mapping:** اختر `intent-vpc` وحدد الشبكتين `intent-public-subnet-1` و `intent-public-subnet-2`.
* **Security groups:** اختر `intent-sg`.
* **Listeners and routing:** وجّه منفذ `HTTP : 80` إلى `mlops-target-group`.



### 5. إنشاء Auto Scaling Group (ASG)

1. من قسم **Auto Scaling** اختر **Auto Scaling Groups** واضغط **Create Auto Scaling group**:
* **Name:** `mlops-autoscaling` | **Launch template:** `mlops-template`.
* **Network:** اختر `intent-vpc` وحدد الشبكتين الفرعيتين.
* **Load balancing:** اختر **Attach to an existing load balancer** وحدد `mlops-target-group`، مع تفعيل **ELB health checks**.
* **Group size:** حدد `Desired: 1`، `Min: 1`، `Max: 3`.


2. بعد اكتمال التشغيل وظهور حالة السيرفر **Healthy** داخل **Target Group**، افتح رابط **DNS name** الخاص بالـ ALB في المتصفح.

---

## القسم الثاني: حذف الموارد عبر AWS Management Console

يجب الالتزام بالترتيب العكسي التالي لتجنب أخطاء ارتباط الموارد:

1. **حذف Auto Scaling Group:**
* انتقل إلى **EC2 -> Auto Scaling Groups**، حدد `mlops-autoscaling`، ومن قائمة **Actions** اختر **Delete** واكتب `delete` للتأكيد. انتظر حتى تصبح حالة السيرفرات في **Instances** هي **Terminated**.


2. **حذف Load Balancer:**
* انتقل إلى **EC2 -> Load Balancers**، حدد `model-deployment`، ومن قائمة **Actions** اختر **Delete load balancer**.


3. **حذف Target Group:**
* انتقل إلى **EC2 -> Target Groups**، حدد `mlops-target-group`، ومن قائمة **Actions** اختر **Delete**.


4. **حذف Launch Template:**
* انتقل إلى **EC2 -> Launch Templates**، حدد `mlops-template`، ومن قائمة **Actions** اختر **Delete template**.


5. **حذف Security Group:**
* انتقل إلى **EC2 -> Security Groups**، حدد `intent-sg`، ومن قائمة **Actions** اختر **Delete security groups** (تأكد من إغلاق كافة السيرفرات وحذف الـ ALB أولاً).


6. **حذف الشبكة (VPC):**
* انتقل إلى **VPC -> Your VPCs**، حدد `intent-vpc`، ومن قائمة **Actions** اختر **Delete VPC**. سيقوم النظام تلقائياً بحذف الـ **Subnets**، و **Route Table**، وفصل وحذف **Internet Gateway** دفعة واحدة.



---

## القسم الثالث: حذف الموارد عبر AWS CloudShell

افتح **AWS CloudShell** من الشريط العلوي للكونسول ونفّذ الأوامر التالية بالترتيب:

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

انتظر حوالي دقيقة واحدة حتى يتم إنهاء جميع السيرفرات وتحرير كروت الشبكة، ثم نفّذ أوامر حذف جدار الحماية والشبكة:

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

للتحقق النهائي من نظافة الحساب وعدم وجود أي موارد نشطة:

```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,pending,shutting-down" --query 'Reservations[*].Instances[*].InstanceId' --region $AWS_REGION
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerName' --region $AWS_REGION
aws ec2 describe-vpcs --filters "Name=cidr,Values=10.10.0.0/16" --region $AWS_REGION

```

```

```
