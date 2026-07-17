#!/usr/bin/env python3
"""Create the Whisper Flow tables in a LOCAL DynamoDB so the cloud DB + auth
features can be tested on this machine with NO AWS account.

Pick a local engine (any one), then point this script + config.json at it:

  dynalite (pure Node, no Java/Docker — recommended here):
      npm install -g dynalite
      dynalite --port 8000 --path ./dynalite-data

  DynamoDB Local via Docker:
      docker run -p 8000:8000 amazon/dynamodb-local

Then:   python setup_local_db.py
And in config.json:  "dynamodb_endpoint_url": "http://localhost:8000"

Idempotent — re-running skips tables that already exist.
"""
import sys
import boto3
from botocore.exceptions import EndpointConnectionError, ClientError

ENDPOINT   = "http://localhost:8000"
REGION     = "us-east-1"
THROUGHPUT = {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}  # provisioned: works on dynalite + DynamoDB Local

# (table name, key schema, attribute defs)
KEYED = [
    {"AttributeName": "userId",    "KeyType": "HASH"},
    {"AttributeName": "timestamp", "KeyType": "RANGE"},
]
KEYED_ATTRS = [
    {"AttributeName": "userId",    "AttributeType": "S"},
    {"AttributeName": "timestamp", "AttributeType": "S"},
]
TABLES = [
    ("whisperflow-history",  KEYED, KEYED_ATTRS),
    ("whisperflow-feedback", KEYED, KEYED_ATTRS),
    ("whisperflow-events",   KEYED, KEYED_ATTRS),
    # users table for the local email/password login (single email partition key)
    ("whisperflow-users",
     [{"AttributeName": "email", "KeyType": "HASH"}],
     [{"AttributeName": "email", "AttributeType": "S"}]),
]


def main():
    db = boto3.resource(
        "dynamodb",
        region_name=REGION,
        endpoint_url=ENDPOINT,
        aws_access_key_id="local",      # local engines ignore credentials
        aws_secret_access_key="local",
    )
    try:
        existing = {t.name for t in db.tables.all()}
    except EndpointConnectionError:
        print(f"[ERROR] Could not reach a local DynamoDB at {ENDPOINT}.")
        print("        Start one first, e.g.:  dynalite --port 8000 --path ./dynalite-data")
        sys.exit(1)

    for name, key_schema, attrs in TABLES:
        if name in existing:
            print(f"[skip]    {name} already exists")
            continue
        try:
            db.create_table(
                TableName=name,
                KeySchema=key_schema,
                AttributeDefinitions=attrs,
                ProvisionedThroughput=THROUGHPUT,
            ).wait_until_exists()
            print(f"[created] {name}")
        except ClientError as e:
            print(f"[FAIL]    {name}: {e}")

    print("\nDone. The history/feedback/events tables (same keys) are what you'll")
    print("create in real AWS later; whisperflow-users is local-test only.")


if __name__ == "__main__":
    main()
