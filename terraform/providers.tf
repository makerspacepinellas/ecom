terraform {
  required_version = ">= 1.1.7"

  required_providers {
    aws = {
      version = "~> 4.0"
    }
    random = ">= 2"
  }
}

provider "aws" {
  region  = "us-east-2"
  default_tags {
    tags = {
      Application = var.app_name
      Owner       = var.owner_name
      Environment = terraform.workspace
      Source      = "https://github.com/makerspacepinellas/ecom/tree/develop/terraform"
      Automation  = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  default_tags {
    tags = {
      Application = var.app_name
      Owner       = var.owner_name
      Environment = terraform.workspace
      Source      = "https://github.com/makerspacepinellas/ecom/tree/develop/terraform"
      Automation  = "terraform"
    }
  }
}