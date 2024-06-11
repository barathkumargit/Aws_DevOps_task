terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}  


# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Create public and private subnets
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}

# Create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# Attach internet gateway to VPC
resource "aws_internet_gateway_attachment" "gw_attach" {
  vpc_id       = aws_vpc.main.id
  internet_gateway_id = aws_internet_gateway.gw.id
}

# Create route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Create security groups
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  name   = "web_sg"

  ingress {
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

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id
  name   = "db_sg"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
}

# Create EC2 instances
resource "aws_instance" "web_instance" {
  ami             = "ami-05e00961530ae1b55"
  instance_type   = "t2.medium"
  subnet_id       = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.web_sg.name]

  tags = {
    Name = "Web Instance"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y python3-pip",
      "sudo pip3 install Flask==2.0.1 Werkzeug==2.0.1 Jinja2==3.0.1",
      "sudo systemctl start flask"
    ]
  }
    
  }
  

resource "aws_instance" "db_instance" {
  ami             = "ami-05e00961530ae1b55"
  instance_type   = "t2.medium"
  subnet_id       = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.db_sg.name]

  tags = {
    Name = "DB Instance"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y postgresql",
      "sudo systemctl start postgresql"
    ]
  }
}

# Data sources to fetch the existing VPC and subnets
data "aws_vpc" "existing_vpc" {
  id = "vpc-0567368cb70ce41d4"  # Replace with your VPC ID
}
data "aws_subnets" "existing_subnets" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.main.id]
  }
}


# Create Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "Allow HTTP traffic"
  vpc_id = aws_vpc.main.id
  ingress {
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

resource "aws_lb" "main" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.private_subnet.id]  

  enable_deletion_protection = false

  idle_timeout = 60
}

# Create ALB target group
resource "aws_lb_target_group" "main" {
  name        = "my-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# Create ALB listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Create a Route 53 DNS record
resource "aws_route53_zone" "main" {
  name = "awstask.com"  # Replace with your domain name
}

resource "aws_route53_record" "main" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "alb.awstask.com"  # Replace with your desired subdomain
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}


# Create bastion host (assuming only SSH access is allowed)
resource "aws_instance" "bastion_host" {
  ami           = "ami-05e00961530ae1b55"
  instance_type = "t2.medium"
  subnet_id     = aws_subnet.public_subnet.id
  key_name      = "Keypair-ap-south-1"
  associate_public_ip_address = true

  tags = {
    Name = "Bastion Host"
  }
}

# Output the IP addresses of instances for convenience
output "web_instance_ip" {
  value = aws_instance.web_instance.private_ip
}

output "db_instance_ip" {
  value = aws_instance.db_instance.private_ip
}
