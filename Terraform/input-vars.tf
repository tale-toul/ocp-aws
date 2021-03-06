#VARIABLES
variable "region_name" {
  description = "AWS Region where the cluster is deployed"
  type = string
  default = "eu-west-1"
}

variable "cluster_name" {
  description = "Cluster name, used to define Clusterid tag and as part of other component names"
  type = string
  default = "ocp"
}

variable "vpc_name" {
  description = "Name assigned to the VPC"
  type = string
  default = "volatil"
}

variable "dns_domain_ID" {
  description = "Zone ID for the route53 DNS domain that will be used for this cluster"
  type = string
  default = "Z0246469SRQO0B41TRDD"
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
  default = "t3.xlarge"
}

variable "rhel7-ami" {
  description = "AMI on which the EC2 instances are based on, depends on the region"
  type = map
  default = {
    eu-central-1   = "ami-08dfa6c8af482fb9d"
    eu-west-1      = "ami-012d8ddfa1b0b8c46"
    eu-west-2      = "ami-009f8651dc5341434"
    eu-west-3      = "ami-0f1241f3a67ba7ad5"
    eu-north-1     = "ami-0420d727e1092ca73"
    us-east-1      = "ami-01f1bea9a9de3c605"
    us-east-2      = "ami-0514e35fdff0030d9"
    us-west-1      = "ami-0a919c71816e6c91c"
    us-west-2      = "ami-07567e5457f5effa2"
    sa-east-1      = "ami-01888ec47b4eec391"
    ap-south-1     = "ami-04c9741e8c0c6f588"
    ap-northeast-1 = "ami-0e876007231767016"
    ap-northeast-2 = "ami-06f052b6d87a1b726"
    ap-southeast-1 = "ami-0d3bda4bebae2f1fa"
    ap-southeast-2 = "ami-0344c97f84600bb27"
    ca-central-1   = "ami-00efbf3e3a6386ad7"
  }
}

variable "ssh-keyfile" {
  description = "Name of the file with public part of the SSH key to transfer to the EC2 instances"
  type = string
  default = "ocp-ssh.pub"
}

variable "master_count" {
  description = "Number of master nodes in the OCP cluser, can only be 1 or 3"
  type = number
  default = 3
}

variable "infra_count" {
  description = "Number of node instance to be used as infras in the OCP cluster"
  type = number
  default = 3
}

variable "worker_count" {
  description = "Number of node instance to be used as workers in the OCP cluster"
  type = number
  default = 3
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
