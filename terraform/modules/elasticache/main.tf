resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.environment}-cache-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.environment}-redis-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-redis"
  }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.environment}-accounting-cache"
  description          = "Redis cluster for accounting platform"

  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t3.micro"
  num_cache_clusters   = 2
  automatic_failover_enabled = true

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  snapshot_retention_limit = 7
  snapshot_window         = "05:00-06:00"

  tags = {
    Name = "${var.environment}-accounting-cache"
  }
}
