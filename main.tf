provider "aws" {
    region = "us-east-1"
  } # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
  
  data "aws_caller_identity" "current" {} # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
  
  data "aws_ami" "rhel" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
    most_recent = true
    owners      = ["309956199498"] # Red Hat
    filter {
      name   = "name"
      values = ["RHEL-8.*_HVM-*"]
    }
  }
  
  resource "aws_vpc" "main" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
    cidr_block           = "10.1.0.0/16"
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags = { Name = "main-vpc" }
  }
  
  resource "aws_internet_gateway" "igw" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
    vpc_id = aws_vpc.main.id
  }
  
  resource "aws_subnet" "app_subnet_az1" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.1.1.0/24"
    availability_zone       = "us-east-1a"
    map_public_ip_on_launch = false
    tags = { Name = "app-subnet-az1" }
  }
  
  resource "aws_subnet" "app_subnet_az2" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.1.2.0/24"
    availability_zone       = "us-east-1b"
    map_public_ip_on_launch = false
    tags = { Name = "app-subnet-az2" }
  }
  
  resource "aws_subnet" "mgmt_subnet" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.1.3.0/24"
    availability_zone       = "us-east-1a"
    map_public_ip_on_launch = true
    tags = { Name = "mgmt-subnet" }
  }
  
  resource "aws_subnet" "backend_subnet" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.1.4.0/24"
    availability_zone       = "us-east-1b"
    map_public_ip_on_launch = false
    tags = { Name = "backend-subnet" }
  }
  
  resource "aws_route_table" "public" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
    vpc_id = aws_vpc.main.id
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
    }
  }
  
  resource "aws_route_table_association" "mgmt_assoc" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
    subnet_id      = aws_subnet.mgmt_subnet.id
    route_table_id = aws_route_table.public.id
  }
  
  resource "aws_security_group" "app_sg" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
    name        = "app-sg"
    description = "Allow web from ALB and SSH from mgmt"
    vpc_id      = aws_vpc.main.id
    ingress {
      description = "Allow HTTP from ALB"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      security_groups = [aws_security_group.alb_sg.id]
    }
    ingress {
      description = "Allow SSH from mgmt instance"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      security_groups = [aws_security_group.mgmt_sg.id]
    }
    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  
  resource "aws_security_group" "mgmt_sg" {
    name        = "mgmt-sg"
    description = "Allow SSH from fixed IP"
    vpc_id      = aws_vpc.main.id
    ingress {
      description = "SSH from fixed IP"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["9.9.9.9/32"]
    }
    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  
  resource "aws_security_group" "alb_sg" {
    name        = "alb-sg"
    description = "Allow HTTP from internet"
    vpc_id      = aws_vpc.main.id
    ingress {
      description = "Allow HTTP"
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
  }
  
  resource "aws_lb" "app_lb" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
    name               = "app-lb"
    internal           = false
    load_balancer_type = "application"
    security_groups    = [aws_security_group.alb_sg.id]
    subnets            = [aws_subnet.app_subnet_az1.id, aws_subnet.app_subnet_az2.id]
  }
  
  resource "aws_lb_target_group" "app_tg" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
    name     = "app-tg"
    port     = 80
    protocol = "HTTP"
    vpc_id   = aws_vpc.main.id
    health_check {
      path                = "/"
      protocol            = "HTTP"
      matcher             = "200"
      interval            = 30
      timeout             = 5
      healthy_threshold   = 5
      unhealthy_threshold = 2
    }
  }
  
  resource "aws_lb_listener" "app_listener" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
    load_balancer_arn = aws_lb.app_lb.arn
    port              = 80
    protocol          = "HTTP"
    default_action {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app_tg.arn
    }
  }
  
  resource "aws_launch_template" "app_lt" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template
    name_prefix   = "app-template-"
    image_id      = data.aws_ami.rhel.id
    instance_type = "t2.micro"
    key_name      = "Key"
    vpc_security_group_ids = [aws_security_group.app_sg.id]
    user_data = <<-EOF
      #!/bin/bash
      yum update -y
      yum install -y httpd amazon-cloudwatch-agent
      systemctl enable httpd
      systemctl start httpd
      echo "Howdy, pilgrim." > /var/www/html/index.html
      cat <<EOC > /opt/aws/amazon-cloudwatch-agent/bin/config.json
      {
        "metrics": {
          "metrics_collected": {
            "mem": { "measurement": ["mem_used_percent"] },
            "disk": { "measurement": ["disk_used_percent"], "resources": ["*"] }
          }
        }
      }
      EOC
      /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
    EOF
  }
  
  resource "aws_autoscaling_group" "app_asg" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
    desired_capacity     = 2
    max_size             = 6
    min_size             = 2
    vpc_zone_identifier  = [aws_subnet.app_subnet_az1.id, aws_subnet.app_subnet_az2.id]
    target_group_arns    = [aws_lb_target_group.app_tg.arn]
    health_check_type    = "EC2"
    launch_template {
      id      = aws_launch_template.app_lt.id
      version = "$Latest"
    }
  }
  
  resource "aws_instance" "mgmt" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
    ami                         = data.aws_ami.rhel.id
    instance_type               = "t2.micro"
    subnet_id                   = aws_subnet.mgmt_subnet.id
    vpc_security_group_ids      = [aws_security_group.mgmt_sg.id]
    associate_public_ip_address = true
    key_name                    = "Key"
    tags = { Name = "mgmt-instance" }
  }
  
  resource "aws_cloudwatch_metric_alarm" "cpu_high" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
    alarm_name          = "HighCPUUtilization"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 2
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = 300
    statistic           = "Average"
    threshold           = 80
    dimensions = { AutoScalingGroupName = aws_autoscaling_group.app_asg.name }
  }
  
  resource "aws_cloudwatch_metric_alarm" "memory_high" {
    alarm_name          = "HighMemoryUtilization"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 2
    metric_name         = "mem_used_percent"
    namespace           = "CWAgent"
    period              = 300
    statistic           = "Average"
    threshold           = 80
    dimensions = { AutoScalingGroupName = aws_autoscaling_group.app_asg.name }
  }
  
  resource "aws_cloudwatch_metric_alarm" "disk_high" {
    alarm_name          = "HighDiskUtilization"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 2
    metric_name         = "disk_used_percent"
    namespace           = "CWAgent"
    period              = 300
    statistic           = "Average"
    threshold           = 80
    dimensions = { AutoScalingGroupName = aws_autoscaling_group.app_asg.name }
  }
  
  resource "aws_cloudwatch_metric_alarm" "alb_4xx_high" {
    alarm_name          = "HighALB4xxErrors"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 2
    metric_name         = "HTTPCode_ELB_4XX_Count"
    namespace           = "AWS/ApplicationELB"
    period              = 300
    statistic           = "Sum"
    threshold           = 10
    dimensions = { LoadBalancer = aws_lb.app_lb.arn_suffix }
  }
  
  resource "aws_backup_vault" "default" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault
    name        = "aws-backup-default-vault"
  }
  
  resource "aws_backup_plan" "default" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan
    name = "aws-backup-default-plan"
    rule {
      rule_name         = "daily-backup"
      target_vault_name = aws_backup_vault.default.name
      schedule          = "cron(0 5 * * ? *)"
      lifecycle { delete_after = 30 }
    }
  }
  
  resource "aws_backup_selection" "ec2" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection
    iam_role_arn = aws_iam_role.backup_role.arn
    name         = "ec2-backup-selection"
    plan_id      = aws_backup_plan.default.id
    resources    = [aws_instance.mgmt.arn]
  }
  
  resource "aws_backup_selection" "asg" {
    iam_role_arn = aws_iam_role.backup_role.arn
    name         = "asg-backup-selection"
    plan_id      = aws_backup_plan.default.id
    resources = [
  "arn:aws:autoscaling:us-east-1:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${aws_autoscaling_group.app_asg.name}"
    ]
  }
  
  resource "aws_backup_selection" "s3" {
    iam_role_arn = aws_iam_role.backup_role.arn
    name         = "s3-backup-selection"
    plan_id      = aws_backup_plan.default.id
    resources = [
      "arn:aws:s3:::accesslogs",
      "arn:aws:s3:::elb-accesslogs",
      "arn:aws:s3:::backups",
      "arn:aws:s3:::installs",
      "arn:aws:s3:::cloudtrail",
      "arn:aws:s3:::config"
    ]
  }
  
  resource "aws_iam_role" "backup_role" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
    name = "AWSBackupDefaultRole"
    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{ Effect = "Allow", Principal = { Service = "backup.amazonaws.com" }, Action = "sts:AssumeRole" }]
    })
  }
  
  resource "aws_iam_role_policy_attachment" "backup_policy" { # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
    role       = aws_iam_role.backup_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  }
  
  output "alb_dns_name" { value = aws_lb.app_lb.dns_name }
  output "mgmt_public_ip" { value = aws_instance.mgmt.public_ip }
  output "success_message" { value = "I hope this worked... ALB: ${aws_lb.app_lb.dns_name} MGMT IP: ${aws_instance.mgmt.public_ip}" }  