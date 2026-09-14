resource "aws_eks_cluster" "this" {
  name = "eks-cluster"

  #not clear parameter
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  bootstrap_self_managed_addons = true

  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.36"

  # for disabling Auto Mode next 3 blocks must be specified
  compute_config {
    enabled = false
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = false
    }
  }

  storage_config {
    block_storage {
      enabled = false
    }
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true

    subnet_ids = [
      aws_subnet.public_subnet_01.id,
      aws_subnet.public_subnet_02.id,
      aws_subnet.private_subnet_01.id
    ]
  }


  # Ensure that IAM Role permissions are created before and deleted
  # after EKS Cluster handling. Otherwise, EKS will not be able to
  # properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
  ]

  tags = {
    Description = local.Description
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "AmazonEKSClusterRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_node_group" "this" {
  cluster_name  = aws_eks_cluster.this.name
  node_role_arn = aws_iam_role.eks_node_group_role.arn
  subnet_ids    = [aws_subnet.private_subnet_01.id]

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  capacity_type  = "ON_DEMAND"
  disk_size      = 20
  instance_types = ["t3.small"]

  node_group_name = "main-eks-node-group"

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly
  ]
}

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

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_eks_addon" "metrics" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "metrics-server"
  addon_version = "v0.9.0-eksbuild.7"

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "aws-efs-csi-driver"
  addon_version = "v3.4.2-eksbuild.1"

  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi_driver_role.arn
    service_account = "efs-csi-controller-sa"
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEFSCSIDriverPolicy,
    aws_eks_addon.pod_identity_agent,
    aws_eks_node_group.this
  ]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.3.10-eksbuild.3"

  depends_on = [aws_eks_node_group.this]
}

#---------------EFS FILESYSTEM PART------------------
resource "aws_efs_file_system" "this" {
  creation_token = "efs-eks"
  encrypted      = true

  tags = {
    Description = local.Description
  }
}
resource "aws_efs_mount_target" "alpha" {
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = aws_subnet.private_subnet_01.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "efs-sg"
  description = "Allow inbound traffic on port 2049"
  vpc_id      = aws_vpc.eks_vpc.id
}

resource "aws_vpc_security_group_egress_rule" "egress_efs" {
  security_group_id = aws_security_group.efs.id
  description       = "Allow all outbound traffic to all ipv4 destinations"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_efs" {
  security_group_id = aws_security_group.efs.id
  description       = "Allow inbound traffic on port 2049"

  ip_protocol = "tcp"
  from_port   = 2049
  to_port     = 2049
  cidr_ipv4   = aws_subnet.private_subnet_01.cidr_block
}


#---------------EFS CSI DRIVER'S ROLE------------------
resource "aws_iam_role" "efs_csi_driver_role" {
  name = "AmazonEFSCSIDriverRole"

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = [{
        Sid    = "AllowEksAuthToAssumeRoleForPodIdentity",
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

locals {
  Description = "Created with Terraform"
}
