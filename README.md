# Terraform on AWS: EC2 + Nginx (Beginner Hands-on)

A step-by-step beginner project to provision an Ubuntu EC2 instance on
AWS using Terraform, configure networking and security, connect through
SSH, and serve the Nginx welcome page.

> **Region used:** `ap-south-1` (Mumbai)\
> **Local environment:** WSL / Linux terminal\
> **Terraform project directory:** `~/terraform-projects/ec2Demo`

------------------------------------------------------------------------

## 1. What you'll build

``` text
Your browser / SSH client
          |
      Internet
          |
   Internet Gateway
          |
  Route: 0.0.0.0/0
          |
  Public subnet (10.0.1.0/24)
          |
  Ubuntu EC2 instance
  ├── SSH (TCP 22) — only from your public IP
  └── Nginx (TCP 80) — public web access
```

Terraform manages these AWS resources:

1.  AWS provider configuration
2.  VPC
3.  Subnet
4.  Internet Gateway
5.  Route table and subnet association
6.  Security group
7.  EC2 key pair (AWS receives only the public key)
8.  EC2 instance with Nginx installation through user data

## 2. Prerequisites

Install and configure these on your WSL terminal:

-   Terraform CLI
-   AWS CLI
-   An AWS account with permission to create the resources in this
    project
-   SSH key-generation utility (`ssh-keygen`)

Verify the tools:

``` bash
terraform -version
aws --version
command -v ssh-keygen
```

Check that AWS credentials work:

``` bash
aws sts get-caller-identity
```

If this fails, configure AWS CLI credentials using your preferred secure
method before continuing. **Do not put AWS access keys in Terraform
files or commit them to Git.**

Set the region for AWS CLI commands:

``` bash
export AWS_DEFAULT_REGION=ap-south-1
```

The Terraform provider below explicitly selects the same region.

## 3. Create the project directory

``` bash
mkdir -p ~/terraform-projects/ec2Demo
cd ~/terraform-projects/ec2Demo
```

Terraform configuration files use the `.tf` extension. In this project,
we'll use `main.tf`.

## 4. Generate an SSH key pair

Create a key pair in WSL:

``` bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/terraform-ec2 -C "terraform-ec2"
chmod 600 ~/.ssh/terraform-ec2
```

Choose a passphrase if you want extra protection. The generated files
are:

  -----------------------------------------------------------------------
  File                                Purpose
  ----------------------------------- -----------------------------------
  `~/.ssh/terraform-ec2`              Private key --- keep it secret and
                                      on your machine

  `~/.ssh/terraform-ec2.pub`          Public key --- Terraform registers
                                      this with AWS
  -----------------------------------------------------------------------

Check the files:

``` bash
ls -l ~/.ssh/terraform-ec2*
cat ~/.ssh/terraform-ec2.pub
```

Never paste, upload, or commit the private key. The `aws_key_pair`
resource registers the **public** key; AWS does not receive your private
key.

## 5. Build `main.tf` step by step

You can add each section to `main.tf` as you learn it. The final
configuration below puts all required resources together.

### Step 5.1 --- AWS provider

``` hcl
provider "aws" {
  region = "ap-south-1"
}
```

**Meaning:** The AWS provider plugin allows Terraform to communicate
with AWS. This configuration uses the Mumbai region and obtains
credentials from the AWS CLI's configured credential chain/environment.

### Step 5.2 --- VPC and subnet

``` hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "terraform-ec2-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "terraform-public-subnet"
  }
}
```

**Meaning:** - The VPC defines our isolated virtual network. - The
subnet is a smaller IP range inside the VPC. - `aws_vpc.main.id`
references the VPC's ID. Terraform infers that the VPC must be created
before the subnet. - `map_public_ip_on_launch = true` enables automatic
public IPv4 assignment for instances launched in the subnet, unless
overridden.

**Important:** A subnet is not truly public just because it is named
`public` or assigns public IPs. It also needs a route to an Internet
Gateway.

### Step 5.3 --- Internet Gateway, route table, and association

``` hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "terraform-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

**Meaning:** - The Internet Gateway provides a path between the VPC and
the internet. - The route `0.0.0.0/0` sends destinations not covered by
a more specific route to the Internet Gateway. - The association
attaches this route table to our subnet.

### Step 5.4 --- Security group

First find your current public IPv4 address:

``` bash
curl -4 https://checkip.amazonaws.com
```

In the security group below, replace `REPLACE_WITH_YOUR_PUBLIC_IP/32`
with the address returned, followed by `/32`. For example, if the
command returns `203.0.113.10`, use `203.0.113.10/32` only as a format
example; use your actual current address.

``` hcl
resource "aws_security_group" "web_sg" {
  name        = "terraform-web-sg"
  description = "Allow SSH from my IP and HTTP for Nginx"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my current public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["REPLACE_WITH_YOUR_PUBLIC_IP/32"]
  }

  ingress {
    description = "HTTP for Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-web-sg"
  }
}
```

**Meaning:** - Inbound TCP `22` permits SSH from your IP only. - Inbound
TCP `80` permits public HTTP requests to Nginx. - The outbound rule
permits outbound IPv4 traffic, including package downloads.

If your public IP changes, update the SSH CIDR and apply the Terraform
change. Do not open SSH to `0.0.0.0/0` just to troubleshoot.

### Step 5.5 --- Register the public key with AWS

``` hcl
resource "aws_key_pair" "deployer" {
  key_name   = "terraform-ec2-key"
  public_key = file(pathexpand("~/.ssh/terraform-ec2.pub"))
}
```

**Meaning:** `aws_key_pair` registers the local public key in AWS.
`pathexpand` expands `~` to your home directory, and `file` reads the
public-key file.

If AWS already has a key pair named `terraform-ec2-key`, choose a unique
`key_name` or deliberately import/manage the existing key. Do not assume
an existing key pair is identical to your local key.

### Step 5.6 --- EC2 instance and automatic Nginx installation

Choose a valid Ubuntu AMI for **Mumbai (`ap-south-1`)** and the
architecture that matches the instance type. AMI IDs are
region-specific; don't copy an ID from another region.

You can retrieve the current Ubuntu AMI from the AWS EC2 Console, or use
the official Ubuntu SSM parameter if available for the desired Ubuntu
release and architecture. Confirm the AMI is Ubuntu before using the
`ubuntu` SSH username.

``` hcl
resource "aws_instance" "web" {
  ami                         = "REPLACE_WITH_UBUNTU_AMI_ID"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable --now nginx
  EOF

  tags = {
    Name = "terraform-nginx-server"
  }
}
```

Replace `REPLACE_WITH_UBUNTU_AMI_ID` with the real AMI ID for Mumbai.
The `user_data` script is for Ubuntu and installs Nginx during first
boot.

**Meaning of key arguments:** - `ami`: operating system image to
launch. - `instance_type`: instance size; confirm current pricing and
account eligibility. - `subnet_id`: subnet where the instance will be
launched. - `vpc_security_group_ids`: attaches our security group. -
`key_name`: attaches the registered EC2 key pair. -
`associate_public_ip_address`: requests a public IPv4 address. -
`user_data`: runs startup commands during instance initialization. -
`tags`: adds a readable name to the instance.

A change to an EC2 instance's AMI or some other arguments can force
replacement. Always review `terraform plan` before applying changes.

### Step 5.7 --- Output the public IP

``` hcl
output "ec2_public_ip" {
  description = "Public IPv4 address of the Nginx EC2 instance"
  value       = aws_instance.web.public_ip
}

output "nginx_url" {
  description = "HTTP URL for the Nginx web server"
  value       = "http://${aws_instance.web.public_ip}"
}
```

Outputs display useful values after Terraform applies the configuration.

## 6. Final `main.tf` checklist

Your final `main.tf` should contain all the blocks from Steps 5.1--5.7:

-   [ ] `provider "aws"`
-   [ ] `aws_vpc.main`
-   [ ] `aws_subnet.public`
-   [ ] `aws_internet_gateway.igw`
-   [ ] `aws_route_table.public`
-   [ ] `aws_route_table_association.public`
-   [ ] `aws_security_group.web_sg`
-   [ ] `aws_key_pair.deployer`
-   [ ] `aws_instance.web`
-   [ ] `output "ec2_public_ip"`
-   [ ] `output "nginx_url"`

Do not leave either placeholder (`REPLACE_WITH_YOUR_PUBLIC_IP/32` or
`REPLACE_WITH_UBUNTU_AMI_ID`) in the file.

## 7. Initialize, validate, plan, and apply

From the project directory:

``` bash
cd ~/terraform-projects/ec2Demo

