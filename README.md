## Openshift 3.11 installation on AWS

#REFERENCE DOCUMENTATION
#https://access.redhat.com/documentation/en-us/reference_architectures/2018/html/deploying_and_managing_openshift_3.9_on_amazon_web_services/red_hat_openshift_container_platform_prerequisites
#https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf

### Terraform

The Terraform directory contains the neccessary files to create the infrastructure required to install OCP in AWS

The architecture used is based on the one descrived in [this reference document](https://access.redhat.com/sites/default/files/attachments/ocp-on-aws-8.pdf) from Red Hat.

Two different aws providers are defined (https://www.terraform.io/docs/configuration/providers.html): 

* One for the majority of the resources created
* Other for the Route53 DNS name management

Each provider uses different access credentials so a credentials file is created like the following:

```
[default]
aws_access_key_id=xxxx
aws_secret_access_key=xxxx
```
and the provider definition contains the following directive reference the credentials file:

```
  shared_credentials_file = "redhat-credentials.ini"
```

When using different credentials files for each provider it is important to make sure that the environment variables **WS_SECRET_ACCESS_KEY** and **AWS_ACCESS_KEY_ID** are not defined in the session, otherwise extraneus errors will appear when running terraform.

Six subnets are created to leverage the High Availavility provided by the Availability Zones in the region, 3 for public subnets, 3 for private subnets.

####EC2 instances

The AWS base ami that will be used to deploy the hosts is based on RHEL 7.7.
To look for the AWS amis the following command can be used.  The aws CLI binary needs to be available, the authentication to AWS can be completed exporting the variables **AWS_ACCESS_KEY_ID** and **AWS_SECRET_ACCESS_KEY**:

```
$ export AWS_ACCESS_KEY_ID=xxxxxx
$ export AWS_SECRET_ACCESS_KEY=xxxxx
$ aws ec2 describe-images --owners 309956199498 --filters "Name=is-public,Values=true" "Name=name,Values=RHEL*7.7*" --region eu-west-1
```
The command searches for **public** amis in the eu-west-1 (Ireland) region with owner Red Hat (309956199498) that include in the name the string "RHEL*7.7*".  The output will contain a list of amis released at different dates and with minor differences among them.

The EC2 VMs created in the private networks need access to the Internet to donwload packages and images, so 3 NAT gateways are created, one for every private subnet.

One Internet Gateway is created in the VPC to provide access from and to the Internet for the resources created in the public subnets. For this access to be enable, a single route table is created and associated to every public subnet.

A total of 10 EC2 instances are created:

* 1 bastion host deployed in one of the public subnets

* 3 master nodes, each one deployed in one private subnet hence in an availability zone.

* 3 infra nodes, each one deployed in one private subnet hence in an availability zone.

* 3 worker nodes, each one deployed in one private subnet hence in an availability zone.

The bastion host is assigned an Elastic IP, and a corresponding DNS entry is created for that IP.  The A record is created in a different AWS account, so a specific provider is used for the Route53 DNS configuration.

The EC2 instances need the right security group assigned depending on the particular role of the instace.

#### Security Groups

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

Quite a few security groups need to be created, I followed the documentation [here](https://docs.openshift.com/container-platform/3.11/install/prerequisites.html#required-ports) and [here](https://access.redhat.com/documentation/en-us/reference_architectures/2018/html/deploying_and_managing_openshift_3.9_on_amazon_web_services/red_hat_openshift_container_platform_prerequisites)
To add in Terraform the same security group that is being created as a source security group the option **self = true** muste be used:

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

#### Elastic Load Balancers

[Terraform documentations](https://www.terraform.io/docs/providers/aws/r/lb.html)

Three load balancers are created: 

* An ELB in front of the masters accepting requests from the Internet.  This load balancer will accept requests on ports 443 and 8444.

* An ELB in front of the masters, internal, not accessible from the Internet, accepting requests from other components of the cluser.  This load balancer accepts requests on port 443.

* An ELB in front of the infra nodes that contain the router pods (HAProxy), accepting requests from the Internet.  This load balancer accepts requests on ports 80 and 443.

The load balancers are of type **aws_elb**.- This _classic_ load balancer allows the use of security groups, does not need an x509 certificate to terminate the SSL/TLS connections; allows the definition of a TCP port to listen to and to forward the requests to the EC2 instances downstream.  The subnets where the load balancer will be placed, listening for requests is also defined, along the instances that will receive the requests. Cross zone load balanzing will be enable because the VMs being access are in differente availability zones. The load balancer will be internal or not depending on who will be using it.  Finally a health check against the EC2 instances is defined to verify if they can accept requests.


### Ansible

To run an ansible playbook against the nodes in the cluster, first ssh must be configured so that a connection to the hosts in the private subnetworks can be stablished. For this a configuratin file is created **ssh.cfg** that defines a block with the connection parameters for the bastion host, and another one for the connection to the rest of the hosts in the VPC.

```
Host bastion.taletoul.com
  Hostname                bastion.taletoul.com
  user                    ec2-user
  StrictHostKeyChecking   no
  ProxyCommand            none
  CheckHostIP             no
  ForwardAgent            yes
  IdentityFile            ./tale-toul.pem

```

To connect to the bastion host the name **bastion.taletoul.com** must be used so the configuration block is applied.  This configuration defines the FQDN of the host to connect to; the remote user to connect as; remote host's key will not be checked; no proxy command is used; key checking is against hostname rather than IP; ssh connection forwarding is enabled so a key managed by ssh agent can be used from this host to connect to another one; the file with the key used to connect to the remote host is defined to be on the same directory where the ssh command is run from.

The command used to connect to the bastion host will be:

```
$ ssh -F ssh.cfg bastion.taletoul.com
```
The ssh.cfg file is loaded from the command line.

To connect to other hosts in the VPC, which are in private networks and therefore not directly accesible, the following configuration block is defined:

```
Host *.eu-west-1.compute.internal
  StrictHostKeyChecking   no
  ProxyCommand            ssh ec2-user@bastion.taletoul.com -W %h:%p
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

To apply this configuration to ansible the contents of the file must be added to one of the standar config files: /etc/ssh/ss_config or ~/.ssh/config

```
$ cat ssh_config >> ~/.ssh/config
```

When ansible is run for the first time after the hosts have been created the remote keys need to be accepted, even when using the option **host_key_checking=False** not to be bothered with that key validation.  When an indirect connection is stablished to the hosts in the private subnets the key validation happens both at the bastion host and at the final host, but ansible doesn't seem to be prepared for two question and the play hangs on the second question until a connection timeout is reached.

To avoid this problem we have to make sure that a connection to the bastion host is stablished before going to the hosts in the private subnets, for that reason we have to make sure that we run a play against the bastion host before running another against the registry.

A basic **ansible.cfg** configuration file is created with the following contents:

```
[defaults]
inventory=inventario
host_key_checking=False
log_path = ansible.log
```
The default inventory file that ansible will look for is called **inventario**
No ssh key checking for the remote host will be performed
The default log file for ansible will be **ansible.log**

To verify that the configuration is correct and all node are accesble via ansible, an inventory file is created after deploying the terraform infrastructure using a script called **create_inventario.sh**

And a ping is sent to all hosts:

```
$ ansible all -m ping 
```

####Prerequisites

A playbook is created to apply some prerequisites in the cluster host.  The playbook is **prereqs-ocp.yml**.

In the first play a single tasks run against the bastion host serves to puposes: make sure the bastion is accessed before the rest of the hosts in the private networks, and to change the hostname to bastion.taletoul.com

The sencond play subscribes all the hosts with Red Hat; enables the repositories needed to install Openshift.

The username and password required to register the hosts with Red Hat are encrypted in a vault file.  the playbook must be run providing the password to unencrypt that file, for example by storing the password in a file and using the command:

```
$ ansible-playbook --vault-id vault_id.txt prereqs-ocp.yml
```

####Tests

A directory called _tests_ within the Ansible directory is created to hold test playbooks to verify that the infrastructure works as expected:

Before running any of these playbooks the prereqs-ocp.yml playbook must be run.

* **http-test.yaml**.- This playbooks is run agains the nodes group but only applies to those with the variable openshift_node_group_name defined and either with value node-config-master or node-config-infra; installs an httpd server; copies a configuration file to set up an SSL virtual host using a locally generated self signed x509 certificate, with document root at **/var/www/html**. A very simple index.html is added to the Document root containing the hostname of the node so when the connection is tested we know which node we hit, an additional copy of the file with name healthz is created to make the health check of the AWS load balancers happy.  As a final step the httpd service is restarted.  Once the playbook is run, we can use a command like the following to access the web servers through the external load balancer:

`` 
$ while true; do curl -k https://elb-master-public-697013167.eu-west-1.elb.amazonaws.com/; sleep 1; done
`` 
