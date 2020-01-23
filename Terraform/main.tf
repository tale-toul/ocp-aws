#PROVIDERS
#https://www.terraform.io/docs/configuration/providers.html#alias-multiple-provider-instances
#https://www.terraform.io/docs/providers/aws/index.html
provider "aws" {
  region = var.region_name
  version = "~> 2.39"
  shared_credentials_file = "redhat-credentials.ini"
}

#This is only used to generate random values
provider "random" {
  version = "~> 2.2"
}

#VARIABLES
variable "region_name" {
  description = "AWS Region where the cluster is deployed"
  type = string
  default = "eu-west-1"
}

variable "cluster_name" {
  description = "Cluser name, used for prefixing some component names like the DNS domain"
  type = string
  default = "ocp"
}

variable "vpc_name" {
  description = "Name assigned to the VPC"
  type = string
  default = "volatil"
}

variable "dns_domain_ID" {
  description = "Zone ID for the route 53 DNS domain that will be used for this cluster"
  type = string
  default = "Z1UPG9G4YY4YK6"
}

#Not all instances types are available in all regions
#Depending on the instance type used, the device for the addtional disks use the name xvd<letter> (xvda) or nvme<number>n1 (nvme1n1)
variable "master-instance-type" {
  description = "Type of instance used for master nodes, define the hardware characteristics like memory, cpu, network capabilities"
  type = string
  default = "t3.xlarge"
}

variable "nodes-instance-type" {
  description = "Type of instance used for infra and worker nodes, define the hardware characteristics like memory, cpu, network capabilities"
  type = string
  default = "m4.xlarge"
}

variable "rhel7-ami" {
  description = "AMI on which the EC2 instances are based on, depends on the region"
  type = map
  default = {
    eu-central-1   = "ami-0b5edb134b768706c"
    eu-west-1      = "ami-0404b890c57861c2d"
    eu-west-2      = "ami-0fb2dd0b481d4dc1a"
    eu-west-3      = "ami-0dc7b4dac85c15019"
    eu-north-1     = "ami-030b10a31b2b6df19"
    us-east-1      = "ami-0e9678b77e3f7cc96"
    us-east-2      = "ami-0170fc126935d44c3"
    us-west-1      = "ami-0d821453063a3c9b1"
    us-west-2      = "ami-0c2dfd42fa1fbb52c"
    sa-east-1      = "ami-09de00221562b0155"
    ap-south-1     = "ami-0ec8900bf6d32e0a8"
    ap-northeast-1 = "ami-0b355f24363d9f357"
    ap-northeast-2 = "ami-0bd7fd9221135c533"
    ap-southeast-1 = "ami-097e78d10c4722996"
    ap-southeast-2 = "ami-0f7bc77e719f87581"
    ca-central-1   = "ami-056db5ae05fa26d11"
  }
}

variable "ssh-keyfile" {
  description = "Name of the file with public part of the SSH key to transfer to the EC2 instances"
  type = string
  default = "ocp-ssh.pub"
}

variable "ssh-keyname" {
  description = "Name of the key that will be imported into AWS"
  type = string
  default = "ssh-key"
}

variable "user-data-masters" {
  description = "User data for master instances"
  type = string
  default = <<-EOF
       #cloud-config
       cloud_config_modules:
       - disk_setup
       - mounts
       - cc_write_files

       write_files:
       - content: |
           STORAGE_DRIVER=overlay2
           DEVS=/dev/nvme1n1
           VG=dockervg
           CONTAINER_ROOT_LV_NAME=dockerlv
           CONTAINER_ROOT_LV_MOUNT_PATH=/var/lib/docker
           CONTAINER_ROOT_LV_SIZE=100%FREE
         path: "/etc/sysconfig/docker-storage-setup"
         permissions: "0644"
         owner: "root"

       fs_setup:
       - label: ocp_emptydir
         filesystem: xfs
         device: /dev/nvme2n1
         partition: auto
       - label: etcd
         filesystem: xfs
         device: /dev/nvme3n1
         partition: auto

       mounts:
       - [ "LABEL=ocp_emptydir", "/var/lib/origin/openshift.local.volumes", xfs, "defaults,gquota" ]
       - [ "LABEL=etcd", "/var/lib/etcd", xfs, "defaults,gquota" ]
  EOF
}

