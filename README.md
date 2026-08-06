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

For installing efs driver navigate through this guide https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html

Current plan:
1. comment code with efs part. (look thoroughly through yamls where mount is used, specifically users.yaml. then users.app / users.routes etc.) - done
2. build and  push image to docker hub - done
3. test locally - done
4. deploy cluster, vpc, nodes, roles, kupdate cubeconfig via cli!
5. test stack
6. delete all resources
7. migrate to terraform
8. test deployment with terraform
9. add efs driver
10. test with efs driver

**Key notes to consider while deploying:**
1. AmazonEKSClusterRole and AmazonEKSNodeRole roles for cluster and nodes are needed.
2. Eks requires to create control plane in 2 different AZs. For this setup pub-subnet and private-subnet in AZ 1 and pub-subnet in AZ 2 can be used, with 1 NAT Gateway.
3. EC2 instances must be size t3.small and bigger.
4. Instances have their own limits on pods creation, e.g. t3.small can contain 11 pods simultaneously.
5. Select minimum 2 nodes to workaround the problem from point 4 or use bigger instances.
6. Next addons are needed : VPC-CNI, kube-proxy, Core-DNS + 1 another (they are selected by default) + custom addons for metrics: Metrics Server
7. 2 LoadBalancers are created for users and tasks services, think how to combine them into 1 (for cost saving)
8. Security group for efs needs to be created
