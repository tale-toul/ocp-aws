#!/bin/sh

TERRAFORM_STATE=../Terraform/terraform.tfstate

#Save master host names in an array
for host in $(terraform output -state=$TERRAFORM_STATE masters_name|egrep -v -e '\[' -e '\]'|sed -e 's/"//g' -e 's/,//g'); do
  masters+=($host)
done

#Save infra host names in an array
for host in $(terraform output -state=$TERRAFORM_STATE infras_name|egrep -v -e '\[' -e '\]'|sed -e 's/"//g' -e 's/,//g'); do
  infras+=($host)
done

#Save worker host names in an array
for host in $(terraform output -state=$TERRAFORM_STATE workers_name|egrep -v -e '\[' -e '\]'|sed -e 's/"//g' -e 's/,//g'); do
  workers+=($host)
done

echo -e "\n[bastion]"
terraform output -state=$TERRAFORM_STATE |grep bastion_dns_name|cut -d= -f2

echo -e "\n[masters]"

for x in ${masters[@]}; do
  echo " $x"
done

echo -e "\n[etcd]\n\n[etcd:children]\n masters"

echo -e "\n[nodes]"

for x in ${masters[@]}; do
  echo " $x  openshift_node_group_name='node-config-master'"
done

for x in ${infras[@]}; do
  echo " $x  openshift_node_group_name='node-config-infra'"
done

for x in ${workers[@]}; do
  echo " $x  openshift_node_group_name='node-config-compute'"
done
