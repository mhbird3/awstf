# Terraform exercise

basic network and compute resources: VPC, AZs, subnets, routing, security groups, load balancer, auto-scaling EC2 instances with apache, and a management instance with cloudwatch alarms and s3 backups

# Included
mgmt subnet with public internet access for SSH into environment
app subnets in separate AZs
backend subnet

# Load balancing
ALB port 80 forwarding to EC2/apache

# Compute
2x minimum, 6x maximum t2.micro RHEL latest EC2 instances

# Routing
mgmt: SSH (22) allowed only from a trusted IP (9.9.9.9)
app: HTTP (80) allowed only from load balancer, SSH only from mgmt subnet
backend: private (no internet access)

# Requirements
terraform CLI: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli
AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html
S3 restore: https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects.html

# Suggstions or optimizations
recommend HTTPS for web traffic with valid cert
scale back or disable auto-scaling before understanding baseline load
instance sizing is a concern, but not here with micro instances
risks with current AZ would be an outage/degradation if an AZ is not available or not available to a specific acccount
only basic visibility into app performance, added cloudwatch alarms for CPU, memory, disk, and HTTP 4xx (current product I support would desire this)
9.9.9.9 is a placeholder and will need to be updated to reflect actual management IP
added backup jobs

# Deployment
requires EC2 key pair
requires AWS CLI access/secret
terraform init
terraform validate
terraform plan
terraform apply

# Validation
terminal (from management): curl http://instance.url
ssh (from management): ssh -i Key.pem Terraform@instance.IP
browser: http://instance.url

# Research/resources
https://registry.terraform.io/providers/hashicorp/aws/latest/docs
https://github.com/Coalfire-CF/terraform-aws-account-setup
https://github.com/alfonsof/terraform-aws-examples