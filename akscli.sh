az group create --name aksdemo-rg --location SouthCentralUS

az aks create \
    --resource-group aksdemo-rg \
    --name aksattscus \
    --generate-ssh-keys \
    --load-balancer-sku standard \
    --enable-managed-identity \
    --location SouthCentralUS \
    --node-count 1

az aks nodepool add \
    --resource-group aksdemo-rg \
    --cluster-name aksattscus \
    --name spotnodepool \
    --priority Spot \
    --eviction-policy Delete \
    --spot-max-price -1 \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 3 \
    --no-wait

az aks get-credentials --resource-group aksdemo-rg --name aksattscus

#https://github.com/Azure/AKS/issues/1349
az role assignment create --assignee --scope --role acrpull

# https://nodejs.org/fr/docs/guides/nodejs-docker-webapp/
az acr build --image sample/hello-world:v1 \
  --registry nzaksreg.azurecr.io \
  --file Dockerfile .

az acr login --name nzaksreg

docker login nzaksreg.azurecr.io

docker build --tag sample/hello-world:v2 .

docker push nzaksreg.azurecr.io/sample/hello-world:v2

docker run -d -p 8091:8080 --name simplenodeapp nzaksreg.azurecr.io/sample/hello-world:v2

az network private-endpoint create --name attaksep --resource-group nzdemo-sc-vnet-rg --subnet /subscriptions/7e0f910b-6182-434c-a552-2b63ad635f23/resourceGroups/nzdemo-sc-vnet-rg/providers/Microsoft.Network/virtualNetworks/nzdemo-sc-vnet/subnets/plstore-subnet --private-connection-resource-id "/subscriptions/03228871-7f68-4594-b208-2d8207a65428/resourcegroups/aksdemo-rg/providers/Microsoft.ContainerService/managedClusters/aksattscus" --group-ids management --connection-name attaksepConnection

az aks get-credentials --name aksattclustereastus2 --resource-group aksdemo

################Retrieve AKS Resource ID######################
aksresourceid=$(az aks show --name aksattcluswestus2 --resource-group aksdemo --query 'id' -o tsv)
################Retrieve the MC Resource Group################
noderg=$(az aks show --name aksattcluswestus2 --resource-group aksdemo --query 'nodeResourceGroup' -o tsv) 
az resource list --resource-group $noderg
##############Create subnet, disable private endpoint network policies, create private endpoint############
az network vnet subnet create --name BastionPESubnet2 --resource-group Bastion --vnet-name BastionVMVNET --address-prefixes 10.0.4.0/24
az network vnet subnet update --name BastionPESubnet2 --resource-group Bastion --vnet-name BastionVMVNET --disable-private-endpoint-network-policies true
az network private-endpoint create --name PrivateKubeApiEndpoint2 --resource-group Bastion --vnet-name BastionVMVNET --subnet BastionPESubnet2 --private-connection-resource-id $aksresourceid --group-ids management --connection-name myKubeConnection

##############Create a Private DNS zone within the Bastion Resource group to match the one in the MC resource group####
az network private-dns zone create -g Bastion -n 1392a07c-ad38-49fd-b65e-86f45e099abb.westus2.azmk8s.io

####Update DNS with actual ip of endpoint created above######################
az network private-dns record-set a add-record -g Bastion -z 1392a07c-ad38-49fd-b65e-86f45e099abb.westus2.azmk8s.io -n aksattclus-aksdemo-c24839-686c6cd4 -a 10.0.3.4
#######Link the Bastion Vnet to private dns zone to propogate the records####
az network private-dns link vnet create -g Bastion -n MyDNSLinktoBastion -z 1392a07c-ad38-49fd-b65e-86f45e099abb.westus2.azmk8s.io -v BastionVMVNET -e true

######List nodes from within Bastion VM##############
sudo az aks install-cli
az aks get-credentials --resource-group aksdemo --name aksattcluswestus2
kubectl get nodes
############################Deploy application###############################################

az acr create --resource-group aksdemo --name attacr --sku Standard --location westus 
AKS_RESOURCE_GROUP="aksdemo"
ACR_RESOURCE_GROUP="aksdemo"
AKS_CLUSTER_NAME="aksattcluswestus2"
Service endpoint from Bastion to ACR 
ACR_NAME="attacr"
 # Get the id of the service principal configured for AKS
 CLIENT_ID=$(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "servicePrincipalProfile.clientId" --output tsv)

 # Get the ACR registry resource id
 ACR_ID=$(az acr show --name $ACR_NAME --resource-group $ACR_RESOURCE_GROUP --query "id" --output tsv)

# Create role assignment
az role assignment create --assignee $CLIENT_ID --role acrpull --scope $ACR_ID
az aks update -n aksattcluswestus2 -g aksdemo --attach-acr attacr

#Deploy the application
vi azure-vote-all-in-one-redis.yaml
kubectl apply -f azure-vote-all-in-one-redis.yaml
kubectl get service azure-vote-front --watch
kubectl delete deployment azure-vote-front
kubectl delete deployment azure-vote-back