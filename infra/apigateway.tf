# =============================================================================
# Vaakya Infrastructure — API Gateway HTTP API
# =============================================================================

resource "aws_apigatewayv2_api" "api" {
  name          = "vaakya-api-${var.stage}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.stage == "prod" ? ["https://vaakya.app"] : ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

# --- JWT Authorizer (Firebase Auth) ---

resource "aws_apigatewayv2_authorizer" "firebase" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "firebase-jwt-${var.stage}"

  jwt_configuration {
    audience = [var.firebase_project_id]
    issuer   = "https://securetoken.google.com/${var.firebase_project_id}"
  }
}

# --- Routes ---

# Default route: requires Firebase JWT auth
resource "aws_apigatewayv2_route" "default" {
  api_id             = aws_apigatewayv2_api.api.id
  route_key          = "$default"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.firebase.id
}

# Public routes (no auth required)
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "share_resolve" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /share/{token}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# --- Stage ---

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
