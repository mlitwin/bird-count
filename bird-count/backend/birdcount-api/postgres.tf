# Aurora Serverless PostgreSQL

data "aws_ssm_parameter" "foo" {
  name = "foo"
}

resource "aws_rds_cluster" "birds" {
  cluster_identifier      = "example-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "serverless"
  database_name           = "birds"
  master_username         = "root"
  master_password         = "changeme" # Change this in production
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"

  scaling_configuration {
    auto_pause               = true
    max_capacity             = 4
    min_capacity             = 2
    seconds_until_auto_pause = 300
    timeout_action           = "ForceApplyCapacityChange"
  }
}

output "db_endpoint" {
  value = aws_rds_cluster.example_db.endpoint
}
