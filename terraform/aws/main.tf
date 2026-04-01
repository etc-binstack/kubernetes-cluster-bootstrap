
provider "aws" {
  region = "ap-south-1"
}

resource "aws_instance" "k8s" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t3.medium"

  tags = {
    Name = "k8s-node"
  }
}
