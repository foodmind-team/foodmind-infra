# FoodMind staging observability

This is an optional, cost-bearing extension to the single-instance staging environment. It is intentionally separate from `cloudformation.aws-demo.yaml`, so reviewing or merging the application release cannot silently enable CloudWatch ingestion or alarm charges.

## What it adds

- A retained CloudWatch Logs group with seven-day retention by default.
- Least-privilege log-stream write access attached to the existing EC2 role.
- Non-blocking Docker `awslogs` delivery for every FoodMind container.
- EC2 status-check and sustained high-CPU alarms.
- RDS sustained high-CPU and low-free-storage alarms.
- An SNS email subscription for `ALARM` and recovery notifications.

The EC2 and RDS alarms use standard AWS metrics; memory and filesystem utilisation still require CloudWatch Agent metrics and are not claimed by this stack.

## Deployment order

Deploy the observability stack before enabling the Compose override. Reversing the order causes Docker startup to fail because `awslogs-create-group` is deliberately disabled and the EC2 role cannot create arbitrary log groups.

```bash
aws cloudformation deploy \
  --stack-name foodmind-staging-observability \
  --template-file cloudformation.observability.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    AppRoleName=foodmind-demo-ec2-role \
    AppInstanceId=REPLACE_INSTANCE_ID \
    DatabaseInstanceIdentifier=foodmind-demo-db \
    AlertEmail=REPLACE_OPERATIONAL_EMAIL
```

After the stack reaches `CREATE_COMPLETE`:

1. Confirm the AWS SNS subscription from the operational mailbox.
2. Set these values in the protected EC2 `.env.aws` file:

   ```text
   FOODMIND_CLOUDWATCH_LOGS_ENABLED=true
   CLOUDWATCH_LOG_GROUP=/foodmind/staging/containers
   ```

3. Deploy a tested release. Both manual and continuous-delivery scripts automatically add `compose.aws-cloudwatch-logs.yaml` when the flag is true.
4. Confirm every expected container has a current log stream and all four alarms have left `INSUFFICIENT_DATA`.
5. Trigger a controlled alarm test or temporarily lower one threshold, capture the notification, then restore the reviewed template value.

Do not place credentials, bearer tokens, cookies, presigned URLs, personal data, or raw user prompts in logs. The application-level redaction tests remain a required control; CloudWatch is not a redaction boundary.

## Rollback

Set `FOODMIND_CLOUDWATCH_LOGS_ENABLED=false` and redeploy before deleting the observability stack. Stack deletion removes the IAM policy, alarms, topic, and subscription. The log group is retained to avoid accidental evidence loss and must be deleted separately only after an explicit retention decision.