terraform fmt
terraform init
terraform validate
terraform plan
```

Review the plan. It should create the resources needed for the VPC,
subnet, internet routing, security group, key pair, and EC2 instance. If
resources already exist from earlier steps, the plan may instead show
updates or no changes.

Then apply:

``` bash
terraform apply
```

Read the proposed actions carefully and type `yes` only if they are what
you expect.

Get the public IP and URL:

``` bash
terraform output
terraform output -raw ec2_public_ip
terraform output -raw nginx_url
```

The instance may take a minute or two after creation before cloud-init
finishes installing Nginx.

## 8. Verify Nginx and connect over SSH

Open the output URL in your browser, for example:

``` text
http://<EC2_PUBLIC_IP>
```

You should see the default Nginx welcome page.

Connect from WSL using the private key and the Ubuntu default username:

``` bash
ssh -i ~/.ssh/terraform-ec2 ubuntu@<EC2_PUBLIC_IP>
```

Use the **private** key path `~/.ssh/terraform-ec2`, not the public key
`.pub` file. The filename `terraform-ec2-key.pem` will not work unless
you actually created a file with that name.

Inside EC2, useful checks are:

``` bash
cat /etc/os-release
sudo systemctl status nginx
curl -I http://localhost
```

Return to WSL by running:

``` bash
exit
```

### If SSH times out

A timeout usually indicates a network path or firewall issue rather than
a wrong key. Check:

1.  The instance is running and has the expected public IP.
2.  The attached security group allows TCP 22 from your **current**
    public IP `/32`.
3.  The subnet's route table has `0.0.0.0/0` pointing to the VPC's
    Internet Gateway.
4.  The Internet Gateway is attached to the correct VPC.
5.  Your local network allows outbound SSH.

Check your public IP:

``` bash
curl -4 https://checkip.amazonaws.com
```

Inspect the instance and its attached security group:

``` bash
aws ec2 describe-instances \
  --region ap-south-1 \
  --filters "Name=ip-address,Values=<EC2_PUBLIC_IP>" \
  --query 'Reservations[].Instances[].{State:State.Name,PublicIP:PublicIpAddress,Subnet:SubnetId,VPC:VpcId,SecurityGroups:SecurityGroups[*].GroupId,KeyName:KeyName}' \
  --output table
```

Inspect inbound rules, replacing the security group ID with the one
attached to your instance:

``` bash
aws ec2 describe-security-groups \
  --region ap-south-1 \
  --group-ids <SECURITY_GROUP_ID> \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json
```

## 9. Terraform commands to remember

  -----------------------------------------------------------------------
  Command                             Purpose
  ----------------------------------- -----------------------------------
  `terraform init`                    Initializes the directory and
                                      installs provider plugins

  `terraform fmt`                     Formats Terraform files

  `terraform validate`                Checks configuration syntax and
                                      consistency

  `terraform plan`                    Previews proposed infrastructure
                                      changes

  `terraform apply`                   Applies the changes after
                                      confirmation

  `terraform state list`              Lists resources tracked in
                                      Terraform state

  `terraform state show <address>`    Shows recorded details for one
                                      resource

  `terraform output`                  Displays configured outputs

  `terraform destroy`                 Proposes removing resources managed
                                      by this configuration
  -----------------------------------------------------------------------

## 10. Key concepts learned

-   **Provider:** Plugin that lets Terraform communicate with AWS.
-   **Resource:** An infrastructure object Terraform manages.
-   **Resource reference:** For example, `aws_vpc.main.id`; Terraform
    uses references to infer dependencies.
-   **Dependency graph:** Terraform determines resource ordering from
    references.
-   **State:** Records the mapping between Terraform-managed resources
    and real infrastructure.
-   **Execution plan:** Previews the changes Terraform intends to make.
-   **Public subnet:** Needs an Internet Gateway route; a public IP
    alone is not enough.
-   **Security group:** Controls allowed inbound and outbound traffic.
-   **Key pair:** AWS stores the public key; you keep the private key.
-   **User data:** A startup script used here to install Nginx
    automatically.
-   **Outputs:** Expose useful values, such as the instance's public IP.

## 11. Important safety and cost notes

-   EC2, public IPv4 addresses, storage, and other AWS resources may
    incur charges. Check the pricing applicable to your account and
    region.
-   Keep SSH access limited to your own current IP.
-   Never commit private keys, AWS credentials, or Terraform state files
    to a public repository.
-   Terraform state may contain sensitive infrastructure details.
    Protect it and do not share it publicly.
-   Before applying, read the plan and check for unexpected resource
    replacement or destruction.
-   When finished, remove the resources you no longer need.

For a disposable learning environment, after confirming that this
Terraform configuration manages the resources you intend to remove, run:

``` bash
terraform plan -destroy
terraform destroy
```

Review the destroy plan carefully and confirm only when you're sure.
This removes resources managed by the current Terraform state, but does
not necessarily remove unrelated resources or resources created manually
outside Terraform.

------------------------------------------------------------------------

## Final workflow to memorize

``` text
Write .tf configuration
        ↓
terraform init
        ↓
terraform fmt + validate
        ↓
terraform plan
        ↓
Review the proposed changes
        ↓
terraform apply
        ↓
Verify EC2 + Nginx + SSH
        ↓
terraform destroy (when finished)
```

**Core takeaway:** Terraform lets you describe AWS infrastructure as
code, review changes before applying them, and repeatedly manage the
infrastructure from a version-controlled configuration.
