#########################################################################################################
## Create eks cluster
#########################################################################################################
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"
  cluster_name    = var.cluster-name
  cluster_version = var.cluster-version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      cluster_name = var.cluster-name
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  cluster_additional_security_group_ids = [aws_security_group.ecom-sg-cli.id]

  # EKS Managed Node Group
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "default"
          namespace = "kube-system"
        }
      ]
    }
    mgmt = {
      name = "mgmt"
      selectors = [
        {
          namespace = "mgmt"
        }
      ]
    }
    service = {
      name = "service"
      selectors = [
        {
          namespace = "service"
        }
      ]
    }
  }
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.12"

  role_name_prefix      = "VPC-CNI-IRSA"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
    common = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

############################################################################################
## 로드밸런서 콘트롤러 설정
## EKS 에서 Ingress 를 사용하기 위해서는 반듯이 로드밸런서 콘트롤러를 설정 해야함.
## 참고 URL : https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/aws-load-balancer-controller.html
############################################################################################

######################################################################################################################
# 로컬변수
# 쿠버네티스 추가 될때마다 lb_controller_iam_role_name 을 추가해야함.
######################################################################################################################

locals {
  # data-eks 를 위한 role name
  lb_controller_iam_role_name = "lb-controller-role"
  k8s_aws_lb_service_account_namespace = "kube-system"
  lb_controller_service_account_name   = "aws-load-balancer-controller"
}

######################################################################################################################
# EKS 클러스터 인증 데이터 소스 추가
######################################################################################################################

data "aws_eks_cluster_auth" "eks" {
  name = var.cluster-name
}

######################################################################################################################
# Load Balancer Controller ROLE 설정
######################################################################################################################
module "lb_controller_role" {
  source      = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version     = "v5.1.0"
  create_role = true

  role_name        = local.lb_controller_iam_role_name
  role_path        = "/"
  role_description = "Used by AWS Load Balancer Controller for EKS"

  role_permissions_boundary_arn = ""

  provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  oidc_fully_qualified_subjects = [
    "system:serviceaccount:${local.k8s_aws_lb_service_account_namespace}:${local.lb_controller_service_account_name}"
  ]
  oidc_fully_qualified_audiences = [
    "sts.amazonaws.com"
  ]
}