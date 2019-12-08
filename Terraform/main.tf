#PROVIDERS
#https://www.terraform.io/docs/configuration/providers.html#alias-multiple-provider-instances
#https://www.terraform.io/docs/providers/aws/index.html
provider "aws" {
  region = "eu-west-1"
  version = "~> 2.39"
  shared_credentials_file = "redhat-credentials.ini"
}

#VARIABLES
variable "cluster_name" {
  description = "Cluser name, used for prefixing some component names like the DNS domain"
  type = string
  default = "ocp"
}

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

    tags = {
        Name = "volatil"
        Project = "OCP-CAM"
    }
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
        Project = "OCP-CAM"
    }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "intergw" {
    vpc_id = aws_vpc.vpc.id

    tags = {
        Name = "intergw"
        Project = "OCP-CAM"
    }
}

#EIPS
resource "aws_eip" "nateip1" { 
    vpc = true
    tags = {
        Name = "nateip1"
        Project = "OCP-CAM"
    }
}

resource "aws_eip" "nateip2" { 
    vpc = true
    tags = {
        Name = "nateip2"
        Project = "OCP-CAM"
    }
}

resource "aws_eip" "nateip3" { 
    vpc = true
    tags = {
        Name = "nateip3"
        Project = "OCP-CAM"
    }
}

resource "aws_eip" "bastion_eip" {
    vpc = true
    instance = aws_instance.tale_bastion.id

    tags = {
        Name = "bastion_eip"
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
        Project = "OCP-CAM"
    }
}

resource "aws_nat_gateway" "natgw2" {
    allocation_id = aws_eip.nateip2.id
    subnet_id = aws_subnet.subnet2.id

    depends_on = [aws_internet_gateway.intergw]

    tags = {
        Name = "natgw2"
        Project = "OCP-CAM"
    }
}

resource "aws_nat_gateway" "natgw3" {
    allocation_id = aws_eip.nateip3.id
    subnet_id = aws_subnet.subnet3.id

    depends_on = [aws_internet_gateway.intergw]

    tags = {
        Name = "natgw3"
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
    Project = "OCP-CAM"
  }
}

#EC2s
#Bastion host
resource "aws_instance" "tale_bastion" {
  ami = "ami-0404b890c57861c2d"
  instance_type = "t2.medium"
  subnet_id = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"

  root_block_device {
      volume_size = 25
      delete_on_termination = true
  }

  tags = {
        Name = "bastion"
        Project = "OCP-CAM"
  }
}

#Masters
resource "aws_instance" "tale_mast01" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.master-instance-type
  subnet_id = aws_subnet.subnet_priv1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-master.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_mast02" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.master-instance-type
  subnet_id = aws_subnet.subnet_priv2.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-master.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_mast03" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.master-instance-type
  subnet_id = aws_subnet.subnet_priv3.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-master.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

#Infras
resource "aws_instance" "tale_infra01" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-web-in.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_infra02" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv2.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-web-in.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}
resource "aws_instance" "tale_infra03" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv3.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-web-in.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

#Workers
resource "aws_instance" "tale_worker01" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_worker02" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv2.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_worker03" {
  ami = "ami-0404b890c57861c2d"
  instance_type = var.nodes-instance-type
  subnet_id = aws_subnet.subnet_priv3.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
                            aws_security_group.sg-node.id,
                            aws_security_group.sg-all-out.id]
  key_name= "tale-toul"
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
        Project = "OCP-CAM"
  }
}

#ROUTE53 CONFIG

#Datasource for rhcee.support. route53 zone
data "aws_route53_zone" "rhcee" {
  zone_id = "Z1UPG9G4YY4YK6"
}


#External hosted zone, this is a public zone because it is not associated with a VPC
resource "aws_route53_zone" "external" {
  name = "${var.cluster_name}ext.rhcee.support."

  tags = {
    Name = "external"
    Project = "OCP-CAM"
  }
}

resource "aws_route53_record" "external-ns" {
  zone_id = data.aws_route53_zone.rhcee.zone_id
  name    = "${var.cluster_name}ext.rhcee.support."
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
  name = "${var.cluster_name}int.rhcee.support."

  vpc {
    vpc_id = aws_vpc.vpc.id
  }

  tags = {
    Name = "internal"
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
  description = "The DNS name of the public load balancer in front of masters"
}
