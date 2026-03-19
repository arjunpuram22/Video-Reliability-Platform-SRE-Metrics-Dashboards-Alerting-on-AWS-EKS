provider "aws" {
  region = var.region
}

data "aws_availability_zones" "azs" {}

locals {
  name = "${var.project}-${var.env}"
  az1  = data.aws_availability_zones.azs.names[0]
  az2  = data.aws_availability_zones.azs.names[1]
}

# -------------------------
# VPC
# -------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-igw" }
}

# Public subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.20.0.0/20"
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${local.name}-public-1"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.20.16.0/20"
  availability_zone       = local.az2
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${local.name}-public-2"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private subnets
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.20.32.0/20"
  availability_zone = local.az1
  tags = {
    Name                              = "${local.name}-private-1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.20.48.0/20"
  availability_zone = local.az2
  tags = {
    Name                              = "${local.name}-private-2"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# NAT gateway for private subnets
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "${local.name}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-rt-private" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# -------------------------
# IAM roles
# -------------------------
resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "${local.name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -------------------------
# EKS Cluster SG
# -------------------------
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${local.name}-eks-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${local.name}-eks-cluster-sg" }
}

# -------------------------
# EKS Cluster
# -------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.eks_public_access_cidrs
    security_group_ids      = [aws_security_group.eks_cluster_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
  ]
}

# -------------------------
# RDS Postgres (private)
# -------------------------
resource "aws_db_subnet_group" "rds" {
  name       = "${local.name}-rds-subnets"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_security_group" "rds_sg" {
  name   = "${local.name}-rds-sg"
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-rds-sg" }
}

resource "aws_security_group_rule" "rds_ingress_vpc" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.rds_sg.id
  cidr_blocks       = [aws_vpc.this.cidr_block]
}

resource "aws_security_group_rule" "rds_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.rds_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_db_instance" "postgres" {
  identifier        = "${local.name}-postgres"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage

  db_name  = var.db_name
  username = var.db_user
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  backup_retention_period = 7
  deletion_protection     = false

  tags = { Name = "${local.name}-postgres" }
}