variable "user-data-nodes" {
  description = "User data for worker and infra nodes instances"
  type = string
  default = <<-EOF
       #cloud-config
       cloud_config_modules:
       - disk_setup
       - mounts
       - cc_write_files

       write_files:
       - content: |
           STORAGE_DRIVER=overlay2
           DEVS=/dev/xvdb
           VG=dockervg
           CONTAINER_ROOT_LV_NAME=dockerlv
           CONTAINER_ROOT_LV_MOUNT_PATH=/var/lib/docker
           CONTAINER_ROOT_LV_SIZE=100%FREE
         path: "/etc/sysconfig/docker-storage-setup"
         permissions: "0644"
         owner: "root"

       fs_setup:
       - label: ocp_emptydir
         filesystem: xfs
         device: /dev/xvdc
         partition: auto

       mounts:
       - [ "LABEL=ocp_emptydir", "/var/lib/origin/openshift.local.volumes", xfs, "defaults,gquota" ]
  EOF
}

#VPC
resource "aws_vpc" "vpc" {
    cidr_block = "172.20.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = var.vpc_name
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_vpc_dhcp_options" "vpc-options" {
  domain_name          = "${var.region_name}.compute.internal"
  domain_name_servers  = ["AmazonProvidedDNS"] 
}

resource "aws_vpc_dhcp_options_association" "vpc-association" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.vpc-options.id
}

#SUBNETS
data "aws_availability_zones" "avb-zones" {
  state = "available"
}

