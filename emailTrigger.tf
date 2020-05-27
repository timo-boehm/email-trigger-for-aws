provider "aws" {
  profile = "default"
  region  = "eu-west-1"
}

locals {
  common_tags = {
    creator = "terraform"
    project = "email-trigger"
  }
  open_email = ["trigger@blogpostemailtrigger.de"]
}

# ---- SES ----

# Create an active Rule Set for incoming eMails
resource "aws_ses_active_receipt_rule_set" "trigger_rules" {
  rule_set_name = "trigger_rules"
}
# Add a rule that forwards incoming mails to SNS
resource "aws_ses_receipt_rule" "trigger_processing" {
  name          = "trigger_forwarding"
  recipients    = local.open_email
  enabled       = true
  rule_set_name = aws_ses_active_receipt_rule_set.trigger_rules.rule_set_name
  sns_action {
    topic_arn = aws_sns_topic.lambda_trigger.arn
    position  = 1
  }
}

# ---- SNS ----

# Topic that receives messages from SES and passes them to the Lambda Function
resource "aws_sns_topic" "lambda_trigger" {
  name = "lambda_trigger"
  tags = local.common_tags
}
# Topic that Lambda publishes the monitoring results to
resource "aws_sns_topic" "sender_monitoring" {
  name = "sender_monitoring"
  tags = local.common_tags
}

# ---- LAMBDA ----

# Zip the function code for lambda
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda.py"
  output_path = "lambda.zip"
}

# Create the execution role for the lambda function
resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda_exec_role"
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

# Create policy for lambda execution (logging and publishing)
resource "aws_iam_policy" "lambda_execution_policy" {
  name   = "lambda_execution_policy"
  path   = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
   {
     "Action": [
       "SNS:Publish"
     ],
     "Resource": "*",
     "Effect": "Allow"
   } 
  ]
}
EOF
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

# Create a Lambda Function that executes the code when triggered
resource "aws_lambda_function" "triggered_process" {
  function_name    = "triggered_process"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "lambda.lambda_handler"
  role             = aws_iam_role.lambda_exec_role.arn
  runtime          = "python3.8"
  tags             = local.common_tags
  environment {
    variables = {
      SNS_TOPIC = aws_sns_topic.sender_monitoring.arn
    }
  }
}

# Allow Lambda to get executed by SNS Topic
resource "aws_lambda_permission" "triggered_by_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.triggered_process.arn
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.lambda_trigger.arn
}

# Connect the Lambda Function to the topic via subscription
resource "aws_sns_topic_subscription" "sns_to_lambda" {
  topic_arn = aws_sns_topic.lambda_trigger.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.triggered_process.arn
}