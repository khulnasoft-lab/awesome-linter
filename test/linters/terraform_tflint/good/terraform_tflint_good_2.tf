module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "4.9.0"

  bucket = "test-bucket"
}

module "good_relative_reference" {
  source = "../modules/ec2_instance"
}
