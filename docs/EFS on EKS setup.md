Here I am transforming gathered knowledge about EFS, EFS CSI driver and Pod Identity to a teraform code
For this setup EKS Auto mode is off
Content of the article will contain components to make EFS work with AWS EKS and Additional Information section
At the end of each component's part will be provided terraform code.

Steps:
1. EFS file system and security group for efs (port 2049)
2. The EFS CSI driver EKS addon with a specified IAM role
3. Set up Pod Identity 
    - Prepare node IAM role
    - Install Pod Identity Agent addon to a cluster
    - Create the EFS CSI driver IAM role
    - Assign the IAM role to a Kubernetes service account (pod association)
4. Create a K8s StorageClass and PVC (for dynamical provisioning)

* Additional information


# EFS file system and security group for efs (port 2049)

It's not quite clear from the official [AWS CSI driver doc](https://github.com/kubernetes-sigs/aws-efs-csi-driver/tree/master/docs#features)
whether creation of EFS file system can be omitted if dynamic provisioning is used.

<pre>Dynamic provisioning - Uses a persistent volume claim (PVC) to dynamically provision a persistent volume (PV). On creating a PVC, Kubernetes requests an Amazon EFS or Amazon S3 file system to create an access point in a file system which will be used to mount the PV.`</pre>

But according to the [eksworkshop link](https://www.eksworkshop.com/docs/fundamentals/storage/efs/efs-csi-driver)

<pre>Dynamic provisioning: The driver creates an access point for each PersistentVolume. <b>This requires an existing AWS EFS file system</b> that must be specified in the StorageClass parameters.
Static provisioning: This also requires a pre-created AWS EFS file system, which can then be mounted as a volume inside a container using the driver.</pre>

So to be sure that dynamic provisioning is working, efs fs will be created

Based on [the official doc](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/efs-create-filesystem.md)
the following resources are necessary:
- VPC id and CIDR range of VPC the cluster in. 

- A Security Group with an inbound rule on port 2049 that allows inbound NFS traffic
**Important** To further restrict access to your file system, you can use the CIDR for your subnet instead of the VPC. - If i understood correctly in SG ingress rule can be specified source parameter either CIDR block of cluster VPC or subnet CIDR. Subnet CIDR rule is stricter and will allow only make calls to EFS from this source.
`cidr_ipv4 = aws_subnet.private_subnet_01.cidr_block`

- Add mount targets for the subnets that your nodes are in.

**Small clarification**
Mount target (network layer) is an Elastic Network Interface which exposes EFS to a specified VPC. We access EFS through this 'gate'. That's how the cluster nodes will be able to reach EFS (through mount targets). 
Best practice is to create a mount target for each AZ for high availability, but since my nodes are placed only in 1 private subnet in 1 AZ (to save cost), I will be using only 1 mount target.

ENI is a logical networking component in a VPC that represents a virtual network card. 

Access Point (application layer) is a construct that sits on top of a file system and mount targets. With it you specify a root directory path within the file system (basePath) and sub-directory path (subPathPattern) and level of permissions (uid/gid) you can assign for this sub-directory. 

Mount targets provide the network connectivity to your EFS file system while access points provide the access control and application-specific entry points. [link](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html#enforce-root-directory-access-point)
**Terraform code**
<pre>
resource "aws_efs_file_system" "this" {
  creation_token = "efs-eks"
  encrypted = true

  tags = {
    Description = local.Description
  }
}
resource "aws_efs_mount_target" "alpha" {
  file_system_id = aws_efs_file_system.this.id
  subnet_id = aws_subnet.private_subnet_01.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name = "efs-sg"
  description = "Allow inbound traffic on port 2049"
  vpc_id = aws_vpc.eks_vpc.id
}

resource "aws_vpc_security_group_egress_rule" "egress_efs" {
  security_group_id = aws_security_group.efs.id
  description = "Allow all outbound traffic to all ipv4 destinations"

  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_efs" {
  security_group_id = aws_security_group.efs.id
  description = "Allow inbound traffic on port 2049"

  ip_protocol = "tcp"
  from_port = 2049
  to_port = 2049
  cidr_ipv4 = aws_subnet.private_subnet_01.cidr_block
}
</pre>

# [Install EFS CSI driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
A storage driver is the code that manages the actual external infrastructure (like AWS EBS volumes or AWS EFS filesystems) and connects them to Kubernetes storage abstractions like PVs and PVCs.
Before K8s baked cloud-specific (for google, aws, azure, etc.) drivers directly in its source code , but every change in a driver code led to rewriting k8s core backend, which was inefficient. So k8s decided to provide an interface (CSI driver) to the external providers and providers in their turn had to implement drivers according to this interface. Installing EFS CSI driver give the pods ability to call AWS EFS APIs.

Here you can find the list of [aws addons](https://docs.aws.amazon.com/eks/latest/userguide/workloads-add-ons-available-eks.html)
The Amazon EKS add-on name is aws-efs-csi-driver.

*Note*
To get addon versions and which one is default use:
<pre>aws eks describe-addon-versions \
    --kubernetes-version 1.36 \
    --addon-name aws-efs-csi-driver \
    --query 'addons[].addonVersions[].{Version: addonVersion, IsDefault: compatibilities[0].defaultVersion}' \
    --output table
</pre>

**Terraform code**
<pre>
resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name = aws_eks_cluster.this.name
  addon_name = "aws-efs-csi-driver"
  addon_version = "v3.4.2-eksbuild.1"

  pod_identity_association {
    role_arn = aws_iam_role.efs_csi_driver_role.arn
    service_account = "efs-csi-controller-sa"
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEFSCSIDriverPolicy,
    aws_eks_addon.pod_identity_agent
  ]
}
</pre>

## Main components of efs-csi-driver:
-efs-csi-controller (Deployment).
Includes efs-plugin, csi-provisioner and liveness-probe.
the controller's job is management of the AWS-side storage resource (specifically Access Points, when using dynamic 
provisioning), create/delete volumes, validation calls to describe filesystems/access points/mounttargets.

-efs-csi-node (DaemonSet) mounts EFS filesystem to a pod's directory on the node, when a pod using an EFS volume is scheduled there. This daemonset contains: csi-driver-registrar, efs-plugin and liveness-probe.

## Containers' responsibility:
liveness-probe (both pods) checks if the containers are alive and functioning.

csi-provisioner(efs-csi-controller) - watches PVC objects via k8s API, calls the CSI driver's CreateVolume gRPC over a local Unix socket, also creates PersistentVolume objects in k8s with volumeHandle received from main container (efs-plugin)

efs-plugin(efs-csi-controller) - receives CreateVolume gRPC call, translates it into AWS SDK call and calls AWS EFS API using Pod Identity credentials (discussed in Additional information).

csi-driver-registrar(efs-csi-node) - informs local node's kubelet daemon about the presence of the EFS CSI driver and registers the driver's specific Unix socket path via which calls will be handled. 

efs-plugin(efs-csi-node) - receives NodePublishVolume call over a Unix socket from kubelet (when pod is assigned and it needs the volume to be mounted), then runs mount command. NFS mount to EFS's mount target ENI (access point) in the VPC.

For [Amazon EFS file systems](https://docs.aws.amazon.com/eks/latest/userguide/workloads-add-ons-available-eks.html#add-ons-aws-efs-csi-driver): Attach the AmazonEFSCSIDriverPolicy managed policy. We need to attach this policy to an IAM role to authorize our SDK calls.
For Sdk calls we need keys/credentials and we get them from Pod Identity.

# Set up EKS Pod Identity
<pre>There are 2 ways to provide the ability to manage credentials for your applications in AWS: IAM roles for service accounts (IRSA) and Pod Identity. Here I will look into the 2nd option - PI. PI is more modern, simpler and has the following enhancements compare to IRSA: Reusability, Independent Operations, Scalability.</pre> 

To make Pod Identity explanation clearer I'd want to start with Pod Identity primary goals, Service Account and Pod Identity Association. 

### EKS Pod Identity main goals
Pod Identity provides AWS credentials to pods so that AWS SDKs which is called by containers (e.g. efs-plugin, csi-provisioner) can use these credentials to access AWS services.

### Service Account (SA)
K8s definition: `"A service account is a type of non-human account that, in Kubernetes, provides a distinct identity in a Kubernetes cluster."`

Imagine pods which need certain permissions to operate inside a cluster and namespaces. How could we achieve that? With service accounts, but not only with them; SA by itself is just a label/an identity. We need a role and permissions added to this identity. Role and ClusterRole accomplishes this goal (Roles must specify namespaces where we want to operate, ClusterRoles are cluster-scoped). Also we need to bind the newly created role which contains permissions together with Service Account in order to apply this bundle to certain subjects who could operate within this role. This is done by RoleBinding/ClusterRoleBinding. Then SA is applied to Pods/Deployment/DaemonSet which need certain permissions, like this:
<pre>serviceAccountName: efs-csi-controller-sa</pre>

### Pod Identity Association
ClusterRole/Role and ClusterRoleBinding/RoleBinding exists only **inside** the k8s. To bind AWS and K8s developers had to come with a different solution.
This solution is **Pod Identity Association**.

To operate on AWS services, we need to configure IAM role, which defines what pods (inside AWS EFS CSI driver) are allowed to do in AWS (analogue of Role/ClusterRole in k8s). SA can be reused in the same manner as in k8s - to give pods an identity (which pod is allowed to use the role). But to bind 2 'worlds' (SA from k8s and IAM role from AWS) we need to create **Pod Identity Association**. Iefs-csi-node-sat connects IAM role, SA, namespace and cluster name to grant permissions to certain pods (as we did with ClusterRoleBinding/RoleBinding). This defines which identity can operate on which AWS services, and within what scope.

Having learned about this, we can start set up EKS Pod Identity.
I will be referring to [AWS documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)

**Important**
This configuration is appliable to resources which live in the same AWS account.

To set up Pod Identity the following must be done:
1. Prepare node IAM role
2. Install Pod Identity Agent addon to a cluster
3. Create the EFS CSI driver IAM role
4. Assign the IAM role to a Kubernetes service account


## Preparing node role
The node must have a role with permission for the agent to call AssumeRoleForPodIdentity action in the EKS Auth API. (It gives an opportunity for Pod Identity Agent to call EKS Auth API):
<pre>{
    "Version":"2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks-auth:AssumeRoleForPodIdentity"
            ],
            "Resource": "*"
        }
    ]
}</pre>

**AmazonEKSWorkerNodePolicy** already contains the permission to call **eks-auth:AssumeRoleForPodIdentity** api (this policy is configured as part of eks_node_group_role in tf code).

**Terraform code**
<pre>
resource "aws_iam_role" "eks_node_group_role" {
  name = "AmazonEKSNodeGroupRole"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}
</pre>

## Installing Pod Identity Agent addon
The Amazon EKS addon name is eks-pod-identity-agent.

**Important note**
By default, the EKS Pod Identity Agent is pre-installed on EKS Auto Mode clusters.

**Terraform code**
<pre>
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
  addon_version = "v1.3.10-eksbuild.3"
}
</pre>

<pre>To Confirm that the EKS Pod Identity Agent pods are running on your cluster.

kubectl get pods -n kube-system | grep 'eks-pod-identity-agent'</pre>

## Create role for EFS CSI Driver pods
- Create an IAM role with a trust policy that allows pods.eks.amazonaws.com to assume it. (From my understanding pods.eks.amazonaws.com is the service principal identifier for the EKS Auth API backend service It's how the service identifies itself to STS when calls it.) As principal here is set pods.eks.amazonaws.com , because it acts on behalf of EFS CSI Driver pods.

Trust Policy:
<pre>{
    "Version":"2012-10-17",
    "Statement": [
        {
            "Sid": "AllowEksAuthToAssumeRoleForPodIdentity",
            "Effect": "Allow",
            "Principal": {
                "Service": "pods.eks.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
            ]
        }
    ]
}</pre>

For Permission Policy can be used custom or prebuilt AmazonEFSCSIDriverPolicy

**Terraform code**
<pre>
resource "aws_iam_role" "efs_csi_driver_role" {
  name = "AmazonEFSCSIDriverRole"

  assume_role_policy = jsonencode(
    {
    Version = "2012-10-17",
    Statement = [{
      Sid = "AllowEksAuthToAssumeRoleForPodIdentity",
      Effect = "Allow",
      Principal = {
        Service = "pods.eks.amazonaws.com"
        },
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
          ]
      }]
    })
}

resource "aws_iam_role_policy_attachment" "AmazonEFSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi_driver_role.name
}
</pre>

### Assign the IAM role (step 3) to a Kubernetes service account
In other words create Pod Identity Association that links the IAM role to a specific Kubernetes namespace and service account.

**Terraform code**
<pre>
  pod_identity_association {
    role_arn = aws_iam_role.efs_csi_driver_role.arn
    service_account = "efs-csi-controller-sa"
  }
</pre>
Here association created inside aws_eks_addon.efs_csi_driver resource.


* Additional information
Throughout the guide an uncertainty about Eks Pod Identity may arise. Why are we talking about Pod Identity, but use Pod Identity Agent Or what is Eks Pod Identity?

More details you can find in a great article [here] Kudos to its authors: George John, Ashok Srirama, and Hemanth AVS (https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)

Eks Pod Identity is a feature which consists of different components. The main components are: EKS Pod Identity Webhook, EKS Auth API, EKS Pod Identity Agent and EKS Pod Identity API.


To understand their functionality let's take a look at the flow of using Amazon EKS Pod Identity.
Prerequisites:
- Installed addon Pod Identity Agent
- Created an IAM role for EFS CSI driver pods
- Created Pod Identity Association: (namespace, service account)

After the AWS IAM role is associated with the service account, any newly created pods using that service account will be intercepted by the EKS Pod Identity webhook. 
This webhook mutates the pod spec with the env vars: `AWS_CONTAINER_CREDENTIALS_FULL_URI` and `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`*.

<pre>*All SDKs have number of sources which they look through to find valid credentials to use, to make a request to an AWS service. This search is called credential provider chain. Customer's containerized application uses **container credential provider**. EKS Pod Identity utilises it to retrieve credentials from an HTTP endpoint specified in the environment variable AWS_CONTAINER_CREDENTIALS_FULL_URI

`AWS_CONTAINER_CREDENTIALS_FULL_URI` specifies the full HTTP URL endpoint for the SDK to use when making a request for credentials i.e. which address to call (Pod Identity agent's address)

`AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE` - is set of instructions for Kubernetes API server specified by webhook: who can use this token (pods.eks.amazonaws.com) and where to store the token (/var/run/secrets/pods.eks.amazonaws.com/serviceaccount/). Kubelet asks Kubernetes Server Api to generate JWT. Generated token contains different information, but more important is: **audience** and **subject** (holds info about pod's namespace and service account ). After generation kubelet writes JWT to the node. </pre>

0. Pod Identity Association stored inside EKS control plane (imo it is a mapping record: {namespace, service account} → IAM role ARN)
1. Source code inside the driver containers (like efs-plugin or csi-provisioner) calls AWS SDKs. 
2. SDK looking into its provider chain, calls Pod Identity Agent endpoint asking for credentials.
3. Request reaches EKS Pod Identity Agent, which runs as a DaemonSet pod on worker nodes. 
    - make a request to the EKS Auth API (AssumeRoleForPodIdentity) to exchange the token for temporary IAM credentials
4. EKS Auth API
    - decodes the JWT token 
    - retrieves namespace, service account
    - validates retrieved params against role associations with the service account created before (from step 0).
5. If validation is succesful calls sts:AssumeRole and sts:TagSession
6. STS receives a request
    - checks whether provided identity (pods.eks.amazonaws.com) is allowed to receive temp. credentials
    - attaches session tags such as kubernetes-namespace, kubernetes-service-account, eks-cluster-arn, eks-cluster-name, kubernetes-pod-name, kubernetes-pod-uid
    - issues temporary credentials scoped to target role's permissions back to the EKS Auth API
7. Credentials are returned back (EKS Auth API -> EKS Pod Identity Agent -> Pod's SDK) by the chain of the request.


**Interesting points**
Does a service account need to be created? - no, service account is created inside the efs csi driver  (efs-csi-controller-sa )
There are 2 service accounts in efs-csi-driver: efs-csi-controller-sa and efs-csi-node-sa.
Here you can find list of permissions for [efs-csi-controller-sa](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/d13e3c718f913a6fa56cca3971b753325e8d70f8/deploy/kubernetes/base/controller-serviceaccount.yaml#L6) and [efs-csi-node-sa](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/d13e3c718f913a6fa56cca3971b753325e8d70f8/deploy/kubernetes/base/node-serviceaccount.yaml#L6)
Usually we don't create pod identity association for efs-csi-node-sa only if specific mount options are used for mount control.

Do we need to bind application pods to the efs-csi-controller-sa service account? - no, as long as we don't make api calls inside the app pods. In my example app pods shouldn't know anything about underlying architecture. They only asks for volume storage. Csi-controller and csi-node pods provide all necessary mechanisms.

Csi controller decides which uid/gid will be used for an Access Point (admin specifies gid/uid range in storageClass, then controller decides which certain ids to use - e.g. 1000) If user doesn't specify gid/uid range defaults from driver are used.
Pods (container processes) also have their own gid/uid (param `runAsUser` or image based setup: implicitly, if not specified in an image - depends on the image,e.g. nginx sets uid to root 0 or explicilty-specified in dockerfile). When pods use external storage write/update data, uid/gid of Access Point will be used.
Almost always gids/uids of pods and aps won't be the same.
This mismatch is usually harmless — most apps just read/write files without 
checking ownership. It only causes problems for apps that explicitly compare 
file ownership to their own uid (e.g. `stat()` checks, some security-hardened 
images, DB startup scripts) — a fairly rare pattern.


