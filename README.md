This project is created to build hands-on experience with cloud infrastructure, container orchestration, automated CI/CD pipelines, and DevOps best practices.

## Current Architecture

The core infrastructure is functional and managed as **Infrastructure as Code (IaC)**:

*   **Container Orchestration:** [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) for deploying and scaling containerized applications.
*   **Infrastructure as Code:** [Terraform]([https://terraform.io](https://developer.hashicorp.com/terraform)) to provision, version, and manage all AWS resources.

## Next Phase: Automated Pipeline Creation

**The primary focus of is establishing a robust CI/CD Deployment Pipeline.** 

To transition this from a local Terraform execution to a modern DevOps workflow, an automated pipeline need to be built to handle:
*   Validating Terraform code before deployment.
*   Automatically building, testing, and deploying application updates into the Amazon EKS cluster without manual intervention.

##  Short summary of the codebase
There are 5 services in the project: auth, user, task, mongodb, efs.
1. User backend api provides functionality for creating and signing in - /signup and /login endpoints respectively. Internally it uses auth apis to obtain token, validation of token, etc. .
2. Task api is used for creating tasks for a specific user. When you make a request to create or get tasks, you need to provide a token obtained from the auth endpoint.
3. Auth api is the core service, which serves as dispatcher of token, their validation, etc. Both user and task apis use auth api internally
4. Mongodb is used for storing users with their tokens, which then utilised in foreseen requests.
5. Aws EFS to store logs of created users.

**Before proceed must be installed:**
- kubectl
- terraform
- aws cli

**To deploy the project you need to execute:** 
1. `terraform init`
2. `terraform apply`
3. to update or create a kubeconfig file:
   `aws eks update-kubeconfig --region region-code --name my-cluster`
4. Since for now there is no implemented mechanism to retrieve EFS filesytemId and set it in StorageClass, you need to take filesystemId from EFS and place it here:
`kind: StorageClass
apiVersion: storage.k8s.io/v1
parameters:
  provisioningMode: efs-ap
  fileSystemId: -
  #other params ommitted for brevity
`
5. Deploy all resources to aws eks `kubectl apply -f ../kubernetes`
6. To check k8s resources are running: `kubectl get all -o wide` 
