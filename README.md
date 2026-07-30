This project is created for testing and educational purposes to deep dive into **k8s technology ** and **AWS EKS specifically**. 
The main point of the project not to focus on backend/frontend technologies, but deploying k8s, its features and behaviour.
Short summary of the project
There are 4 services in general: auth, user, task, mongodb.
##add endpoints?
User backend api provides functionality for creating and signing in - /signup and /login endpoints respectively. Internally it uses auth apis to obtain token, validation of token, etc. .

Task api is used for creating tasks for a specific user. When you make a request to create or get tasks, you need to provide a token obtained from the auth endpoint.

Auth api is the core service, which serves as dispatcher of token, their validation, etc.

Both user and task api uses auth api internally

Mongodb is used for storing users with their tokens, which then utilised in foreseen requests.

To deploy the project to eks can be used several variants: aws CLI + Console, eksctl or terraform. 
Here will be considered eksctl and then added terraform approach for automation pipelines.

**Eksctl approach**
To EKS work properly must be configured the following resources: IAM Roles, Vpcs, Security groups, subnets.
For testing purposes and for preventing draining money - will be used 1 az with 2 subnets (private + public). 
IAM Roles: For eksctl you don't need to provide cluster and node roles. You need to do it, only if you have existing roles. In this case they must be included into a cfg file.
VPC: eksctl will create a VPC for you by default if you don't specify one (existing or a vpc which you want to create)

Creating cluster.
In this example will be considered creation of eks with cfg `cluster.yaml` file.
Next, run this command
eksctl create cluster -f cluster.yaml
Updating kubeconfig file can be skipped, because eksctl already completed this step for you

To check cluster is working:
kubectl get all -o wide

To delete this cluster, run:
eksctl delete cluster -f --wait cluster.yaml
eksctl delete cluster --name my-cluster --region region-code
