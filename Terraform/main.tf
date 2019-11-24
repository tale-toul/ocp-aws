#REFERENCE DOCUMENTATION
#https://access.redhat.com/documentation/en-us/reference_architectures/2018/html/deploying_and_managing_openshift_3.9_on_amazon_web_services/red_hat_openshift_container_platform_prerequisites
#https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf

#PROVIDERS
#https://www.terraform.io/docs/configuration/providers.html#alias-multiple-provider-instances
#https://www.terraform.io/docs/providers/aws/index.html
provider "aws" {
  region = "eu-west-1"
  version = "~> 2.39"
  shared_credentials_file = "redhat-credentials.ini"
}

provider "aws" {
  alias = "dns"
  region = "eu-west-1"
  version = "~> 2.39"
  shared_credentials_file = "tale-credentials.ini"
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

#NAT GATEWAYS
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

resource "aws_security_group" "sg-ssh-out" {
    name = "ssh-out"
    description = "Allow outgoing ssh connections to the VPC network"
    vpc_id = aws_vpc.vpc.id

	egress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["172.20.0.0/16"]
    }

    tags = {
        Name = "sg-ssh-out"
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

#EC2s
resource "aws_instance" "tale_bastion" {
  ami = "ami-046dc942cb1d63621"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in.id,
			    aws_security_group.sg-ssh-out.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

  tags = {
        Name = "bastion"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_mas01" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "master01"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_mas02" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv2.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "master02"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_mas03" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv3.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "master03"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_infra01" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "infra01"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_infra02" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv2.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "infra02"
        Project = "OCP-CAM"
  }
}
resource "aws_instance" "tale_infra03" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv3.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "infra03"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_worker01" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv1.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "worker01"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_worker02" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv2.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "worker02"
        Project = "OCP-CAM"
  }
}

resource "aws_instance" "tale_worker03" {
  ami = "ami-046dc942cb1d63621"
#  instance_type = "m4.large"
  instance_type = "t2.small"
  subnet_id = aws_subnet.subnet_priv3.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in-local.id,
			    aws_security_group.sg-web-out.id]
  key_name= "tale-toul"

#  root_block_device {
#      volume_size = 20
#      delete_on_termination = true
#  }

  tags = {
        Name = "worker03"
        Project = "OCP-CAM"
  }
}

#OUTPUT
output "bastion_public_ip" {  
 value       = aws_instance.tale_bastion.public_ip  
 description = "The public IP address of bastion server"
}

output "master01_ip" {
  value = aws_instance.tale_mas01.private_ip
  description = "The private IP address of master01"
}

output "master02_ip" {
  value = aws_instance.tale_mas02.private_ip
  description = "The private IP address of master02"
}

output "master03_ip" {
  value = aws_instance.tale_mas03.private_ip
  description = "The private IP address of master03"
}

output "infra01_ip" {
  value = aws_instance.tale_infra01.private_ip
  description = "The private IP address of infra01"
}
output "infra02_ip" {
  value = aws_instance.tale_infra02.private_ip
  description = "The private IP address of infra02"
}
output "infra03_ip" {
  value = aws_instance.tale_infra03.private_ip
  description = "The private IP address of infra03"
}
output "worker01_ip" {
  value = aws_instance.tale_worker01.private_ip
  description = "The private IP address of woker01"
}
output "worker03_ip" {
  value = aws_instance.tale_worker03.private_ip
  description = "The private IP address of woker02"
}
output "worker03_ip" {
  value = aws_instance.tale_worker03.private_ip
  description = "The private IP address of woker03"
}
