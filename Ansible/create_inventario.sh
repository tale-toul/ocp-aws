#!/bin/sh

TERRAFORM_STATE=../Terraform/terraform.tfstate

echo -e "[bastion]\n bastion.taletoul.com"

echo -e "[masters]"

terraform output -state=$TERRAFORM_STATE|egrep 'master.+_name'|cut -d= -f2 

echo -e "[nodes]\n bastion.taletoul.com"

terraform output -state=$TERRAFORM_STATE |while read -r line
do
  if (echo $line|egrep 'master.+_name') >/dev/null; then
    echo -n $line|cut -d= -f2|tr -d '\n'
    echo "  openshift_node_group_name='node-config-master'"
  elif (echo $line|egrep 'infra.+_name') >/dev/null; then
    echo -n $line|cut -d= -f2|tr -d '\n'
    echo "  openshift_node_group_name='node-config-infra'"
  elif (echo $line|egrep 'worker.+_name') >/dev/null; then
    echo -n $line|cut -d= -f2|tr -d '\n'
    echo "  openshift_node_group_name='node-config-compute'"
  fi
done 


