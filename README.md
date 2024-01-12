# Openshift 3.11 installation on AWS

## Table of contents
* [Introduction](#introduction)

* [Terraform](#terraform)

  * [Variables](#variables)

  * [VPC](#vpc)

  * [EC2 instances](#ec2-instances)

  * [Security Groups](#security-groups)

  * [Elastic Load Balancers](#elastic-load-balancers)

  * [DNS Route 53](#dns-route-53)

  * [S3 bucket](#s3-bucket)

  * [IAM users](#iam-users)

  * [Component creation with loops](#component-creation-with-loops)

    * [Placing infras and workers](#placing-infras-and-workers)

* [Ansible](#ansible)

  * [SSH connection through the bastion host](#ssh-connection-through-the-bastion-host)

  * [Ansible configuration file](#ansible-configuration-file)

  * [Inventory files](#inventory-files)

  * [Prerequisites](#prerequisites)

  * [Tests](#tests)

  * [Storage management ](#storage-management )

* [Cluster deployment instructions](#cluster-deployment-instructions)

  * [Accessing the cluster](#accessing-the-cluster)

* [Cluster decommissioning instructions](#cluster-decommissioning-instructions)


## Introduction

The objective of this project is to simplify the deployment of an OpenShift 3.11 cluster on AWS and make it as automated and repeatable as possible, to accomplish this terraform is used to deploy the insfrastructure part, ansible is used to prepare the hosts and deploy the cluster.

The architecture is based on the following documentation by Red Hat:

[https://access.redhat.com/documentation/en-us/reference_architectures/2018/html/deploying_and_managing_openshift_3.9_on_amazon_web_services/red_hat_openshift_container_platform_prerequisites](https://access.redhat.com/documentation/en-us/reference_architectures/2018/html/deploying_and_managing_openshift_3.9_on_amazon_web_services/red_hat_openshift_container_platform_prerequisites)

[https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf](https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf)

The deployment consists of 3 main phases:

 * Infrastructure creation.- Through a terraform manifest, the infraestructure required to support the cluster is created in AWS.

 * Initial set up.- Through an ansible playbook, the node instances created in the previous step are set up so an OCP 3.11 cluster can be deployed in them

 * Cluster deployment.- Using the standar installation playbooks for OCP 3.11 the cluster is deployed.


## Terraform

The Terraform directory contains the neccessary files to create the infrastructure required to install an OCP 3.11 cluster in AWS.

The terraform manifest is designed to be run against a region with 3 availability zones, it does not work on regions with only 2 availability zones.

One provider is defined (https://www.terraform.io/docs/configuration/providers.html) to create the resources in AWS.  The credentials for the AWS user with privileges to create resources can be defined in a file containing the access key ID and the access key secret with the following format. Put this file in ~/.aws/credentials:

```
[default]
aws_access_key_id=xxxx
aws_secret_access_key=xxxx
```

Alternatively the environment variables **AWS_SECRET_ACCESS_KEY** and **AWS_ACCESS_KEY_ID** can be used 

A second provider is defined to generate random vales, like the name of the S3 bucket for the registry, that must be unique in all AWS.
 
Most of the resources created in AWS to deploy the OCP cluster require the tag named **Clusterid** with an identifier common to all elements. In this case the value of the tag is defined via a variable:

```
Clusterid = var.cluster_name
```
In addition to the tag Clusterid, the EC2 instances also require the following tag, the tag name includes the value used for Clusterid, and the value can be owned or shared, depending on the cluster use, if it is only for OCP we use owned, if the nodes have other uses we use shared:

```
"kubernetes.io/cluster/${var.cluster_name}" = "owned"
```

### Variables

Variables are defined in a separate file **input-vars.tf** to simplify the the configuration, it is enough to modify its values to change the configuration of the infrastructure deployed by terraform:

* **region_name**.- AWS region where the cluster is deployed

* **cluster_name**.- Indentifier used for prefixing some component names like the DNS domain

* **vpc_name**.- Name assigned to the VPC

* **dns_domain_ID**.- Zone ID for the route 53 base DNS domain used for this cluster

* **master-instance-type**.- Type of instance used for master nodes, define the hardware characteristics like memory, cpu, network capabilities

* **nodes-instance-type**.- Type of instance used for infra and worker nodes, define the hardware characteristics like memory, cpu, network capabilities

* **rhel7-ami**.- This map variable defines the AMI on which the EC2 instances are based on depending on the region. This AMI is based on a RHEL 7. See [EC2 instances](ec2-instances) for more details

* **ssh-keyfile**.- Name of the file with the public part of the SSH key to transfer to the EC2 instances. The key name is be generated by appending a random string of 5 characters to the name *ssh-key-*, this way the uniqueness of the name is guarrantied.

* **master_count**.- Number of master nodes in the OCP cluser, can only be 1 or 3

* **infra_count**.- Number of node instance to be used as infras in the OCP cluster

* **worker_count**.- Number of node instance to be used as workers in the OCP cluster

* **user-data-masters**.- User data for master instances, contains cloud config directives to setup disks and partitions.

* **user-data-nodes**.- User data for worker and infra nodes instances, contains cloud config directives to setup disks and partitions.

### VPC

A single VPC is created where all resources will be placed, it has DNS support enable for EC2 instances inside, distributed by the DHCP server.  

In most regions the domain used by the internal DNS server will be `<region_name>.compute.internal`, but for the region **us-east-1** it will be `ec2.internal`, the difference is due to the particular way the  **us-east-1** regions is treated in AWS.  The domain name assigned to the instances by DHCP is such that the internal DNS names match the names obtained inside the hosts with the command `hostname -f`.  To apply this particular case to the terraform configuration a conditional is used, the variable domain_name will receive the value ec2.internal only when region_name is equal to "us-east-1":

```
 resource "aws_vpc_dhcp_options" "vpc-options" {
  domain_name = var.region_name == "us-east-1" ? "ec2.internal" : "${var.region_name}.compute.internal" 
  ...
 }
```

Six subnets are created to leverage the High Availavility provided by the Availability Zones, 3 public and 3 private subnets.

An internet gateway is created and assigned to the VPC to provide access to and from the Internet.  For the EC2 instances in the public subnets to be able to use it, a route table is created with a default route pointing to the internet gateway, then an association is made between each public subnet and the route table.

3 NAT gateways are created and placed, one on each of the public subnets, they are used to provide access to the Inernet to the EC2 instances in the private subnets, this way those EC2 instances will be able to reach out and grab anything they need, for example to download images, while not being accesible themselves. An Elastic IP is created and assigned to each one of the NAT gateways.  For the EC2 instances in the private networks to be able to use the NAT gateways, 3 route tables are created with a default route pointing to one of the NAT gateways, then an association is made between one private subnet and the corresponding route table; in the end there will be a route table associated to each private subnet pointing to one of the NAT gateways.

An endpoint to access the S3 API is created, this will increase security and performance since the S3 related traffic will not leave the AWS network

### EC2 instances

A total of 10 EC2 instances are created.  By default master and worker and bastion hosts have 4 vCPUs and 16GB of RAM:

* 1 bastion host deployed in one of the public subnets

* 3 master nodes, each one deployed in one private subnet hence in an availability zone. 

* 3 infra nodes, each one deployed in one private subnet hence in an availability zone.

* 3 worker nodes, each one deployed in one private subnet hence in an availability zone.

The bastion host is assigned an Elastic IP, and a corresponding DNS entry is created for that IP.  

The AWS ami used to deploy the hosts is based on RHEL 7.7.  To look for the AWS amis the following command can be used.  The aws CLI binary needs to be available, the authentication to AWS can be completed exporting the variables **AWS_ACCESS_KEY_ID** and **AWS_SECRET_ACCESS_KEY**:

```
$ export AWS_ACCESS_KEY_ID=xxxxxx
$ export AWS_SECRET_ACCESS_KEY=xxxxx
$ aws ec2 describe-images --owners 309956199498 --filters "Name=is-public,Values=true" "Name=name,Values=RHEL*7.7*" --region eu-west-1
```
The command searches for **public** amis in the eu-west-1 (Ireland) region with owner Red Hat (309956199498) that include in the name the string "RHEL*7.7*".  The output will contain a list of amis released at different dates and with minor differences among them.

The terraform file uses a variable of type map to keep the correct ami IDs for each region, so it should not be necessary to look for the AMI.

According to the [OpenShift installation documentation](https://docs.openshift.com/container-platform/3.11/install/prerequisites.html#hardware) a minimum available disk space is required in the partitions containing specific directories, also docker and OpenShift require available space to store ephemeral data and images, and in the case of the masters a separate disk is recommended to hold the data for etcd.  To comply with the previous requirements the root disk for the nodes is sized accordingly and additinal disks are added to the each master, infra and worker instance.  The additional disks are formated and mounted via a user data script that is passed to the instance during creation, one of the disks is used to create a volume group and logical volume to be used by docker.  It is important to take into consideration that the naming scheme for the devices created for the additional disks depends on the type of instance used; for example t3.xlarge will use devices like /devnvme1n1, while m4.xlarge will use /dev/xvdb

An SSH key pair is created so the public part can be distributed to the EC2 instances and ssh access is posible. The key pair can be created in the AWS web interface or using a commnad like:

```
$ ssh-keygen -o -t rsa -f ocp-ssh -N ""
```
The previous command generates 2 files: ocp-ssh with the private part of the key, and ocp-ssh.pub with the public part of the key.  The private part is not protected by a passphrase (-N "")

An SSH key pair resource is created based on the ssh key created in the previous step. The name of the key must be unique in The AWS account, with that porpuse the name is made of the string "**ssh-key-**" followed by a random string of 5 characters.

The EC2 VMs created in the private networks need access to the Internet to donwload packages and images, so 3 NAT gateways are created, one for every private subnet.

One Internet Gateway is created in the VPC to provide access from and to the Internet for the resources created in the public subnets. For this access to be enable, a single route table is created and associated to every public subnet.

### Security Groups

The EC2 instances need the right security group assigned depending on the particular role of the instace.

According to Terraform [documentation](https://www.terraform.io/docs/providers/aws/r/security_group.html):
By default, AWS creates an ALLOW ALL egress rule when creating a new Security Group inside of a VPC. Terraform will remove this default rule, and require you specifically re-create it if you desire that rule. We feel this leads to fewer surprises in terms of controlling your egress rules. If you desire this rule to be in place, you can use this egress block:

```
resource "aws_security_group" "sg-all-out" {
...
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
```
This _allow-all-out_ security group is assigned to most of the EC2 instances and load balancers.

A few security groups need to be created, the ports that need to be accessable along the type of host that need to access them are described in the documentation [here](https://docs.openshift.com/container-platform/3.11/install/prerequisites.html#required-ports) and [here](https://access.redhat.com/documentation/en-us/reference_architectures/2018/html/deploying_and_managing_openshift_3.9_on_amazon_web_services/red_hat_openshift_container_platform_prerequisites)

To add the same security group that is being created as a source security group the option **self = true** muste be used, then any instance wich gets assigned the security group will be able to access the ports to of any other instance with the same security group assigned:

```
resource "aws_security_group" "sg-master" {
...
     ingress {
        from_port = 2379
        to_port = 2380
        protocol = "tcp"
        self = true
    }
```
The other options to define the source that can use the ingress rule are:

* A network CIDR address.  Any request coming from that network will be allowed:

```
     ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
     }
```
* Another security group.  In this case any request coming from an instance that has assigned any of the security groups will be allowed:

```
    ingress {
        from_port = 2379
        to_port = 2380
        protocol = "tcp"
        security_groups = [aws_security_group.sg-node.id]
    }
```

### Elastic Load Balancers

[Terraform documentations](https://www.terraform.io/docs/providers/aws/r/lb.html)

Three load balancers are created: 

* An ELB in front of the masters accepting requests from the Internet, providing access to the API.  This load balancer will accept requests on ports 443 and 8444.

* An ELB in front of the masters, internal, not accessible from the Internet, accepting requests from other components of the cluser and providing access to the API.  This load balancer accepts requests on port 443.

* An ELB in front of the infra nodes that contain the router pods (HAProxy), accepting requests from the Internet, providing access to the application router.  This load balancer accepts requests on ports 80 and 443.

The load balancers are of type **aws_elb**.- This _classic_ load balancer allows the use of security groups, does not need an x509 certificate to terminate the SSL/TLS connections; allows the definition of a TCP port to listen to and to forward the requests to the EC2 instances downstream.  The subnets where the load balancer will be placed, listening for requests is also defined, along the instances that will receive the requests. Cross zone load balanzing will be enable because the VMs being access are in differente availability zones. The load balancer will be internal or not depending on who will be using it.  Finally a health check against the EC2 instances is defined to verify if they can accept requests.

### DNS Route 53

Two DNS zones are created to resolve the names of components in the cluster: one external to be accessible from the Internet, and one internal to be only accessible from inside the cluster.  Both zones are created under the zone defined in the variable **dns_domain_ID** (rhce.support by default), this variable expects a zone ID.  Both zones use the same name, but they don't collide because one is private and the other public, the public zone is the one not explicitly associated with a VPC.
A few records have been created so far.

* In the external zone:

  * bastion
  * master.- for the external load balancer
  * *.apps.- wildcard record for the applications 

* In the internal zone 

  * master.- for the internal load balancer
  * *.apps.- for the applications domain
  
### S3 bucket

An S3 bucket is created to be used as backend storage for the internal OpenShift image registry.  It is created in the same region as the rest of the resources, this is controlled through the variable **region_name**.  

The name of the bucket must be unique across the whole AWS infrastructure, so a **random_string** resource is defined to generate names of lengh 20 character, the characters will be only lowercase letters and numbers:

```
resource "random_string" "bucket_name" {
  length = 20
  upper = false
  special = false
}
```
Later during the bucket definition the random name is generated `bucket = random_string.bucket_name.result`.  In other parts of the terraform manifest the same name is referenced with `${aws_s3_bucket.registry-bucket.id}`

Terraform will not generate a new random string if we run the **terraform apply** command a second time when a previous S3 bucket has been created, so the S3 bucket will not be recreated.

By default the non empty S3 buckets are not deleted by the command **terraform destroy**, this behaviour has been changed with the use of the argument **force_destroy = true** which forces terraform to destroy the S3 bucket even if this is not empty.

### IAM users

Two IAM users are created to be used by the installation playbooks, and later by the cluster itself.  The policy definitions assigned to them are created as "here" documents, it is **important** that the opening and closing curly brackets are placed on column 1 of the document, otherwise a malformed JSON error happens when running "terraform apply" command.  The name of the users must be unique in the organization, so a random 5 character suffix is added by a random string provider:

```
resource "random_string" "sufix_name" {
  length = 5
  upper = false
  special = false
}

 resource "aws_iam_user" "iam-admin" {
  name = "iam-admin-${random_string.sufix_name.result}"
  ...
 
 resource "aws_iam_user" "iam-registry" {
  name = "iam-registry-${random_string.sufix_name.result}"
  ...
```

* The first one (iam-admin) is to be associated with the EC2 instances and has a policy that allows it to operate on the EC2 instances and load balancers. The id and key of this user is assigned to the following variables in the inventory file used to deploy the cluster: **openshift_cloudprovider_aws_access_key**; **openshift_cloudprovider_aws_secret_key**

* The second one (iam-registry) has a policy that allows it to manage the S3 bucket that is also created as part of this terraform definition.

In the output section there are entries to print the access key ID and access key secret of these two IAM users, this information should be considered restricted.

### Component creation with loops

Many of the components in the infrastructure are comprised of more than one instance to add high availability and possibly load balancing to the cluster, this is the case of the availability zones, subnets, nat gateways, master infra and worker instances, etc.  In all cases the instances of these components are similar so it is possible to use a loop to create them instead of using a definition block for each one; with the use of loops the terraform manifest is more compact an aesier to maintain.  In the case of the infra and worker instances the number is controlled by variables (**infra_count**, **worker_count**) with a default value of 3, but they can be modified by the user to create the desired amount of infra and worker nodes.

Other components, like the subnets, are fixed to a number of 3, to refelec the number of availability zones in most of the regions.  

The loop to create the components is controlled by the internal variable **count** that contains the number of instances to be created, this variable contains an atribute **count.index**, that gets assigned the number of the instance being created as the loop progresses, this index can be used to reference other components with the same index.  In the following example 3 subnets are created, called subnet_pub.0, subnet_pub.1, subnet_put.2, each one of them will be assosiated with the corresponding availability zone in the region, extracted from the list **avb-zones.names** in the same index position.  The tag **Name** is also asigned a name that contains the index of the element in the loop.
```
resource "aws_subnet" "subnet_pub" {
    count = 3
    ...
    availability_zone = data.aws_availability_zones.avb-zones.names[count.index]
    tags = {
        Name = "subnet_pub.${count.index}"
    ...
    }
}
```

The **count.index** variable when used within a string is called with the expression **${count.index}**; when called as part of a list index uses the format [count.index], as seen in the example above.

When a particular resource is created using a loop, the result is a list, in the previous example the reosource **aws_subnet.subnet_pub** is a list of subnets; if a reference to all the elements of that list is required, a _splat_ reference is used:

```
subnets = aws_subnet.subnet_pub[*].id
```

This is equivalent to 

```
subnets = aws_subnet.subnet_pub[0].id, aws_subnet.subnet_pub[1].id, aws_subnet.subnet_pub[2].id
```

Master nodes are a special case of loop creation, only two values are permited for the variable controlling the loop (**master_count**), either 1 or 3.  This variable has a default value of 3, alternatively admits the value 1, any other value will default back to 3 masters.  Even when the value assigned is 1, the variable will still be a list:

```
resource "aws_instance" "master" {
  count = var.master_count == 1 || var.master_count == 3 ? var.master_count : 3
...
```

When resources are created with loops, the output variables will accordingly accept and show list:

```
output "infras_ip" {
   value = aws_instance.infra[*].private_ip
```

This requires a special approach in the proccessing of the output when used by the [create_inventario.sh](#inventory-files) script


#### Placing infras and workers

When there is not a 1 to 1 match between the number of instances to be assigned to another resource, for example the number of nodes is different from the number of subnets to place them in, the **element** function can be used; this function accepts a list and a number, and extracts from the list the element in the index position referenced by the number, if the number is greater than the maximum index position it is wrapped around and starts at the beggining of the list, for example if the number is 4 in a 3 element list, the returnded element by the function will be the one at position 2, consider that indexes start counting at 0.
```
resource "aws_instance" "infra" {
   count = var.infra_count
   ...
   subnet_id = element(aws_subnet.subnet_priv[*].id,count.index)

```

With the use of the element function the instances will be evenly spread across the subnets in the region.

## Ansible

An ansible playbook is used to prepare the hosts before actually running the official cluster deployment playbooks.

### SSH connection through the bastion host

Before running any ansible playbooks against the nodes in the cluster, first ssh must be configured so that a connection to the hosts in the private subnetworks can be stablished. A configuration file **ssh.cfg** is created from a jinja2 template (ssh.cfg.j2), containing a block with the connection parameters for the bastion host, and a block for the connection to the rest of the hosts in the VPC.  The template is rendered in the prereqs-ocp.yml ansible playbook, using variables from the terraform output variables.

```
Host bastion.ocpext.rhcee.support 
  user                    ec2-user
  StrictHostKeyChecking   no
  ProxyCommand            none
  CheckHostIP             no
  ForwardAgent            yes
  IdentityFile            ./tale-toul.pem
```

To connect to the bastion host the name **bastion.ocpext.rhcee.support** must be used so the configuration block is applied.  This configuration defines the FQDN of the host to connect to; the remote user to connect as; remote host's key will not be checked; no proxy command is used; key checking is against hostname rather than IP; ssh connection forwarding is enabled so a key managed by ssh agent can be used from this host to connect to another one; the file with the key used to connect to the remote host is defined to be on the same directory where the ssh command is run from.

The command used to connect to the bastion host would be.

```
$ ssh -F ssh.cfg bastion.taletoul.com
```

To connect to other hosts in the VPC, which are in private networks and therefore not directly accesible, the following configuration block is defined:

```
Host *.eu-west-1.compute.internal
  StrictHostKeyChecking   no
  ProxyCommand            ssh ec2-user@bastion.ocpext.rhcee.support -W %h:%p
  user                    ec2-user
  IdentityFile            ./tale-toul.pem
```
The block applies to all hosts in the DNS domain **eu-west-1.compute.internal**; remote key checking is disabled; a proxy command is defined so when connecting to a host is this network this command is run instead; the remote user to connect as is defined; the file with the key used to connect to the remote host is defined to be on the same directory where the ssh command is run from.

To connect to a host in a private subnet the key file must be added to the ssh agent, and then the connection can be established:

```
$ ssh-agent bash
$ ssh-add tale-toul.pem
$ ssh -F ssh.cfg ip-172-20-20-220.eu-west-1.compute.internal
```

To apply this configuration to ansible the following block is added to ansible.cfg:

```
[ssh_connection]
ssh_args = -F ./ssh.cfg
```

When ansible is run for the first time after the hosts have been created, the remote keys need to be accepted, even when using the option **host_key_checking=False** not to be bothered with that key validation.  When an indirect connection is stablished to the hosts in the private subnets the key validation happens both at the bastion host and at the final host, but ansible doesn't seem to be prepared for two question and the play hangs on the second question until a connection timeout is reached.

To avoid this problem we have to make sure that a connection to the bastion host is stablished before going to any other host in the private subnets, for that reason we have to make sure that we run a play against the bastion host before running any other plays against the hosts in the private networks.

### Ansible configuration file

An **ansible.cfg** configuration file is created with the following contents:

```
[defaults]
inventory=inventario
host_key_checking=False
log_path = ansible.log
callback_whitelist = profile_tasks, timer
any_errors_fatal = True
timeout = 30
forks=10
gathering = smart

[privilege_escalation]
become=true
become_user=root
become_method=sudo

[ssh_connection]
ssh_args = -F ./ssh.cfg -C -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
```
In the **default** section:
inventory=inventario.- The default inventory file that ansible will look for is called **inventario**
host_key_checking=False.- No ssh key checking for the remote host will be performed
log_path = ansible.log.- The default log file for ansible will be **ansible.log**
callback_whitelist = profile_tasks, timer.- Time marks will be shown along the playbook execution
any_errors_fatal = True.- Any error in any task will cause the whole playbook to stop after the failing task.
timeout = 30.- Time out for the ssh connections.
forks=10.- Up to 10 host can run any task in parrallel.
gathering=smart.- Facts will only be collected for nodes that have not been yet been contacted.

In the **privilege_escalation** section:
All tasks will be run via sudo as root

In the **ssh_connection** section:
The ssh connections will use a specific configuration file, plus additional options that are usually included as default configuration in ansible.
pipelining=True.- SSH connections will be reused by subsequent tasks.

### Inventory files

Two different inventory files are used during the cluster deployment:

* A simple inventory file that is used by the **prereqs-ocp.yml**, basically containing the list of all hosts in the cluster, including the bastion host, grouped by the sections that will be used later in the deploy cluster inventory file. This inventory file is generated by the script **Ansible/create_inventario.sh** which gathers the data from the terraform output.  This inventory file must be recreated every time a new infrastructure is created with terraform.  

When using [loops](#component-creation-with-loops) in terraform to create the instances, the list of hostnames is saved in an array ignoring lines with square brackets and removing quotes and commas, later the contents of the array are printed. 

```
for host in $(terraform output -state=$TERRAFORM_STATE masters_name|egrep -v -e '\[' -e '\]'|sed -e 's/"//g' -e 's/,//g'); do
  masters+=($host)
done
...
for x in ${masters[@]}; do
  echo " $x"
done
```
* A complete inventory file used by the deploy_cluster.yml playbook.  This inventory file is created by the **prereqs-ocp.yml** playbook from two different sources: 

  * A jinja2 template containing the sections **[OSEv3:children]** and **[OSEv3:vars]**.  The variables used in the templated are populated from the data generated by the `terraform output` command, and are updated every time new infrastructure is generate by terraform. 

  * The host groups section that is created and added at the end of the first inventory part, also in the **prereqs-ocp.yml** playbook.

  The resulting inventory file should be reviewed and possibly modified before running the cluster deployment playbooks.

#### Router and Registry configuration

By default the deploy playbook will not verify that the applications router and internal image registry in the default project have started successfully, this may lead to an apparently successful cluster deployment with a malfunctioning router and image registry, which in turn makes the whole cluster useless.  To avoid this situation the following variables are used in the inventory file: openshift_hosted_router_wait; openshift_hosted_registry_wait.  These variables make the playbook stop and wait for complete deployment of the router and registry, if the deployment is successful the playbook will continue with the following tasks, otherwise it will fail and stop.

OCP v3.11 uses an older version of the AWS SDK, which means that it is not aware of newer AWS regions like eu-north-1, so if the cluster is deployed in this region the image registry will fail when the pod starts and tries to connect to the S3 bucket, with the error messsage "panic: Invalid region provided: eu-north-1".  The workaround for new regions is to provide the s3 endpoint directly in the ansible inventory via the [`openshift_hosted_registry_storage_s3_regionendpoint` parameter](https://docs.openshift.com/container-platform/3.11/install/configuring_inventory_file.html#advanced-install-registry-storage). For eu-north-1 this would be https://s3.eu-north-1.amazonaws.com, see the list [here](https://docs.aws.amazon.com/general/latest/gr/rande.html)

The inventory template uses an _if_ block to determine if the special endpoint must be used or not:

```
{% if region_name == "eu-north-1" %}
openshift_hosted_registry_storage_s3_regionendpoint=https://s3.eu-north-1.amazonaws.com

{% endif %}
```

### Prerequisites

A playbook is created to set up the hosts in the cluster before running the actual deployment playbook.  The playbook is called **prereqs-ocp.yml**.

In the first play **"Local actions for localhost"** the following tasks are performed in localhost:

 * Remove any stale ssh keys in the user's known_hosts file that belonged to previous EC2 instances with the same hostname as the ones created by the last terraform run.

 * Create a file with variables from terraform output, and loads them into ansible. 

 * Create the ssh config file from a jinja2 template.  This config file will be used by the rest of the playbook to connect to the remote hosts.

 * Create the inventory file to be used by the deploy cluster playbooks later.  This file is created in two stages: from a jinja2 template and from a script.

The next play **First access to bastion host** is run against the bastion host, this makes sure that the bastion is accessed before any of the other hosts in the private networks

The next play **Prerequisites for OCP cluster members** contains several tasks:

* Find and Disable any repo file not manage by the subscription manager
 
* Register nodes with Red Hat

* Enable the repositories needed to install Openshift.  It has been updated to use the now supported ansible verion 2.8 which dramatically reduces the time required to complete the playbooks, and the fast-datapath has been removed since it is not required anymore.

* Update operating system packages, only when the **update_packages** variable has been defined as true, the default value is false.

The username and password required to register the hosts with Red Hat are encrypted in a vault file.  the playbook must be run providing the password to unencrypt that file, for example by storing the password in a file and using the command:

```
$ ansible-playbook --vault-id vault_id.txt prereqs-ocp.yml
```

The next two plays: **Check and set for additional storage for all nodes** and **Check and set for etcd specific storage on masters** take care make sure masters and nodes in the cluster are setup following the [storage recommendations for OpenShift 3.11](https://docs.openshift.com/container-platform/3.11/install/prerequisites.html#prerequisites-storage-management).  See the [Storage management section](#storage-management) later in this document.

The next play **Set up bastion host** prepares the bastion host to run the official OpenShift deployment playbooks, by installing some packages and copying some required files. 

### Tests

A directory called _tests_ inside the Ansible directory is created to hold test playbooks to verify that the infrastructure works as expected:

Before running any of these playbooks the prereqs-ocp.yml playbook must be run.

* **http-test.yaml**.- This playbooks is run agains the nodes group but only applies to those with the variable openshift_node_group_name defined and either with value node-config-master or node-config-infra; installs an httpd server; copies a configuration file to set up an SSL virtual host using a locally generated self signed x509 certificate, with document root at **/var/www/html**. A very simple index.html is added to the Document root containing the hostname of the node so when the connection is tested we know which node we hit, an additional copy of the file with name healthz is created to make the health check of the AWS load balancers happy.  As a final step the httpd service is restarted.  Once the playbook is run, we can use a command like the following to access the web servers through the external load balancer:

'`` 
$ while true; do curl -k https://elb-master-public-697013167.eu-west-1.elb.amazonaws.com/; sleep 1; done
'`` 

* **docker-test.yaml**.- This playbook is run against all nodes, including the bastion, install docker packages, starts the docker service, and runs a container.  

### Storage management 

The [OpenShift documentation](https://docs.openshift.com/container-platform/3.11/install/prerequisites.html#prerequisites-storage-management) recommends minimums for available storage in some partitions in the cluster host members.  To fulfill these recommendations a two step process is followed:

* The first step is performed in terraform:

 * The definition of the EC2 instances in terraform add additional disks to the hosts: 3 for the masters; 2 for the nodes.
 
 * A user-data script is defined, one for the masters and another for the rest of the nodes.  Here the additional disks previously added are setup to be used for the partitions **/var/lib/origin/openshift.local.volumes** in all nodes; **/var/lib/etcd** in the masters.  Also in all nodes the file defining the docker storage setup is created **/etc/sysconfig/docker-storage-setup**, this file references one of the additional disks as a backend for the docker storage.  Unfortunately the device names used in the user-data script may not match the actual device names in the EC2 instances, this happens because different instance types use different naming conventions for the disk device names, this can lead to situation in which the hosts created by terraform have the additional disks but these are not configured as backend storage as expected.

* The second step is performed in ansible.  The **prereqs-ocp.yml** playbook contains two plays that verify and correct the storage setup in the hosts: **Check and set for additional storage for all nodes**; **Check and set for etcd specific storage on masters**.  
  The plays start by verifying that the directories are mountpoints.  Errors are ignored to avoid the playbook to stop in case the directory is not a mountpoint; the result is saved in a variable:

```
        - name: Check for /var/lib/origin/openshift.local.volumes
          command: mountpoint /var/lib/origin/openshift.local.volumes
          ignore_errors: True
          register: point_local_results
```
  Next a list of task is grouped as a block to be run on the hosts for which the directory was not a mountpoint, which means that the user-data script could not properly configure the disk. These tasks look for the right device name to use; create the filesystem in the device; mount it, and finally check again that the directory is a mount point, but this time errors are not ignored so the playbook will fail if the mountpoint does not exists.

  Next the disk device used as backend storage for docker is updated in the **/etc/sysconfig/docker-storage-setup** by looking for the right device name and assigning it to a variable, then updating the line starting with **DEVS=** in the configuration filei. These tasks are always run, without previously verifying if the configuration is already correct, but ansible will actually not change the configuration file if this is already correct.  

## Cluster deployment instructions

[Terraform](https://www.terraform.io/) and [Ansible](https://www.ansible.com/) must be installed in the host where the installation will be run from; an [AWS](https://aws.amazon.com/) account is needed to create the infrastructure elements; A [Red Hat](https://access.redhat.com) user account with entitlements for installing OpenShift is required. 

* Create a credentials file for the Terraform provider as defined in the main.tf file, see the [Terraform section](#terraform) of this document.

* Create an SSH key pair with the following command and copy it to the terraform directory, the terraform configuration expects the output files to be called ocp-ssh and ocp-ssh.pub by default, but the name can be changed via the terraform variable *ssh-keyfile*:

```
$ ssh-keygen -o -t rsa -f ocp-ssh -N ""
```

* The default identity provider is an htpassword file, this file must be created and populated with entries, the prerequisites playbook and the ansible inventory used to deploy the cluster expect this file to be at **Ansible/files/htpasswd.openshift**, for example:

```
$ htpasswd -cb htpasswd.openshift user1 user1_password
$ for x in {1..5}; do htpasswd -b htpasswd.openshift user${x} user${x}_password; done
```
* The ansible task **Register server with Red Hat** references a pool id to subscribe the host to. To get the correct pool id use a command like: 
```
$ sudo subscription-manager list --available --all
```

* Create an ansible vault file with the following secret variables, and place it in the directory *Ansible/group_vars/all*.  The name of the file does not matter:

  * **subscription_username**; **subscription_password**.- Username and password of the Red Hat user with the entitlements to subscribe nodes with Red Hat
  * **oreg_auth_user**; **oreg_auth_password**.- Username and password of the user with access to the Red Hat container registry. Go [here](https://access.redhat.com/terms-based-registry/) to get or create a user account.  

 An example file would look like:

```
---
subscription_username: mariekondo
subscription_password: i3r@assP
oreg_auth_user: 1970546|aws-test
oreg_auth_password: eyJhbGciOiJSUzUxMiJ9.eyJzdWIiOiJlZmQyZDY....UE7x9h7-ZJjj3zn5KS1O7b1hTra-hwjb
...
```
  To encrypt the file with ansible vault use a command like:

```
$ ansible-vault encrypt linux_vars.txt
```


* Many terraform variables are defined and can be used to modify several aspects of the infraestructure deployment, some of these variables need to be modified to avoid collitions with other cluster previously deployed using this same terraform file. Review these variables and assign values where needed, in particular:

  * **region_name**.- The AWS region to deploy the infrastructure on, by default the region is **eu-west-1** (Ireland ).  For example  `-var="region_name=eu-central-1"`

  * **cluster_name**.- The prefix name for the cluster, by default it is **ocp**.  For example `-var="cluster_name=prodocp"`
   
  * **vpc_name**.- The name for the VPC, by default the name is "volatil"

  * **ssh-keyfile**.- The name of the file containing the ssh key, created with the ssh-keygen command; and the name of the ssh key that will be used to reference it in AWS.

  * **master_count**; **infra_count**; **worker_count**.- Number of master (1 or 3), infra and worker nodes.

* Terraform needs to be initialize, only the first time it is used, for that use the following command in the terraform directory:

```
$ terraform init
```

* Deploy the infrastructure by running a **terraform apply** command in the Terraform directory.  In the following example the cluster name, region, AMI, node instance type, ssh key file name are selected:

```
$ terraform apply -var="cluster_name=athena" -var="region_name=eu-west-3" -var="nodes-instance-type=t2.xlarge" -var="ssh-keyfile=test-ssh.pub" 
```

* Save the value of the variables used in this step becasuse the same values will be required in case of destroying the infrastructure with **terrafor destroy** command.  In the example the use of !! assumes that no other command has been executed after _terraform apply_:

```
echo "!!" > terraform_apply.txt
```

* Create an inventory file to run the prereqs-ocp.yml playbook.  This inventory file is not the one used to deploy the OCP cluster, that one will be created during the prereqs-ocp.yml playbook execution:

```
$ cd ../Ansible
$ ./create_inventario.sh > inventory-prereq
```
* Add the ssh private key to the ssh agent ring.  If ssh-agent is not running, start it first with:

```
$ ssh-agent bash
```

Add the key with:

```
$ ssh-add <path-to-private-key-file>
```

* Run the prerequisites (prereqs-ocp.yml ) playbook using the inventory file created in the previous step. If the OS packages in the nodes are going to be updated, the variable **update_packages** must be set to true, and the nodes must be rebooted after the playbook completes.

```
$ ansible-playbook  -i inventory-prereq --vault-id vault_id prereqs-ocp.yml 
```

* Ssh into the bastion host and review the inventory file and correct/modify as required, in particular.
```
$ ssh-agent bash
$ ssh-add <path-to-private-key-file>

$ ssh -F ssh.cfg bastion.ocpext.example.com
bastion$ cd OCP311
bastion$ vim inventario
```
  * The version installed is 3.11.latest, if another z version is wanted, the following variables must be defined: **openshift_image_tag**; **openshift_pkg_version**

  * The DNS subdomain name for the applications deployed in the cluster, this is defined in the variable **openshift_master_default_subdomain**

* Run the prerequisites and deploy cluster openshift playbook:

```
bastion$ ansible-playbook -vvv /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml
bastion$ ansible-playbook -vvv /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml
```

### Accessing the cluster

The hostname that must be used to access the cluster is the one assigned to the public load balancer in front of the masters, this name can be obtained from the variable **openshift_master_cluster_public_hostname** in the inventory file, or the output variable **master_public_lb** in terraform:

```
$ cd Terraform
$ terraform output master_public_lb
```
The URL to access the cluster web console is `https://<openshift_master_cluster_public_hostname>`, for example:

```
https://master.ocpext.rhcee.support
```

To login to the cluster with the **oc** command use `oc login -u <user> https://<openshift_master_cluster_public_hostname>`, for example:

```
$ oc login -u user1 https://master.ocpext.rhcee.support
```

The users created using the htpasswd identity provider don't have any special privileges, those are just developer level users.  To access the cluster with cluster admin privileges follow these steps:

* Ssh into one of the master nodes.  Any oc command run from a master is authenticated as cluster admin
```
$ ssh ip-172-20-10-137.eu-west-1.compute.internal
```
* Asign the cluster admin role to one of the users created with the httpaswd identity provider
```
$ oc adm policy add-cluster-role-to-user cluster-admin user1
cluster role "cluster-admin" added: "user1"
```
* Log out of the master node and authenticate with the "user1" user
```
oc login -u user1 https://master.ocp.sandbox2171.opentlc.com
```

## Cluster decommissioning instructions

To delete the cluster and **all** its components, including the data stored in the S3 and ELB disks, use the `terraform destroy` command.  This command should include the same variable definitions used during cluster creation, not all variables are strictly requiered though:

```
$ cd Terraform
$ terraform destroy -var="cluster_name=athena" -var="region_name=eu-west-3" -var="nodes-instance-type=t2.xlarge" -var="ssh-keyfile=test-ssh.pub" 
```

**WARNING** 

Terraform will only delete the resources it created, if other resources were added off band to the cluster, terraform will not have any knowledge about those and will not delete them.  An example of this can be new nodes added to extend the cluster.  One particular type of resource that will likely be added to the cluster without terraform intervention is the EBS disks created when a PV or PVC is requested by the defalt storage class created during cluster deployment (gp2); These disks need to be destroyed by the cluster administrator in the AWS console, for example looking for the tag **kubernetes.io/cluster/${CLUSTER_NAME}**.
