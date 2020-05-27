import re
import os
import boto3


def lambda_handler(event, context):
    """
    Basic example for a lambda function.
    """

    # Extract message string from the passed message
    sns_message = event["Records"][0]["Sns"]["Message"]
    
    # Extract email address of sender
    sender_regex = re.compile("source\":\"(.*?)\"")
    senders = re.findall(sender_regex, sns_message)
    
    # Publish message to SNS topic for monitoring
    sns_client = boto3.client("sns")
    sns_client.publish(
        TopicArn=os.environ["SNS_TOPIC"],
        Subject="New Request per Mail",
        Message=f"This person made a request: {senders}."
    )