resource "aws_subnet" "subnet1" {
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[0]
    cidr_block = "172.20.1.0/24"
    map_public_ip_on_launch = true

    tags = {
        Name = "subnet1"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_subnet" "subnet2" {
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[1]
    cidr_block = "172.20.2.0/24"
    map_public_ip_on_launch = true

    tags = {
        Name = "subnet2"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_subnet" "subnet3" {
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[2]
    cidr_block = "172.20.3.0/24"
    map_public_ip_on_launch = true

    tags = {
        Name = "subnet3"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_subnet" "subnet_priv1" {
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[0]
    cidr_block = "172.20.10.0/24"
    map_public_ip_on_launch = false

    tags = {
        Name = "subnet_priv1"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_subnet" "subnet_priv2" {
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[1]
    cidr_block = "172.20.20.0/24"
    map_public_ip_on_launch = false

    tags = {
        Name = "subnet_priv2"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_subnet" "subnet_priv3" {
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[2]
    cidr_block = "172.20.30.0/24"
    map_public_ip_on_launch = false

    tags = {
        Name = "subnet_priv3"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "intergw" {
    vpc_id = aws_vpc.vpc.id

    tags = {
        Name = "intergw"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

#EIPS
resource "aws_eip" "nateip1" { 
    vpc = true
    tags = {
        Name = "nateip1"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_eip" "nateip2" { 
    vpc = true
    tags = {
        Name = "nateip2"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_eip" "nateip3" { 
    vpc = true
    tags = {
        Name = "nateip3"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_eip" "bastion_eip" {
    vpc = true
    instance = aws_instance.tale_bastion.id

    tags = {
        Name = "bastion_eip"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

#NAT GATEWAYs
resource "aws_nat_gateway" "natgw1" {
    allocation_id = aws_eip.nateip1.id
    subnet_id = aws_subnet.subnet1.id

    depends_on = [aws_internet_gateway.intergw]

    tags = {
        Name = "natgw1"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_nat_gateway" "natgw2" {
    allocation_id = aws_eip.nateip2.id
    subnet_id = aws_subnet.subnet2.id

    depends_on = [aws_internet_gateway.intergw]

    tags = {
        Name = "natgw2"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_nat_gateway" "natgw3" {
    allocation_id = aws_eip.nateip3.id
    subnet_id = aws_subnet.subnet3.id

    depends_on = [aws_internet_gateway.intergw]

    tags = {
        Name = "natgw3"
        Clusterid = var.cluster_name
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
        Project = "OCP-CAM"
    }
}

#Route table associations
resource "aws_route_table_association" "rtabasso_subnet1" {
    subnet_id = aws_subnet.subnet1.id
    route_table_id = aws_route_table.rtable_igw.id
}

resource "aws_route_table_association" "rtabasso_subnet2" {
    subnet_id = aws_subnet.subnet2.id
    route_table_id = aws_route_table.rtable_igw.id
}

resource "aws_route_table_association" "rtabasso_subnet3" {
    subnet_id = aws_subnet.subnet3.id
    route_table_id = aws_route_table.rtable_igw.id
}

#Route tables: Out bound Internet access for private networks
resource "aws_route_table" "rtable_priv1" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.natgw1.id
    }
    tags = {
        Name = "rtable_priv1"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_route_table" "rtable_priv2" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.natgw2.id
    }
    tags = {
        Name = "rtable_priv2"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

resource "aws_route_table" "rtable_priv3" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.natgw3.id
    }
    tags = {
        Name = "rtable_priv3"
        Clusterid = var.cluster_name
        Project = "OCP-CAM"
    }
}

#Route table associations 
resource "aws_route_table_association" "rtabasso_nat_priv1" {
    subnet_id = aws_subnet.subnet_priv1.id
    route_table_id = aws_route_table.rtable_priv1.id
}

resource "aws_route_table_association" "rtabasso_nat_priv2" {
    subnet_id = aws_subnet.subnet_priv2.id
    route_table_id = aws_route_table.rtable_priv2.id
}

resource "aws_route_table_association" "rtabasso_nat_priv3" {
    subnet_id = aws_subnet.subnet_priv3.id
    route_table_id = aws_route_table.rtable_priv3.id
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
  subnets            = [aws_subnet.subnet1.id,
                        aws_subnet.subnet2.id,
                        aws_subnet.subnet3.id]
  instances = [aws_instance.tale_mast01.id,
               aws_instance.tale_mast02.id,
               aws_instance.tale_mast03.id]

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
  subnets            = [aws_subnet.subnet_priv1.id,
                        aws_subnet.subnet_priv2.id,
                        aws_subnet.subnet_priv3.id]
  instances = [aws_instance.tale_mast01.id,
               aws_instance.tale_mast02.id,
               aws_instance.tale_mast03.id]

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
  subnets            = [aws_subnet.subnet1.id,
                        aws_subnet.subnet2.id,
                        aws_subnet.subnet3.id]
  instances = [aws_instance.tale_infra01.id,
               aws_instance.tale_infra02.id,
               aws_instance.tale_infra03.id]

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
    Project = "OCP-CAM"
  }
}

#EC2s
#SSH key
resource "aws_key_pair" "ssh-key" {
  key_name = var.ssh-keyname
  public_key = file("${path.module}/${var.ssh-keyfile}")
}

#Bastion host
resource "aws_instance" "tale_bastion" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = "t2.medium"
  subnet_id = aws_subnet.subnet1.id
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
        Project = "OCP-CAM"
  }
}

#Masters
resource "aws_instance" "tale_mast01" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.master-instance-type
  subnet_id = aws_subnet.subnet_priv1.id
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
        Name = "master01"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_mast02" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.master-instance-type
  subnet_id = aws_subnet.subnet_priv2.id
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
        Name = "master02"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_mast03" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.master-instance-type
  subnet_id = aws_subnet.subnet_priv3.id
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
        Name = "master03"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

#Infras
resource "aws_instance" "tale_infra01" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv1.id
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
        Name = "infra01"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_infra02" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv2.id
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
        Name = "infra02"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}
resource "aws_instance" "tale_infra03" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv3.id
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
        Name = "infra03"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

#Workers
resource "aws_instance" "tale_worker01" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv1.id
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
        Name = "worker01"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_worker02" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv2.id
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
        Name = "worker02"
        Clusterid = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_worker03" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv3.id
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
        Name = "worker03"
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
  name = "${var.cluster_name}ext.${data.aws_route53_zone.domain.name}"

  tags = {
    Name = "external"
    Clusterid = var.cluster_name
    Project = "OCP-CAM"
  }
}

resource "aws_route53_record" "external-ns" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = "${var.cluster_name}ext.${data.aws_route53_zone.domain.name}"
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
  name = "${var.cluster_name}int.${data.aws_route53_zone.domain.name}"

  vpc {
    vpc_id = aws_vpc.vpc.id
  }

  tags = {
    Name = "internal"
    Clusterid = var.cluster_name
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
  override_special = "-"
}

#Registry Bucket
resource "aws_s3_bucket" "registry-bucket" {
  bucket = random_string.bucket_name.result
  region = var.region_name
  force_destroy = true

  acl    = "private"

  tags = {
    Name  = "Registry bucket"
    Clusterid = var.cluster_name
    Project = "OCP-CAM"
  }
}

#IAM users
#Admin user for aws OpenShift plugin
resource "aws_iam_user" "iam-admin" {
  name = "iam-admin"

   tags = {
    Name = "iam-admin"
    Clusterid = var.cluster_name
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
  name = "iam-registry"

   tags = {
    Name = "iam-registry"
    Clusterid = var.cluster_name
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
output "master01_ip" {
  value = aws_instance.tale_mast01.private_ip
  description = "The private IP address of master01"
}
output "master01_name" {
  value = aws_instance.tale_mast01.private_dns
  description = "The private FQDN of master01"
}
output "master02_ip" {
  value = aws_instance.tale_mast02.private_ip
  description = "The private IP address of master02"
}
output "master02_name" {
  value = aws_instance.tale_mast02.private_dns
  description = "The private FQDN of master02"
}
output "master03_ip" {
  value = aws_instance.tale_mast03.private_ip
  description = "The private IP address of master03"
}
output "master03_name" {
  value = aws_instance.tale_mast03.private_dns
  description = "The private FQDN of master03"
}
output "infra01_ip" {
  value = aws_instance.tale_infra01.private_ip
  description = "The private IP address of infra01"
}
output "infra01_name" {
  value = aws_instance.tale_infra01.private_dns
  description = "The private FQDN of infra01"
}
output "infra02_ip" {
  value = aws_instance.tale_infra02.private_ip
  description = "The private IP address of infra02"
}
output "infra02_name" {
  value = aws_instance.tale_infra02.private_dns
  description = "The private FQDN of infra02"
}
output "infra03_ip" {
  value = aws_instance.tale_infra03.private_ip
  description = "The private IP address of infra03"
}
output "infra03_name" {
  value = aws_instance.tale_infra03.private_dns
  description = "The private FQDN of infra03"
}
output "worker01_ip" {
  value = aws_instance.tale_worker01.private_ip
  description = "The private IP address of woker01"
}
output "worker01_name" {
  value = aws_instance.tale_worker01.private_dns
  description = "The private FQDN of woker01"
}
output "worker02_ip" {
  value = aws_instance.tale_worker02.private_ip
  description = "The private IP address of woker02"
}
output "worker02_name" {
  value = aws_instance.tale_worker02.private_dns
  description = "The private FQDN of woker02"
}
output "worker03_ip" {
  value = aws_instance.tale_worker03.private_ip
  description = "The private IP address of woker03"
}
output "worker03_name" {
  value = aws_instance.tale_worker03.private_dns
  description = "The private FQDN of woker03"
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
  value = aws_iam_access_key.key-admin.secret
  description = "Secret key for the iam user admin"
}
output "iam_registry_key_id" {
  value = aws_iam_access_key.key-registry.id
  description = "ID of registry key"
}
output "iam_registry_key" {
  value = aws_iam_access_key.key-registry.secret
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
