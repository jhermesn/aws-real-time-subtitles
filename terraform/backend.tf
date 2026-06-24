terraform {
  backend "s3" {
    key     = "state/terraform.tfstate"
    encrypt = true
  }
}
