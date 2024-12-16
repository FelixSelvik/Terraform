resource "aws_lambda_function" "my_lambda" {
  filename      = "lambda_function/lambda_function.zip"  # Path to your Lambda zip file
  function_name = "myLambdaFunction"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"       # Replace with your function's handler
  runtime       = "python3.13"                           # Change according to your Lambda runtime

  environment {
    variables = {
      DB_HOST     = aws_instance.my_ec2.public_ip       # EC2 public IP as the database host
      DB_USERNAME = var.db_username
      DB_PASSWORD = var.db_password
      BUCKET_NAME = var.bucket_name
      DB_NAME     = var.db_name
    }
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# S3 permissions for the Lambda function
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name   = "LambdaS3PutObjectPolicy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_api_gateway" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.my_http_api.execution_arn}/*/*"
}

# API Gateway and integration configuration
resource "aws_apigatewayv2_api" "my_http_api" {
  name          = "my-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "my_lambda_integration" {
  api_id                = aws_apigatewayv2_api.my_http_api.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.my_lambda.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "my_lambda_route" {
  api_id    = aws_apigatewayv2_api.my_http_api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.my_lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "my_stage" {
  api_id     = aws_apigatewayv2_api.my_http_api.id
  name       = "prod"
  auto_deploy = true
}
