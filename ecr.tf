// Two repos: one for our own app image (built from Docker/Dockerfile) and one
// for the Jenkins image. Both scan on push and get a lifecycle policy so old
// images actually get cleaned up instead of piling up storage cost forever.

resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-app"
  image_tag_mutability = "MUTABLE" // the pipeline pushes over :latest every build, so this can't be immutable

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
  image_tag_mutability = "MUTABLE" // upstream moves the lts tag around, so ours has to allow that too

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
