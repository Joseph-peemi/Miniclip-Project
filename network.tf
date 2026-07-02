// VPC peering: 10.40.0.0/16 (app) ↔ 10.41.0.0/16 (jenkins)
// Jenkins must reach the app VPC to deploy containers (req. 2)

resource "aws_vpc_peering_connection" "app_jenkins" {
  vpc_id      = module.vpc_app.vpc_id
  peer_vpc_id = module.vpc_jenkins.vpc_id
  auto_accept = true // same account + same region — no accepter resource needed

  tags = merge(var.tags, { Name = "${local.name_prefix}-app-jenkins-peer" })
}

// Routes in the app private subnets pointing to Jenkins VPC
resource "aws_route" "app_to_jenkins" {
  count = length(module.vpc_app.private_route_table_ids)

  route_table_id            = module.vpc_app.private_route_table_ids[count.index]
  destination_cidr_block    = local.jenkins_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_jenkins.id
}

// Routes in the Jenkins private subnets pointing back to the app VPC
resource "aws_route" "jenkins_to_app" {
  count = length(module.vpc_jenkins.private_route_table_ids)

  route_table_id            = module.vpc_jenkins.private_route_table_ids[count.index]
  destination_cidr_block    = local.app_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_jenkins.id
}
