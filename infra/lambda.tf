# =============================================================================
# Vaakya Infrastructure — Lambda Function (API)
# =============================================================================

resource "aws_lambda_function" "api" {
  function_name = "vaakya-api-${var.stage}"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:latest"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 30
  memory_size   = var.stage == "prod" ? 512 : 256

  environment {
    variables = {
      VAAKYA_ENV = var.stage
      # Non-secret config comes from YAML inside the container.
      # Secrets come from SSM at runtime (fetched by the app).
    }
  }

  tags = {
    Name = "vaakya-api-${var.stage}"
  }
}
