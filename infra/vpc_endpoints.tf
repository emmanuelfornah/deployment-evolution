# Gateway endpoints only. They're free and keep S3 and DynamoDB traffic
# off the NAT gateway, so those calls carry no NAT data-processing charge.
#
# The 7 interface endpoints (ecr.api, ecr.dkr, logs, secretsmanager, ssm,
# ssmmessages, ec2messages) were removed for cost control on a portfolio
# project: billed per AZ-hour in both AZs, they cost more than the NAT
# gateway they were meant to save on. Those calls now go out through the
# NAT (the private route table's 0.0.0.0/0 -> NAT route). See
# MONITORING.md §8.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}
