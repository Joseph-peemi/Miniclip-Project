// Peers the two VPCs so Jenkins (10.41.0.0/16) can actually reach the app
// VPC (10.40.0.0/16) and push deployments to it.

resource "aws_vpc_peering_connection" "app_jenkins" {
  vpc_id      = module.vpc_app.vpc_id
  peer_vpc_id = module.vpc_jenkins.vpc_id
  auto_accept = true // same account, same region, so no manual accepter step needed

  tags = merge(var.tags, { Name = "${local.name_prefix}-app-jenkins-peer" })
}

// App side: send anything bound for the Jenkins CIDR across the peering link
resource "aws_route" "app_to_jenkins" {
  count = length(module.vpc_app.private_route_table_ids)

  route_table_id            = module.vpc_app.private_route_table_ids[count.index]
  destination_cidr_block    = local.jenkins_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_jenkins.id
}

// And the mirror route on the Jenkins side, back toward the app VPC
resource "aws_route" "jenkins_to_app" {
  count = length(module.vpc_jenkins.private_route_table_ids)

  route_table_id            = module.vpc_jenkins.private_route_table_ids[count.index]
  destination_cidr_block    = local.app_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_jenkins.id
}
