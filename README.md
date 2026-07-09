# Terraform infrastructure

The Terraform configuration for this setup lives under the [terraform](terraform) folder. It provisions a VPC, public/private subnets, an application load balancer, an EC2 Auto Scaling group, an RDS PostgreSQL instance, IAM roles, and Secrets Manager-backed database credentials.

Security note: the EC2 instances use an IAM instance profile with SSM permissions, so the deployment avoids exposing SSH on port 22. Access is handled through AWS Systems Manager Session Manager instead of open inbound SSH.

Copy [terraform/terraform.tfvars.example](terraform/terraform.tfvars.example) to [terraform/terraform.tfvars](terraform/terraform.tfvars) for local values before running Terraform.

The one-time [terraform/bootstrap](terraform/bootstrap) config creates the S3 bucket and DynamoDB table used by the main config's remote state backend.

## Backup strategy

The RDS instance ([terraform/rds.tf](terraform/rds.tf)) takes automated daily backups with a 7-day retention period (`db_backup_retention_period` in [terraform/variables.tf](terraform/variables.tf)), during a defined backup window (`03:00-04:00` UTC) that doesn't overlap the weekly maintenance window (`mon:04:30-mon:05:30` UTC).

This gives point-in-time recovery to any second within the last 7 days:

```
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier dev-postgres \
  --target-db-instance-identifier dev-postgres-restored \
  --restore-time 2026-07-01T12:00:00Z
```

(Restoring always creates a new instance — RDS can't restore in place.)

`skip_final_snapshot = true` is a deliberate trade-off for this assignment: it lets `terraform destroy` tear down the DB cleanly without needing a unique final-snapshot name each time. In production, that would instead be `skip_final_snapshot = false` with `deletion_protection = true`, so accidental deletion can't skip a final backup.

## Monitoring dashboards

[grafana](grafana) contains dashboard-as-code for two Grafana dashboards (Infrastructure: app EC2 + RDS CPU; Application: app request rate + DB request rate) backed directly by CloudWatch — no extra infra to deploy. See [grafana/README.md](grafana/README.md) for setup.

## Sample app

[app](app) contains a minimal Flask app (with unit + integration tests and a `Dockerfile`) used to exercise the CI/CD pipeline below. The EC2 instances run it as a Docker container, pulling the image tag stored in SSM Parameter Store (`/dev/app/image-tag`) from ECR at boot.

## CI/CD pipeline

Branch flow: feature branches → PR into `develop` (CI checks, auto-deploy on merge) → PR into `main` (CI checks, deploy to production behind manual approval on merge).

| Workflow | Trigger | Does |
|---|---|---|
| [ci-develop.yml](.github/workflows/ci-develop.yml) | PR → `develop` | unit + integration tests, dependency vulnerability scan (Trivy), Docker build check |
| [ci-main.yml](.github/workflows/ci-main.yml) | PR → `main` | same checks, gating the develop→main promotion |
| [cd-develop.yml](.github/workflows/cd-develop.yml) | PR merged → `develop` | single `build-and-deploy` job: build image, scan image (Trivy), push to ECR, deploy (SSM param update + ASG instance refresh) |
| [cd-main.yml](.github/workflows/cd-main.yml) | PR merged → `main` | same single-job flow, gated by the `main` GitHub Environment's required reviewers |

Both CD workflows deploy to the same EC2 Auto Scaling group provisioned in Task 1 — there's a single environment, not separate staging/production stacks, to avoid doubling AWS cost (a second ALB + NAT Gateway are not Free Tier eligible). Merges to `develop` and `main` both update the same running instances; production deploys are just gated by approval.

Both CD workflows run as one job (`build-and-deploy`), not split into separate build/deploy jobs. For `cd-main.yml` this means the `main` environment's approval gate pauses the **entire** job — build and push included, not just the deploy step — since GitHub Environment protection rules apply at the job level.

Authentication to AWS uses GitHub's OIDC provider (no long-lived AWS keys in GitHub secrets) — see the `ci_deploy` IAM role in [terraform/iam.tf](terraform/iam.tf).

Repeated multi-step logic (running tests, image build+scan, deploy, Slack notification) is factored into local composite actions under [.github/actions](.github/actions), so each shows as a single named step in the workflow run instead of a wall of raw shell steps:

- `test-python-app` — setup Python, install deps, run unit + integration tests
- `docker-build` — build image, Trivy scan (pushing to ECR is a separate explicit step in the workflow)
- `deploy-ec2` — update the SSM image-tag parameter, trigger ASG instance refresh
- `notify-slack` — post a message to Slack (CI workflows use it with `if: failure()`; CD workflows use `if: always()` to report both successful and failed deploys)

### One-time manual setup required

1. **Production approval gate**: GitHub → repo Settings → Environments → New environment → name it `main` → add yourself (or others) as required reviewers. Without this, `cd-main.yml` runs immediately with no approval step.
2. **Slack notifications**: create a Slack Incoming Webhook and add its URL as a repo secret named `SLACK_WEBHOOK_URL` (Settings → Secrets and variables → Actions). Notification steps are set to `continue-on-error`, so the pipeline works without it, just silently skips the Slack post.