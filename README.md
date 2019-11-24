## Openshift Installation on AWS

### Terraform

The Terraform directory contains the neccessary files to create the infrastructure required to install OCP in AWS

The architecture used is based on the one descrived in [this reference document](https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf) from Red Hat.

Two different aws providers are defined: 

* One for the majority of the resources created
* Other for the Route53 DNS name management

Six subnets are created to leverage the High Availavility provided by the Availability Zones in the region, 3 for public subnets, 3 for private subnets.

The EC2 VMs created in the private networks need access to the Internet to donwload packages and images, so 3 NAT gateways are created, one for every private subnet.

One Internet Gateway is created in the VPC to provide access from and to the Internet for the resources created in the public subnets. For this access to be enable, a single route table is created and associated to every public subnet.

A total of 10 EC2 instances are created:

* 1 bastion host deployed in one of the public subnets

* 3 master nodes, each one deployed in one private subnet hence in an availability zone.

* 3 infra nodes, each one deployed in one private subnet hence in an availability zone.

* 3 worker nodes, each one deployed in one private subnet hence in an availability zone.
