resource "aws_vpc" "eks_vpc" {
  cidr_block           = "192.168.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = local.name
    Terraform = true
  }
}

locals {
  name   = "eks-vpc"
  region = "eu-north-1"
}

resource "aws_subnet" "public_subnet_01" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "192.168.0.0/18"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name                     = "${local.name}-public-01"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_subnet_02" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "192.168.64.0/18"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]

  tags = {
    Name                     = "${local.name}-public-02"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private_subnet_01" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "192.168.128.0/18"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name                              = "${local.name}-private-01"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.eks_vpc.id
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_01.id
  depends_on    = [aws_internet_gateway.gw]
}


resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
}

resource "aws_route_table_association" "public_subnet_01" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_subnet_01.id
}

resource "aws_route_table_association" "public_subnet_02" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_subnet_02.id
}

resource "aws_route_table_association" "private_subnet_01" {
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private_subnet_01.id
}

output "public_subnet_ids" {
  description = "Ids of public subnets"
  value       = [aws_subnet.public_subnet_01.id, aws_subnet.public_subnet_02.id]
}

output "private_subnet_ids" {
  description = "Ids of private subnets"
  value       = aws_subnet.private_subnet_01.id
}

output "vpc_id" {
  description = "Id of vpc"
  value       = aws_vpc.eks_vpc.id
}