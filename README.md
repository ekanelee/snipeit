# snipe-it
Here is an Azure DevOps pipeline which deploys Snipe-IT using a docker container 

# Steps
- The infrastructure is well defined and configured in the infra.bicep file. When talk of infrastructure I mean the resources that are required for the application to be up and running which are: mysql server, database, storage account, two file shares, a docker container webapp. 

You could refer to the official Snipe-IT documentation for a deeper understanding of the resources 
 https://snipe-it.readme.io/docs/docker#hosting-snipe-it-and-mysql-on-azure

- All variables used in the infa.bicep and yaml files are declared in the variables.yml file. 

- The DockerSompose.yml provides the storage mount configurations for the docker container.

- The release-infra-template.yml is the pipeline template file that contains task that 
    + Creates the resource group.
    + Deploys all the resources declared in the infra.bicep 
    + Download mysql ssl certificate and upload to a storage account file share

- The release-infra.yml file is the actual pipeline file which calls on the template

    That should be it, the container should start and you should be able to access the Snipe-IT UI based setup
    Wizard via the URL of the Web App
