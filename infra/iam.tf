# IAM Role for EC2 instances allowing AWS Systems Manager (SSM) Session Manager
# This enables secure zero-bastion management without opening SSH/RDP to the internet

resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.environment}-boundary-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-boundary-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.environment}-boundary-ec2-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}
