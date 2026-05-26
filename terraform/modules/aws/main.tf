data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [local.resolved_vpc_id]
  }
}

locals {
  vms_by_name        = { for v in var.vms : v.name => v }
  resolved_ami       = var.ami != "" ? var.ami : data.aws_ami.ubuntu.id
  resolved_vpc_id    = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default.id
  resolved_subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.default.ids[0]
}

resource "aws_key_pair" "ansible" {
  key_name_prefix = "poaf-"
  public_key      = var.ssh_public_key
}

resource "aws_security_group" "vm" {
  name_prefix = "poaf-"
  description = "SSH ingress for Ansible control plane"
  vpc_id      = local.resolved_vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "vm" {
  for_each = local.vms_by_name

  ami           = local.resolved_ami
  instance_type = each.value.instance_type
  subnet_id     = local.resolved_subnet_id
  key_name      = aws_key_pair.ansible.key_name

  vpc_security_group_ids      = [aws_security_group.vm.id]
  associate_public_ip_address = true

  tags = {
    Name      = each.value.name
    ManagedBy = "poaf-terraform"
  }
}

resource "aws_ebs_volume" "data" {
  for_each = local.vms_by_name

  availability_zone = aws_instance.vm[each.key].availability_zone
  size              = each.value.storage_gb
  type              = "gp3"

  tags = {
    Name = "${each.value.name}-data"
  }
}

resource "aws_volume_attachment" "data" {
  for_each = local.vms_by_name

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data[each.key].id
  instance_id = aws_instance.vm[each.key].id
}
