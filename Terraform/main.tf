#PROVIDERS
#https://www.terraform.io/docs/configuration/providers.html#alias-multiple-provider-instances
#https://www.terraform.io/docs/providers/aws/index.html
provider "aws" {
  region = var.region_name
}

#This is only used to generate random values
provider "random" {
}

#VPC
resource "aws_vpc" "vpc" {
    cidr_block = "172.20.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = var.vpc_name
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

resource "aws_vpc_dhcp_options" "vpc-options" {
  domain_name = var.region_name == "us-east-1" ? "ec2.internal" : "${var.region_name}.compute.internal" 
  domain_name_servers  = ["AmazonProvidedDNS"] 

  tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_vpc_dhcp_options_association" "vpc-association" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.vpc-options.id
}

#SUBNETS
data "aws_availability_zones" "avb-zones" {
  state = "available"
}

#Public subnets
resource "aws_subnet" "subnet_pub" {
    count = 3
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[count.index]
    cidr_block = "172.20.5${count.index}.0/24"
    map_public_ip_on_launch = true

    tags = {
        Name = "subnet_pub.${count.index}"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

#Private subnets
resource "aws_subnet" "subnet_priv" {
  count = 3
  vpc_id = aws_vpc.vpc.id
  availability_zone = data.aws_availability_zones.avb-zones.names[count.index]
  cidr_block = "172.20.1${count.index}.0/24"
  map_public_ip_on_launch = false

  tags = {
      Name = "subnet_priv.${count.index}"
      Clusterid = var.cluster_name
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      Project = "OCP-CAM"
  }
}

#ENDPOINTS
#S3 endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.region_name}.s3"
  route_table_ids = concat(aws_route_table.rtable_priv[*].id, [aws_route_table.rtable_igw.id]) 
  vpc_endpoint_type = "Gateway"

  tags = {
      Clusterid = var.cluster_name
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      Project = "OCP-CAM"
  }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "intergw" {
    vpc_id = aws_vpc.vpc.id

    tags = {
        Name = "intergw"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

#EIPS
resource "aws_eip" "nateip" {
  count = 3
  vpc = true
  tags = {
      Name = "nateip.${count.index}"
      Clusterid = var.cluster_name
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      Project = "OCP-CAM"
  }
}

resource "aws_eip" "bastion_eip" {
    vpc = true
    instance = aws_instance.tale_bastion.id

    tags = {
        Name = "bastion_eip"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

#NAT GATEWAYs
resource "aws_nat_gateway" "natgw" {
    count = 3
    allocation_id = aws_eip.nateip[count.index].id
    subnet_id = aws_subnet.subnet_pub[count.index].id
    depends_on = [aws_internet_gateway.intergw]

    tags = {
        Name = "natgw.${count.index}"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

#ROUTE TABLES
#Route table: Internet Gateway access for public subnets
resource "aws_route_table" "rtable_igw" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.intergw.id
    }
    tags = {
        Name = "rtable_igw"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

#Route table associations
resource "aws_route_table_association" "rtabasso_subnet_pub" {
    count = 3
    subnet_id = aws_subnet.subnet_pub[count.index].id
    route_table_id = aws_route_table.rtable_igw.id
}

#Route tables: Out bound Internet access for private networks
resource "aws_route_table" "rtable_priv" {
    count = 3
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.natgw[count.index].id
    }
    tags = {
        Name = "rtable_priv.${count.index}"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

#Route table associations 
resource "aws_route_table_association" "rtabasso_nat_priv" {
    count = 3
    subnet_id = aws_subnet.subnet_priv[count.index].id
    route_table_id = aws_route_table.rtable_priv[count.index].id
}

#SECURITY GROUPS
resource "aws_security_group" "sg-ssh-in" {
    name = "ssh-in"
    description = "Allow ssh connections"
    vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "sg-ssh"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

resource "aws_security_group" "sg-all-out" {
    name = "all-out"
    description = "Allow all outgoing traffic"
    vpc_id = aws_vpc.vpc.id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "all-out"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

resource "aws_security_group" "sg-ssh-in-local" {
    name = "ssh-in-local"
    description = "Allow ssh connections from same VPC"
    vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["172.20.0.0/16"]
    }

    tags = {
        Name = "sg-ssh-local"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

resource "aws_security_group" "sg-web-in" {
    name = "web-in"
    description = "Allow http and https inbound connections from anywhere"
    vpc_id = aws_vpc.vpc.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "sg-web-in"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

resource "aws_security_group" "sg-master" {
    name = "master"
    description = "Opens the ports required by the master nodes"
    vpc_id = aws_vpc.vpc.id

    ingress {
        from_port = 2379
        to_port = 2380
        protocol = "tcp"
        self = true
    }

    ingress {
        from_port = 2379
        to_port = 2380
        protocol = "tcp"
        security_groups = [aws_security_group.sg-node.id]
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 8444
        to_port = 8444
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "sg-master"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

resource "aws_security_group" "sg-node" {
    name = "node"
    description = "Opens the ports required by any node, including masters and infras"
    vpc_id = aws_vpc.vpc.id

    ingress {
        from_port = 53
        to_port = 53
        protocol = "tcp"
        self = true
    }
    ingress {
        from_port = 53
        to_port = 53
        protocol = "udp"
        self = true
    }
    ingress {
        from_port = 2049
        to_port = 2049
        protocol = "tcp"
        self = true
    }
    ingress {
        from_port = 8053
        to_port = 8053
        protocol = "tcp"
        self = true
    }
    ingress {
        from_port = 10250
        to_port = 10250
        protocol = "tcp"
        self = true
    }
    ingress {
        from_port = 4789
        to_port = 4789
        protocol = "udp"
        self = true
    }
    ingress {
        from_port = 8053
        to_port = 8053
        protocol = "udp"
        self = true
    }
    tags = {
        Name = "sg-node"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

resource "aws_security_group" "sg-web-out" {
    name = "web-out"
    description = "Allow http and https outgoing connections"
    vpc_id = aws_vpc.vpc.id

  egress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    tags = {
        Name = "sg-web-out"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
    }
}

#ELBs
resource "aws_elb" "elb-master-public" {
  name               = "elb-master-public"
  internal           = false
  cross_zone_load_balancing = true
  connection_draining = false
  security_groups    = [aws_security_group.sg-master.id,
                        aws_security_group.sg-all-out.id]
  subnets            = aws_subnet.subnet_pub[*].id
  instances = aws_instance.master[*].id 

  listener {
      instance_port     = 443
      instance_protocol = "tcp"
      lb_port           = 443
      lb_protocol       = "tcp"
    }

  listener {
      instance_port     = 8444
      instance_protocol = "tcp"
      lb_port           = 8444
      lb_protocol       = "tcp"
    }

  health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 5
      target              = "HTTPS:8444/healthz"
      interval            = 30
    }

  tags = {
    Name = "lb-master-public"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

resource "aws_elb" "elb-master-private" {
  name               = "elb-master-private"
  internal           = true
  cross_zone_load_balancing = true
  connection_draining = false
  security_groups    = [aws_security_group.sg-master.id,
                        aws_security_group.sg-all-out.id]
  subnets            = aws_subnet.subnet_priv[*].id
  instances = aws_instance.master[*].id

  listener {
      instance_port     = 443
      instance_protocol = "tcp"
      lb_port           = 443
      lb_protocol       = "tcp"
    }

  health_check {
      healthy_threshold   = 3
      unhealthy_threshold = 2
      timeout             = 3
      target              = "HTTPS:443/api"
      interval            = 10
    }

  tags = {
    Name = "lb-master-private"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

resource "aws_elb" "elb-infra-public" {
  name               = "elb-infra-public"
  internal           = false
  cross_zone_load_balancing = true
  connection_draining = false
  security_groups    = [aws_security_group.sg-web-in.id,
                        aws_security_group.sg-all-out.id]
  subnets            = aws_subnet.subnet_pub[*].id
  instances = aws_instance.infra[*].id

  listener {
      instance_port     = 80
      instance_protocol = "tcp"
      lb_port           = 80
      lb_protocol       = "tcp"
    }

  listener {
      instance_port     = 443
      instance_protocol = "tcp"
      lb_port           = 443
      lb_protocol       = "tcp"
    }

  health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 2
      target              = "TCP:443"
      interval            = 5
    }

  tags = {
    Name = "lb-infra-public"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

#EC2s
#SSH key
resource "aws_key_pair" "ssh-key" {
  key_name = "ssh-key-${random_string.sufix_name.result}"
  public_key = file("${path.module}/${var.ssh-keyfile}")
}

#Bastion host
resource "aws_instance" "tale_bastion" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_pub.0.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in.id,
                            aws_security_group.sg-all-out.id]
  key_name= aws_key_pair.ssh-key.key_name

  root_block_device {
      volume_size = 25
      delete_on_termination = true
  }

  tags = {
        Name = "bastion"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

#Masters
resource "aws_instance" "master" {
#If master_count is 1 or 3, count gets that value, otherwise it gets 3.  Only 1 or 3 are allowed values
  count = var.master_count == 1 || var.master_count == 3 ? var.master_count : 3
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.master-instance-type
  subnet_id = aws_subnet.subnet_priv[count.index].id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-master.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= aws_key_pair.ssh-key.key_name
  user_data = var.user-data-masters 

  root_block_device {
      volume_size = 60
      delete_on_termination = true
  }
  ebs_block_device {
      device_name = "/dev/xvdb"
      volume_size = 80
      delete_on_termination = true
  }
  ebs_block_device {
      device_name = "/dev/xvdc"
      volume_size = 80
      delete_on_termination = true
  }
  ebs_block_device {
      device_name = "/dev/xvdd"
      volume_size = 80
      delete_on_termination = true
  }

  tags = {
        Name = "master.${count.index}"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

#Infras
resource "aws_instance" "infra" {
  count = var.infra_count
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = element(aws_subnet.subnet_priv[*].id,count.index)
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-web-in.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= aws_key_pair.ssh-key.key_name
  user_data = var.user-data-nodes

  root_block_device {
      volume_size = 30
      delete_on_termination = true
  }
  ebs_block_device {
      device_name = "/dev/xvdb"
      volume_size = 80
      delete_on_termination = true
  }
  ebs_block_device {
      device_name = "/dev/xvdc"
      volume_size = 80
      delete_on_termination = true
  }

  tags = {
        Name = "infra.${count.index}"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

#Workers
resource "aws_instance" "worker" {
  count = var.worker_count
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = element(aws_subnet.subnet_priv[*].id,count.index)
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= aws_key_pair.ssh-key.key_name
  user_data = var.user-data-nodes

  root_block_device {
      volume_size = 30
      delete_on_termination = true
  }
  ebs_block_device {
      device_name = "/dev/xvdb"
      volume_size = 80
      delete_on_termination = true
  }
  ebs_block_device {
      device_name = "/dev/xvdc"
      volume_size = 80
      delete_on_termination = true
  }

  tags = {
        Name = "worker.${count.index}"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

#ROUTE53 CONFIG
#Datasource for rhcee.support. route53 zone
data "aws_route53_zone" "domain" {
  zone_id = var.dns_domain_ID
}

#External hosted zone, this is a public zone because it is not associated with a VPC
resource "aws_route53_zone" "external" {
  name = "${var.cluster_name}.${data.aws_route53_zone.domain.name}"

  tags = {
    Name = "external"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

#Creates the pointer from the base domain to the external cluster domain
resource "aws_route53_record" "external-ns" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = "${var.cluster_name}.${data.aws_route53_zone.domain.name}"
  type    = "NS"
  ttl     = "30"

  records = [
    "${aws_route53_zone.external.name_servers.0}",
    "${aws_route53_zone.external.name_servers.1}",
    "${aws_route53_zone.external.name_servers.2}",
    "${aws_route53_zone.external.name_servers.3}",
  ]
}

#Internal hosted zone, this is a private zone because it is associated with a VPC
resource "aws_route53_zone" "internal" {
  name = "${var.cluster_name}.${data.aws_route53_zone.domain.name}"

  vpc {
    vpc_id = aws_vpc.vpc.id
  }

  tags = {
    Name = "internal"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

resource "aws_route53_record" "bastion" {
    zone_id = aws_route53_zone.external.zone_id
    name = "bastion"
    type = "A"
    ttl = "300"
    records =[aws_eip.bastion_eip.public_ip]
}

resource "aws_route53_record" "master-ext" {
    zone_id = aws_route53_zone.external.zone_id
    name = "master"
    type = "CNAME"
    ttl = "300"
    records =[aws_elb.elb-master-public.dns_name]
} 

resource "aws_route53_record" "apps-domain" {
    zone_id = aws_route53_zone.external.zone_id
    name = "*.apps"
    type = "CNAME"
    ttl = "300"
    records = [aws_elb.elb-infra-public.dns_name]
}

resource "aws_route53_record" "apps-intdomain" {
    zone_id = aws_route53_zone.internal.zone_id
    name = "*.apps"
    type = "CNAME"
    ttl = "300"
    records = [aws_elb.elb-infra-public.dns_name]
}
resource "aws_route53_record" "master-int" {
    zone_id = aws_route53_zone.internal.zone_id
    name = "master"
    type = "CNAME"
    ttl = "300"
    records =[aws_elb.elb-master-private.dns_name]
}

#S3 BUCKETS

#Provides a source to create a random name for the S3 bucket
resource "random_string" "bucket_name" {
  length = 20
  upper = false
  special = false
}

#Registry Bucket
resource "aws_s3_bucket" "registry-bucket" {
  bucket = random_string.bucket_name.result
#  region = var.region_name
  force_destroy = true

  acl    = "private"

  tags = {
    Name  = "Registry bucket"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

#IAM users

#Provides a source to create a random sufix string for the IAM user names 
resource "random_string" "sufix_name" {
  length = 5
  upper = false
  special = false
}

#Admin user for aws OpenShift plugin
resource "aws_iam_user" "iam-admin" {
  name = "iam-admin-${random_string.sufix_name.result}"

   tags = {
    Name = "iam-admin"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

resource "aws_iam_access_key" "key-admin" {
  user    = aws_iam_user.iam-admin.name
}

resource "aws_iam_user_policy" "policy-admin" {
  name = "policy-admin"
  user = aws_iam_user.iam-admin.name

  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Action": [
               "ec2:DescribeVolume*",
               "ec2:CreateVolume",
               "ec2:CreateTags",
               "ec2:DescribeInstances",
               "ec2:AttachVolume",
               "ec2:DetachVolume",
               "ec2:DeleteVolume",
               "ec2:DescribeSubnets",
               "ec2:CreateSecurityGroup",
               "ec2:DescribeSecurityGroups",
               "ec2:DescribeRouteTables",
               "ec2:AuthorizeSecurityGroupIngress",
               "ec2:RevokeSecurityGroupIngress",
               "elasticloadbalancing:DescribeTags",
               "elasticloadbalancing:CreateLoadBalancerListeners",
               "elasticloadbalancing:ConfigureHealthCheck",
               "elasticloadbalancing:DeleteLoadBalancerListeners",
               "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
               "elasticloadbalancing:DescribeLoadBalancers",
               "elasticloadbalancing:CreateLoadBalancer",
               "elasticloadbalancing:DeleteLoadBalancer",
               "elasticloadbalancing:ModifyLoadBalancerAttributes",
               "elasticloadbalancing:DescribeLoadBalancerAttributes"
           ],
           "Resource": "*",
           "Effect": "Allow",
           "Sid": "1"
       }
   ]
}
 EOF
}

#Registry user for S3 bucket access
resource "aws_iam_user" "iam-registry" {
  name = "iam-registry-${random_string.sufix_name.result}"

   tags = {
    Name = "iam-registry"
    Clusterid = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Project = "OCP-CAM"
  }
}

resource "aws_iam_access_key" "key-registry" {
  user    = aws_iam_user.iam-registry.name
}

resource "aws_iam_user_policy" "policy-registry" {
  name = "policy-registry"
  user = aws_iam_user.iam-registry.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": "arn:aws:s3:::${aws_s3_bucket.registry-bucket.id}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::${aws_s3_bucket.registry-bucket.id}/*"
    }
  ]
}
EOF
}

#OUTPUT
output "bastion_public_ip" {  
 value       = aws_instance.tale_bastion.public_ip  
 description = "The public IP address of bastion server"
}
output "bastion_dns_name" {
  value = aws_route53_record.bastion.fqdn
  description = "DNS name for bastion host"
}
output "masters_ip" {
  value = aws_instance.master[*].private_ip
  description = "The private IP address of the master nodes"
}
output "masters_name" {
  value = aws_instance.master[*].private_dns
  description = "The private FQDN of the master nodes"
}
output "infras_ip" {
  value = aws_instance.infra[*].private_ip
  description = "The private IP address of the infra nodes"
}
output "infras_name" {
  value = aws_instance.infra[*].private_dns
  description = "The private FQDN of the infra nodes"
}
output "workers_ip" {
  value = aws_instance.worker[*].private_ip
  description = "The private IP address of the wokers nodes"
}
output "workers_name" {
  value = aws_instance.worker[*].private_dns
  description = "The private FQDN of the woker nodes"
}
output "master_public_lb" {
  value = aws_route53_record.master-ext.fqdn
  description = "The DNS name of the public load balancer in front of the masters"
}
output "master_internal_lb" {
  value = aws_route53_record.master-int.fqdn
  description = "The DNS name of the internal load balancer in front of the masters"
}
output "iam_admin_key_id" {
  value = aws_iam_access_key.key-admin.id
  description = "ID of admin key"
}
output "iam_admin_key" {
  value = nonsensitive(aws_iam_access_key.key-admin.secret)
  description = "Secret key for the iam user admin"
}
output "iam_registry_key_id" {
  value = aws_iam_access_key.key-registry.id
  description = "ID of registry key"
}
output "iam_registry_key" {
  value = nonsensitive(aws_iam_access_key.key-registry.secret)
  description = "Secret key for the iam user registry"
}
output "iam_admin_encrypted_key" {
  value = aws_iam_access_key.key-admin.encrypted_secret
  description = "Encrypted secret key for the iam user admin"
}
output "registry_s3_bucket" {
  value = aws_s3_bucket.registry-bucket.id
  description = "ARN value for the registry S3 bucket"
}
output "ssh_key" {
  value = "${path.module}/${var.ssh-keyfile}"
  description = "EC2 ssh key local file path"
}
output "ext_public_domain" {
  value = aws_route53_zone.external.name
  description="external DNS domain"
}
output "int_private_domain" {
  value = aws_route53_zone.internal.name
  description = " Internal private DNS domain"
}
output "cluster_name" {
 value = var.cluster_name
 description = "Cluser name, used for prefixing some component names like the DNS domain"
}
output "region_name" {
 value = var.region_name
 description = "AWS region where the cluster and its components will be deployed"
}
