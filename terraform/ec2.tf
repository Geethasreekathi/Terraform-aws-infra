locals {
  ecr_registry_host = split("/", aws_ecr_repository.app.repository_url)[0]
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.environment}-app-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -euo pipefail

              amazon-linux-extras install docker -y
              systemctl enable docker
              systemctl start docker

              REGION="${var.region}"
              REGISTRY_HOST="${local.ecr_registry_host}"
              REPO_URI="${aws_ecr_repository.app.repository_url}"
              IMAGE_TAG_PARAM="${aws_ssm_parameter.image_tag.name}"

              aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY_HOST"

              IMAGE_TAG=$(aws ssm get-parameter --name "$IMAGE_TAG_PARAM" --region "$REGION" --query 'Parameter.Value' --output text)

              docker pull "$REPO_URI:$IMAGE_TAG"
              docker run -d --restart unless-stopped -p 80:80 "$REPO_URI:$IMAGE_TAG"
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.environment}-app"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.environment}-app-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = aws_subnet.private[*].id
  health_check_type   = "ELB"
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}
