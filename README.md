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
Here will be considered cli + console and terraform approaches.

**Note**: kubectl must be installed on your machine.

**aws CLI + Console approach**
To EKS work properly the following resources must be configured: IAM Roles, Vpcs, Security groups, subnets.
For testing purposes and for preventing draining money - will be used 1 az with 2 subnets (private + public). 

**Prerequisits:**
- IAM Roles: Roles for Nodes and Cluster have to be configured.
- VPC: Is located under vpc-config stack, should be deployed with cloudFormation
- Update kubeconfig
- Create Security Groups for EFS. This must be attached to VPC which was created specifically to EKS
- Create Cluster from aws tutorial: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html
- Install CSI EFS driver on cluster https://github.com/kubernetes-sigs/aws-efs-csi-driver. Driver permissions need to be set up.
- Create nodes with t3.small instances and 5-10 Gi storage.
  
To check cluster is working:
kubectl get all -o wide


