#!/bin/bash
set -euxo pipefail

dnf install -y docker
systemctl enable --now docker

# CodeDeploy agent — the RPM is arch-independent (noarch, a Ruby
# script), so this is the same package regardless of Graviton vs x86.
dnf install -y ruby wget
cd /tmp
wget https://aws-codedeploy-${aws_region}.s3.${aws_region}.amazonaws.com/latest/codedeploy-agent.noarch.rpm
dnf install -y ./codedeploy-agent.noarch.rpm
systemctl enable --now codedeploy-agent

# CloudWatch agent, pointed at the log group Terraform created — actual
# container log shipping is `docker run --log-driver=awslogs` in the
# CodeDeploy ApplicationStart hook, this covers instance/system logs
# plus the memory/disk/CPU metrics EC2 doesn't report on its own.
#
# Metrics land in appointments/ContainerMetrics twice: per instance
# (InstanceId dimension, for drilling in) and rolled up across the
# fleet (aggregation_dimensions [[]], no dimensions at all). Alarms
# watch the roll-up because it's the one series that survives
# CodeDeploy replacing every instance on each blue/green deploy.
# Quoted heredoc: bash must not expand the agent's own $${aws:...}
# placeholders (Terraform's templatefile has already filled in ours).
dnf install -y amazon-cloudwatch-agent
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60
  },
  "metrics": {
    "namespace": "${metrics_namespace}",
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}"
    },
    "aggregation_dimensions": [[]],
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "drop_device": true
      },
      "cpu": {
        "measurement": ["cpu_usage_active"],
        "totalcpu": true
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${log_group}",
            "log_stream_name": "{instance_id}/system"
          }
        ]
      }
    }
  }
}
EOF
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# No secret *values* are ever written to disk by this script. It only
# records where CodeDeploy's ApplicationStart hook should fetch them
# from at deploy time (`aws secretsmanager get-secret-value`) — the
# instance role is scoped to read exactly this one secret ARN and
# nothing else (iam.tf). The other files here are non-secret config the
# start_container.sh hook (appspec.yml, in the app repo) needs and would
# otherwise have to hardcode/duplicate from Terraform.
mkdir -p /etc/appointments
echo "${secret_arn}"    > /etc/appointments/app_secret_arn
echo "${aws_region}"    > /etc/appointments/aws_region
echo "${database_host}" > /etc/appointments/database_host
echo "${db_username}"   > /etc/appointments/db_username
echo "${db_name}"       > /etc/appointments/db_name
echo "${app_port}"      > /etc/appointments/app_port
echo "${log_group}"     > /etc/appointments/log_group
echo "${health_check_path}" > /etc/appointments/health_check_path
