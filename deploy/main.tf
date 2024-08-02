provider "aws" {
  region = "eu-central-1"
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "cp-terraform-state-infra"
    key    = "infra/terraform.tfstate"
    region = "eu-central-1"
  }
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "notejam-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.terraform_remote_state.infra.outputs.ecs_execution_role_arn
#  task_role_arn            = data.terraform_remote_state.infra.outputs.ecs_task_role_arn

  container_definitions = jsonencode([{
    name      = "notejam"
    image     = var.container_image
    essential = true
    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
      protocol      = "tcp"
    }]
    environment = [
      {
        name  = "POSTGRES_USER"
        value = data.terraform_remote_state.infra.outputs.db_username
      },
      {
        name  = "POSTGRES_PASS"
        value = data.terraform_remote_state.infra.outputs.db_password
      },
      {
        name  = "POSTGRES_DB"
        value = data.terraform_remote_state.infra.outputs.db_name
      },
      {
        name  = "POSTGRES_URL"
        value = data.terraform_remote_state.infra.outputs.db_instance_endpoint
      }
    ]
    logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/notejam"
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "ecs"
        }
    }
  }])
}


resource "aws_ecs_service" "app_service" {
  name            = "notejam-service"
  cluster         = data.terraform_remote_state.infra.outputs.ecs_cluster_id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.terraform_remote_state.infra.outputs.private_subnet_ids
    security_groups = [data.terraform_remote_state.infra.outputs.security_group_id]
  }

  load_balancer {
    target_group_arn = data.terraform_remote_state.infra.outputs.notejam_target_group_arn
    container_name   = "notejam"
    container_port   = 8000
  }
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition
    ]
  }
}
