output "cluster_name" { value = aws_eks_cluster.this.name }
output "region" { value = var.region }

output "db_endpoint" { value = aws_db_instance.postgres.address }
output "db_name" { value = var.db_name }
output "db_user" { value = var.db_user }

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}
