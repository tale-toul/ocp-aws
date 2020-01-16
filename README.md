## Openshift 3.11 installation on AWS

### Reference documentation

https://access.redhat.com/documentation/en-us/reference_architectures/2018/html/deploying_and_managing_openshift_3.9_on_amazon_web_services/red_hat_openshift_container_platform_prerequisites

https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf

### Terraform

The Terraform directory contains the neccessary files to create the infrastructure required to install an OCP 3.11 cluster in AWS.

The architecture used is based on the one descrived in [this reference document](https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf) from Red Hat.

One provider is defined (https://www.terraform.io/docs/configuration/providers.html) to create the resources in AWS.  A credentials file containing the access key ID and the access key secret is created with the following format:

```
[default]
aws_access_key_id=xxxx
aws_secret_access_key=xxxx
```
and the provider definition contains the following directive referencing the credentials file:

```
  shared_credentials_file = "redhat-credentials.ini"
```

When using credentials files it is important to make sure that the environment variables **WS_SECRET_ACCESS_KEY** and **AWS_ACCESS_KEY_ID** are not defined in the session, otherwise extraneus errors will appear when running terraform.

Most of the resources created in AWS to deploy the OCP cluster require the tag named **Clusterid** with an identifier common to all elements. In this case the value of the tag is defined via a variable:

```
Clusterid = var.cluster_name
```
In addition to the tag Clusterid, the EC2 instances also require the following tag, the tag name includes the value used for Clusterid, and the value can be owned or shared, depending on the cluster use, if it is only for OCP we use owned, if the nodes have other uses we use shared:

```
"kubernetes.io/cluster/${var.cluster_name}" = "owned"
```

#### Variables

Variables are defined at the beginning of the file to simplify the rest of the configuration, it is enough to modify its values to change the configuration of the infrastructure deployed by terraform:

* **region_name**.- AWS region where the cluster is deployed

* **cluster_name**.- Indentifier used for prefixing some component names like the DNS domain

* **vpc_name**.- Name assigned to the VPC

* **dns_domain_ID**.- Zone ID for the route 53 DNS domain that will be used for this cluster

* **master-instance-type**.- Type of instance used for master nodes, define the hardware characteristics like memory, cpu, network capabilities

* **nodes-instance-type**.- Type of instance used for infra and worker nodes, define the hardware characteristics like memory, cpu, network capabilities

* **rhel7-ami**.- AMI on which the EC2 instances are based on, this one is a RHEL 7.7 in the Ireland region.  This variable is region dependent, if the value of variable **region_name** is modified, this one must be updated too.

* **ssh-keyfile**.- Name of the file with the public part of the SSH key to transfer to the EC2 instances

* **ssh-keyname**.- Name of the key that will be imported into AWS

* **registry-bucket-name**.- S3 registry bucket name

* **user-data-masters**.- User data for master instances, contains cloud config directives to setup disks and partitions.

* **user-data-nodes**.- User data for worker and infra nodes instances, contains cloud config directives to setup disks and partitions.

#### VPC

A single VPC is created where all resources will be placed, it has DNS support enable for the EC2 instances created inside, distributed by the DHCP server, and those instances will get a generated DNS name within the domain eu-west-1.compute.internal

Six subnets are created to leverage the High Availavility provided by the Availability Zones in the region, 3 public subnets and 3 private ones.

An internet gateway is created to provide access to and from the Internet.  For the EC2 instances in the public subnets to be able to use it, a route table is created with a default route pointing to the internet gateway, then an association is made between each public subnet and the route table.

3 NAT gateways are created and placed one on each of the public subnets, they are used to provide access to the Inernet to the EC2 instances in the private subnets, this way those EC2 instances will be able to access the ouside world, for example to download images, but the outside world will not be able to access the EC2 instances.  An Elastic IP is created and assigned to each one of the NAT gateways.  For the EC2 instances in the private networks to be able to use the NAT gateways, 3 route tables are created with a default route pointing to one of the NAT gateways, then an association is made between one private subnet and the corresponding route table; in the end there will be a route table associated to each private subnet pointing to one of the NAT gateways.

#### EC2 instances

A total of 10 EC2 instances are created.  Masters and workers have 4 vCPUs and 16GB of RAM, bastion host has 2 vCPUS and 4GB of RAM:

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

According to the [OpenShift installation documentation](https://docs.openshift.com/container-platform/3.11/install/prerequisites.html#hardware) a minimum available disk space is required in the partitions containing specific directories, also docker and OpenShift require available space to store ephemeral data and images, and in the case of the masters a separate disk is recommended to hold the data for etcd.  To comply with the previous requirements the root disk for the nodes is sized accordingly and additinal disks are added to the each master, infra and worker instance.  The additional disks are formated and mounted via a user data script that is passed to the instance during creation, one of the disks is used to create a volume group and logical volume to be used by docker.  It is important to take into consideration that the naming scheme for the devices created for the additional disks depends on the type of instance used; for example t3.xlarge will use devices like /devnvme1n1, while m4.xlarge will use /dev/xvdb

An SSH key pair is created so the public part can be distributed to the EC2 instances and ssh access is posible. The key pair can be created in the AWS web interface or using a commnad like:

```
$ ssh-keygen -o -t rsa -f ocp-ssh -N ""
```
The previous command generates 2 files: ocp-ssh with the private part of the key, and ocp-ssh.pub with the public part of the key.  The private part is not protected by a passphrase (-N "")

An SSH key pair resource is created based on the ssh key created in the previous step. The name of the key must be unique in The AWS account, to simplify the changing of this key name the variable **ssh-keyname** is defined.

The EC2 VMs created in the private networks need access to the Internet to donwload packages and images, so 3 NAT gateways are created, one for every private subnet.

One Internet Gateway is created in the VPC to provide access from and to the Internet for the resources created in the public subnets. For this access to be enable, a single route table is created and associated to every public subnet.

#### Security Groups

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

#### Elastic Load Balancers

[Terraform documentations](https://www.terraform.io/docs/providers/aws/r/lb.html)

Three load balancers are created: 

* An ELB in front of the masters accepting requests from the Internet.  This load balancer will accept requests on ports 443 and 8444.

* An ELB in front of the masters, internal, not accessible from the Internet, accepting requests from other components of the cluser.  This load balancer accepts requests on port 443.

* An ELB in front of the infra nodes that contain the router pods (HAProxy), accepting requests from the Internet.  This load balancer accepts requests on ports 80 and 443.

The load balancers are of type **aws_elb**.- This _classic_ load balancer allows the use of security groups, does not need an x509 certificate to terminate the SSL/TLS connections; allows the definition of a TCP port to listen to and to forward the requests to the EC2 instances downstream.  The subnets where the load balancer will be placed, listening for requests is also defined, along the instances that will receive the requests. Cross zone load balanzing will be enable because the VMs being access are in differente availability zones. The load balancer will be internal or not depending on who will be using it.  Finally a health check against the EC2 instances is defined to verify if they can accept requests.

#### DNS Route 53

Two DNS zones are created to resolve the names of components in the cluster: one external to be accessible from the Internet, and one internal to be only accessible from inside the cluster.  Both zones are created under **rhce.support** by default, but another domain can be selecte assigning a value to the variable **dns_domain_ID**, this variable expects a zone ID not a name.

A few records have been created so far.

* In the external zone:

  * bastion
  * master.- for the external load balancer
  * *.apps.- wildcard record for the applications 

* In the internal zone 

  * master.- for the internal load balancer
  * *.apps.- for the applications domain
  
#### S3 bucket

An S3 bucket is created to be used as backend storage for the internal OpenShift image registry.  It is recommended to create the bucket in the same region as the rest of the resources, this is controlled through the variable **region_name**.  The name of the bucket must be unique across the whole AWS infrastructure so the variable **registry-bucket-name** has been defined to make it easy to change this name in every deployment.

By default the non empty S3 buckets are not deleted by the command **terraform destroy**, this behaviour has been changed with the use of the argument **force_destroy = true** which forces terraform to destroy the S3 bucket even if this is not empty.

#### IAM users

Two IAM users are created to be used by the installation playbooks, and later by the cluster itself.  The policy definitions are created as "here" documents, it is **important** that the opening and closing curly brackets are placed on column 1 of the document, otherwise a malformed JSON error happens when running "terraform apply" command:

* The first one (iam-admin) is to be associated with the EC2 instances and has a policy that allows it to operate on the EC2 instances and load balancers. The id and key of this user is assigned to the following variables in the inventory file used to deploy the cluster: **openshift_cloudprovider_aws_access_key**; **openshift_cloudprovider_aws_secret_key**

* The second one (iam-registry) has a policy that allows it to manage the S3 bucket that is also created as part of this terraform definition.

In the output section there are entries to print the access key ID and access key secret of these two IAM users, this information should be considered restricted.

### Ansible

An ansible playbook is used to prepare the hosts before actually running the official cluster deployment playbooks.

#### SSH connection through the bastion host

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

#### Ansible configuration file

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

[privilege_escalation]
become=true
become_user=root
become_method=sudo

[ssh_connection]
ssh_args = -F ./ssh.cfg -C -o ControlMaster=auto -o ControlPersist=60s
```
In the **default** section:
inventory=inventario.- The default inventory file that ansible will look for is called **inventario**
host_key_checking=False.- No ssh key checking for the remote host will be performed
log_path = ansible.log.- The default log file for ansible will be **ansible.log**
callback_whitelist = profile_tasks, timer.- Time marks will be shown along the playbook execution
any_errors_fatal = True.- Any error in any task will cause the whole playbook to stop after the failing task.
timeout = 30.- Time out for the ssh connections.
forks=10.- Up to 10 host can run any task in parrallel.

In the **privilege_escalation** section:
All tasks will be run via sudo as root

In the **ssh_connection** section:
The ssh connections will use a specific configuration file, plus additional options that are usually included as default configuration in ansible.

#### Inventory files

Two different inventory files are used during the cluster deployment:

* A simple inventory file that is used by the **prereqs-ocp.yml**, basically containing the list of all hosts in the cluster, including the bastion host, grouped by the sections that will be used later in the deploy cluster inventory file. This inventory file is generated by the script **Ansible/create_inventario.sh** which gathers the data from the terraform output.  This inventory file must be recreated every time the infrastructure is created with terraform.

* A complete inventory file used by the deploy_cluster.yml playbook.  This inventory file is created by the **prereqs-ocp.yml** playbook from two different sources: 

  * A jinja2 template containing the sections **[OSEv3:children]** and **[OSEv3:vars]**, that is rendered in the **prereqs-ocp.yml** playbook. The variables used in the templated are populated from the data generated by the `terraform output` command, and are updated every time new infrastructure is generate by terraform. 

  * The host groups section that is created and added at the end of the first inventory part, also in the **prereqs-ocp.yml** playbook.

  The resulting inventory file should be reviewed and possibly modified before running the cluster deployment playbooks.

#### Prerequisites

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

* Enable the repositories needed to install Openshift.

* Update operating system packages, only when the **update_packages** variable has been defined as true, the default value is false.

The username and password required to register the hosts with Red Hat are encrypted in a vault file.  the playbook must be run providing the password to unencrypt that file, for example by storing the password in a file and using the command:

```
$ ansible-playbook --vault-id vault_id.txt prereqs-ocp.yml
```

The next two plays: **Check and set for additional storage for all nodes** and **Check and set for etcd specific storage on masters** take care make sure masters and nodes in the cluster are setup following the [storage recommendations for OpenShift 3.11](https://docs.openshift.com/container-platform/3.11/install/prerequisites.html#prerequisites-storage-management).  See the [Storage management section](#storage-management) later in this document.

The next play **Set up bastion host** prepares the bastion host to run the official OpenShift deployment playbooks, by installing some packages and copying some required files. 

#### Tests

A directory called _tests_ inside the Ansible directory is created to hold test playbooks to verify that the infrastructure works as expected:

Before running any of these playbooks the prereqs-ocp.yml playbook must be run.

* **http-test.yaml**.- This playbooks is run agains the nodes group but only applies to those with the variable openshift_node_group_name defined and either with value node-config-master or node-config-infra; installs an httpd server; copies a configuration file to set up an SSL virtual host using a locally generated self signed x509 certificate, with document root at **/var/www/html**. A very simple index.html is added to the Document root containing the hostname of the node so when the connection is tested we know which node we hit, an additional copy of the file with name healthz is created to make the health check of the AWS load balancers happy.  As a final step the httpd service is restarted.  Once the playbook is run, we can use a command like the following to access the web servers through the external load balancer:

'`` 
$ while true; do curl -k https://elb-master-public-697013167.eu-west-1.elb.amazonaws.com/; sleep 1; done
'`` 

* **docker-test.yaml**.- This playbook is run against all nodes, including the bastion, install docker packages, starts the docker service, and runs a container.  

#### Storage management 

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


### Cluster deployment instructions

[Terraform](https://www.terraform.io/) and [Ansible](https://www.ansible.com/) must be installed in the host where the installation will be run from; an [AWS](https://aws.amazon.com/) account is needed to create the infrastructure elements; A [Red Hat](https://access.redhat.com) user account with entitlements for installing OpenShift is required. 

* Create a credentials file for the Terraform provider in the Terraform direcotry, as defined in the main.tf file, see the [Terraform section](#terraform) of this document.

* Create an SSH key pair with the following command and copy it to the terraform directory, the terraform configuration expects the output files to be called ocp-ssh and ocp-ssh.pub by default, but the name can be changed via the terraform variable ssh-keyfile:

```
$ ssh-keygen -o -t rsa -f ocp-ssh -N ""
```

* The default identity provider is an htpassword file, this file must be created and filled with entries, the prerequisites playbook and the ansible inventory used to deploy the cluster expect this file to be at **Ansible/files/htpasswd.openshift**, for example:

```
$ htpasswd -cb htpasswd.openshift user1 user1_password
$ for x in {1..5}; do htpasswd -b htpasswd.openshift user${x} user${x}_password; done
```

* Create an ansible vault file with the following secret variables: 

  * **subscription_username**; **subscription_password**.- Username and password of the Red Hat user with the entitlements to subscribe nodes with Red Hat
  * **oreg_auth_user**; **oreg_auth_password**.- Username and password of the user with access to the Red Hat container registry. See [here](https://access.redhat.com/RegistryAuthentication) to learn how to get a user.

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

Place the resulting encrypted file in the directory Ansible/group_vars/all

* Many terraform variables are defined and can be used to modify several aspects of the infraestructure deployment, some of these variables need to be modified to avoid collitions with other cluster previously deployed using this same terraform file. Review these variables and assing values where needed, in particular:

  * **region_name**.- The AWS region to deploy the infrastructure on, by default the region is **eu-west-1** (Ireland ).  For example  `-var="region_name=eu-central-1"`

  * **cluster_name**.- The prefix name for the cluster, by default it is **ocp**.  For example `-var="cluster_name=prodocp"`
   
  * **vpc_name**.- The name for the VPC, by default the name is "volatil"

  * **rhel7-ami**.- The AMI to be used as base OS for the EC2 instances, by default this is a RHEL 7.7 in the Ireland region, if the region is changed, this value must also be changed accordingly, see the [EC2 instances section for details](#ec2-instances).  For example `-var="rhel7-ami=ami-0fb2dd0b481d4dc1a"`

  * **ssh-keyfile**; **ssh-keyname**.- The name of the file containing the ssh key, created with the ssh-keygen command; and the name of the ssh key that will be used to reference it in AWS.

* Deploy the infrastructure by running a command like the following in the Terraform directory, in this case a specific region and AMI are selected:

```
$ terraform apply -var="region_name=eu-west-2" -var="rhel7-ami=ami-0fb2dd0b481d4dc1a"
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

* Review the inventory file and correct/modify as required, in particular:

  * The version installed is 3.11.latest, if another z version is wanted, the following variables must be defined: **openshift_image_tag**; **openshift_pkg_version**

  * The DNS subdomain name for the applications deployed in the cluster, this is defined in the variable **openshift_master_default_subdomain**

* ssh to the bastion host and run the prerequisites and deploy cluster openshift playbook:

```
$ ssh -F ssh.cfg bastion.ocpext.rhcee.support
bastion$ cd OCP311
bastion$ ansible-playbook -vvv /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml
bastion$ ansible-playbook -vvv /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml
```

### Cluster decommissioning instructions

To delete the cluster and **all** its components, including the data stored in the S3 and ELB disks, a single command is required.

```
$ cd Terraform
$ terraform destroy
```

