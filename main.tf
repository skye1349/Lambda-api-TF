// dependicies zip
data "archive_file" "layer_zip" {
  type        = "zip"
  source_file = "layer.zip"
  output_path = "layer.zip"
}
// zip files
data "archive_file" "create_note_lambda_zip" {
  type        = "zip"
  source_file = "create.js"
  output_path = "create_note_lambda.zip"
}

data "archive_file" "get_note_lambda_zip" {
  type        = "zip"
  source_file = "get.js"
  output_path = "get_note_lambda.zip"
}
//layer
resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name          = "my_layer"
  filename            = data.archive_file.layer_zip.output_path
  source_code_hash    = filebase64sha256(data.archive_file.layer_zip.output_path)
  compatible_runtimes = ["nodejs14.x"]
}
// create iam role for lambda & attachment
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "iam_lambda_access" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
// create API Gateway
resource "aws_api_gateway_rest_api" "MyDemoAPI" {
  name        = "MyDemoAPI"
  description = "This is my API for demonstration purposes"
}

//Define Lambda Function
resource "aws_lambda_function" "create_note" {
  filename      = "create_note_lambda.zip"
  function_name = "create_note"
  layers        = [aws_lambda_layer_version.lambda_layer.arn]
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "create.handler"
  runtime       = "nodejs14.x"
  source_code_hash = data.archive_file.create_note_lambda_zip.output_base64sha256
}

resource "aws_lambda_function" "get_note" {
  filename      = "get_note_lambda.zip"
  function_name = "get_note"
  layers        = [aws_lambda_layer_version.lambda_layer.arn]
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "get.handler"
  runtime       = "nodejs14.x"
  source_code_hash = data.archive_file.get_note_lambda_zip.output_base64sha256
}
//create method in API Gateway
resource "aws_api_gateway_resource" "MyDemoResource" {
  rest_api_id = aws_api_gateway_rest_api.MyDemoAPI.id
  parent_id   = aws_api_gateway_rest_api.MyDemoAPI.root_resource_id
  path_part   = "note"
}

resource "aws_api_gateway_method" "MyDemoMethodCreate" {
  rest_api_id   = aws_api_gateway_rest_api.MyDemoAPI.id
  resource_id   = aws_api_gateway_resource.MyDemoResource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "MyDemoMethodGet" {
  rest_api_id   = aws_api_gateway_rest_api.MyDemoAPI.id
  resource_id   = aws_api_gateway_resource.MyDemoResource.id
  http_method   = "GET"
  authorization = "NONE"
}

//integration API & Lambda
resource "aws_api_gateway_integration" "MyDemoIntegrationCreate" {
  rest_api_id = aws_api_gateway_rest_api.MyDemoAPI.id
  resource_id = aws_api_gateway_resource.MyDemoResource.id
  http_method = aws_api_gateway_method.MyDemoMethodCreate.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_note.invoke_arn
}

resource "aws_api_gateway_integration" "MyDemoIntegrationGet" {
  rest_api_id = aws_api_gateway_rest_api.MyDemoAPI.id
  resource_id = aws_api_gateway_resource.MyDemoResource.id
  http_method = aws_api_gateway_method.MyDemoMethodGet.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_note.invoke_arn
}

// make API have permission to Lambda
resource "aws_lambda_permission" "apigw_create_note" {
  statement_id  = "AllowExecutionFromAPIGatewayCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_note.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.MyDemoAPI.execution_arn}/*/${aws_api_gateway_method.MyDemoMethodCreate.http_method}${aws_api_gateway_resource.MyDemoResource.path}"
}

resource "aws_lambda_permission" "apigw_get_note" {
  statement_id  = "AllowExecutionFromAPIGatewayGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_note.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.MyDemoAPI.execution_arn}/*/${aws_api_gateway_method.MyDemoMethodGet.http_method}${aws_api_gateway_resource.MyDemoResource.path}"
}

//Deploy API Gateway
resource "aws_api_gateway_deployment" "MyDemoAPI" {
  depends_on = [aws_api_gateway_integration.MyDemoIntegrationCreate, aws_api_gateway_integration.MyDemoIntegrationGet]

  rest_api_id = aws_api_gateway_rest_api.MyDemoAPI.id
  stage_name  = "prod"
}

output "api_gateway_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.MyDemoAPI.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.MyDemoAPI.stage_name}${aws_api_gateway_resource.MyDemoResource.path}"
}