# 8byte-devops-assignment

## Terraform infrastructure

The Terraform configuration for this assignment lives under the [terraform](terraform) folder. It provisions a VPC, public/private subnets, an application load balancer, an EC2 Auto Scaling group, an RDS PostgreSQL instance, IAM roles, and Secrets Manager-backed database credentials.

Security note: the EC2 instances use an IAM instance profile with SSM permissions, so the deployment avoids exposing SSH on port 22. Access is handled through AWS Systems Manager Session Manager instead of open inbound SSH.

Copy [terraform/terraform.tfvars.example](terraform/terraform.tfvars.example) to [terraform/terraform.tfvars](terraform/terraform.tfvars) for local values before running Terraform.

The one-time [terraform/bootstrap](terraform/bootstrap) config creates the S3 bucket and DynamoDB table used by the main config's remote state backend.

## Sample app

[app](app) contains a minimal Flask app (with unit + integration tests and a `Dockerfile`) used to exercise the CI/CD pipeline below. The EC2 instances run it as a Docker container, pulling the image tag stored in SSM Parameter Store (`/dev/app/image-tag`) from ECR at boot.

## CI/CD pipeline

Branch flow: feature branches → PR into `develop` (CI checks, auto-deploy on merge) → PR into `main` (CI checks, deploy to production behind manual approval on merge).

| Workflow | Trigger | Does |
|---|---|---|
| [ci-develop.yml](.github/workflows/ci-develop.yml) | PR → `develop` | unit + integration tests, dependency vulnerability scan (Trivy), Docker build check |
| [ci-main.yml](.github/workflows/ci-main.yml) | PR → `main` | same checks, gating the develop→main promotion |
| [cd-develop.yml](.github/workflows/cd-develop.yml) | PR merged → `develop` | build image, scan image (Trivy), push to ECR, deploy (SSM param update + ASG instance refresh) gated by the `develop` GitHub Environment |
| [cd-main.yml](.github/workflows/cd-main.yml) | PR merged → `main` | same build/scan/push, then deploy gated by the `main` GitHub Environment's required reviewers |

Both CD workflows deploy to the same EC2 Auto Scaling group provisioned in Task 1 — there's a single environment, not separate staging/production stacks, to avoid doubling AWS cost (a second ALB + NAT Gateway are not Free Tier eligible). Merges to `develop` and `main` both update the same running instances; production deploys are just gated by approval.

Authentication to AWS uses GitHub's OIDC provider (no long-lived AWS keys in GitHub secrets) — see the `ci_deploy` IAM role in [terraform/iam.tf](terraform/iam.tf).

Repeated multi-step logic (running tests, build/scan/push, deploy, Slack notification) is factored into local composite actions under [.github/actions](.github/actions), so each shows as a single named step in the workflow run instead of a wall of raw shell steps:

- `test-python-app` — setup Python, install deps, run unit + integration tests
- `docker-build-push` — build image, Trivy scan, push to ECR
- `deploy-ec2` — update the SSM image-tag parameter, trigger ASG instance refresh
- `notify-slack-failure` — post a failure message to Slack

### One-time manual setup required

1. **Production approval gate**: GitHub → repo Settings → Environments → New environment → name it `main` → add yourself (or others) as required reviewers. Without this, `cd-main.yml`'s deploy job runs immediately with no approval step.
2. **Slack notifications**: create a Slack Incoming Webhook and add its URL as a repo secret named `SLACK_WEBHOOK_URL` (Settings → Secrets and variables → Actions). Notification steps are set to `continue-on-error`, so the pipeline works without it, just silently skips the Slack post.