// ECR repositories for the app image (custom Dockerfile in docker/) and the
// Jenkins image. Both have scan-on-push enabled and lifecycle policies to
// cap stored image count and limit storage cost (req. 13.5).

resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-app"
  image_tag_mutability = "MUTABLE" // allows pipeline to overwrite :latest on every build

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

resource "aws_ecr_repository" "jenkins" {
  name                 = "${local.name_prefix}-jenkins"
  image_tag_mutability = "MUTABLE" // lts tag is updated in place by upstream

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire images beyond the last 10"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "jenkins" {
  repository = aws_ecr_repository.jenkins.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire images beyond the last 5"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
