#!/usr/bin/env bash
set -euo pipefail

# Looks up the ARN of this account's AWS-managed SERVICE-dimensional Cost
# Anomaly Detection monitor for the aws_ce_anomaly_subscription's
# monitor_arn_list. AWS auto-creates exactly one per account
# ("Default-Services-Monitor"), and that monitor type is capped at 1 per
# account, so Terraform can't create its own without colliding with the same
# quota. There is no aws_ce_anomaly_monitor data source to look it up
# natively, hence this external data source.

aws ce get-anomaly-monitors --output json | python3 -c '
import json, sys

monitors = json.load(sys.stdin)["AnomalyMonitors"]
service_monitor = next(m for m in monitors if m["MonitorDimension"] == "SERVICE")
print(json.dumps({"arn": service_monitor["MonitorArn"]}))
'
