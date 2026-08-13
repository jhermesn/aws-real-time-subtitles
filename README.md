# AWS Real-Time Subtitles

Real-time speech-to-text and translation for live events. Speaker talks into their mic, translated subtitles appear fullscreen on their screen, and the audience reads them via screen share.

Fork this repo, run the bootstrap once, trigger a GitHub Actions workflow, and you have your own deployment in your AWS account.

## Architecture

![Architecture diagram](docs/architecture.png)

### How it works

**Organizer creates a room:**
1. Opens `/admin` from an allowed IP. The CloudFront Function `speaker-auth` blocks everyone else at the edge (WAF, if enabled, duplicates this as defense in depth).
2. Submits the form, which hits `POST /api/sign-room`. CloudFront's origin access control (OAC) SigV4-signs the request to the Lambda Function URL: there's no shared secret to configure, and the Lambda URL is never exposed in the browser bundle.
3. Lambda signs a token: `base64url(payload) + "." + base64url(HMAC-SHA256(payload, SIGNING_SECRET))`
4. AdminView builds the speaker URL and shows a copy button.

**Speaker presents:**
1. Opens the signed URL. CloudFront Function validates the HMAC and 8h expiry at the edge.
2. Clicks Start mic. Browser calls `getUserMedia({ audio: true })`.
3. Browser calls `GET /api/session` with the room token in an `X-Room-Token` header (not `Authorization`, which CloudFront's OAC overwrites with its own SigV4 signature on the way to the Lambda origin). The Lambda revalidates the token and vends short-lived STS credentials (`sts:AssumeRole`) scoped to Transcribe and Translate only: no Cognito Identity Pool, nothing valid without a live room token.
4. Browser opens a WebSocket audio stream to Amazon Transcribe Streaming.
5. Transcribe returns partial and final transcripts. Final phrases go to Amazon Translate, unless source and target language already match, in which case the transcript is shown as-is.
6. Translated text appears fullscreen. Audience watches via screen share, no separate URL or login. After 5 minutes without a final transcript, the stream auto-stops (mic-left-on protection); tap the mic to resume.

## Cost

All costs are pay-as-you-go. WAF is optional and off by default since the CloudFront Function already covers the IP allowlist and token checks for free.

**Fixed (always running): ~$0/month**
- S3 + CloudFront static requests: < $0.01/month
- Set `enable_waf = true` for ~$6/month (WAF WebACL + managed rule) if you need it documented as a compliance control.

**Per active speaker: ~$2.40/hour**
- Transcribe Streaming: $0.024/min
- Translate: ~$0.95/hr (approx. 63k chars at 150 wpm); $0 if speaker and subtitle language match

| Example | Cost |
|---------|------|
| 1 speaker, 1 hour | ~$2.41 |
| 1 speaker, full day (8h) | ~$19.28 |
| 5 speakers, 2 hours each | ~$24.08 |
| 10 speakers, 4 hours each | ~$96.32 |

Idle cost between events is effectively $0 with WAF off. Run the `destroy` workflow when not in use, and set a Cost Anomaly Detection alert email (`ALERT_EMAIL`) so an unexpected spend surfaces within hours instead of waiting on the monthly Budget threshold.

Both services have AWS Free Tier quotas that may cover small events in the first year.

## Prerequisites

- AWS account with admin access (bootstrap only)
- GitHub repository (forked from this one)
- AWS CloudShell or a local Terraform install

## Deployment

### Step 1: Bootstrap (once per account)

Run from AWS CloudShell or anywhere with AWS credentials and Terraform.

```bash
# Install Terraform in CloudShell (skip if already installed)
curl -fsSL https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip -o tf.zip
unzip -o tf.zip && mv terraform ~/.local/bin/ && rm tf.zip

# Clone your fork
git clone https://github.com/<your-org>/aws-real-time-subtitles.git
cd aws-real-time-subtitles

cp terraform/bootstrap/terraform.tfvars.example terraform/bootstrap/terraform.tfvars
# Edit: set prefix, aws_region, github_repo
# If a GitHub OIDC provider already exists in your account: set create_oidc_provider = false

cd terraform/bootstrap
terraform init
terraform apply
```

The output tells you exactly what to configure in GitHub:

```
github_secrets = {
  AWS_ACCOUNT_ID = "123456789012"
  SIGNING_SECRET = "(generate with: openssl rand -hex 32)"
}
github_variables = {
  TF_PREFIX       = "myevent"
  AWS_REGION      = "us-east-1"
  TF_STATE_BUCKET = "myevent-tfstate-123456789012"
  AWS_ROLE_ARN    = "arn:aws:iam::123456789012:role/myevent-github-actions"
  ADMIN_IPS       = "(your public IP + /32)"
}
```

### Step 2: Configure GitHub

In your forked repository:

**Secrets** (`Settings > Secrets > Actions`):
| Secret | Value |
|--------|-------|
| `AWS_ACCOUNT_ID` | from bootstrap output |
| `SIGNING_SECRET` | `openssl rand -hex 32`, keep it private |

**Variables** (`Settings > Variables > Actions`):
| Variable | Value |
|----------|-------|
| `TF_PREFIX` | from bootstrap output |
| `AWS_REGION` | from bootstrap output |
| `TF_STATE_BUCKET` | from bootstrap output |
| `AWS_ROLE_ARN` | from bootstrap output |
| `ADMIN_IPS` | comma-separated IPv4 CIDRs, e.g. `1.2.3.4/32`. Check with `curl -4 -s https://checkip.amazonaws.com` |
| `ADMIN_IPS_V6` | (optional) comma-separated IPv6 CIDRs if your browser connects via IPv6. Check with `curl -6 -s https://checkip.amazonaws.com` |
| `ALERT_EMAIL` | (optional) email for a Budget alert at $5/month + Cost Anomaly Detection at $10 |
| `ENABLE_WAF` | (optional) `true` to turn on the WAFv2 Web ACL, default `false` |

### Step 3: Deploy

Go to `Actions > deploy > Run workflow`.

When it finishes, the `app_url` Terraform output is your CloudFront URL (e.g. `https://dXXXXXXXXXXXX.cloudfront.net`). No custom domain by default.

## Usage

### Organizer

1. Open `<app_url>/admin` from your configured IP.
2. Fill in the room label, speaker language, and subtitle language.
3. Click **Generate speaker URL**.
4. Send the URL to the speaker.

There is no database. The generated URLs only exist in the AdminView tab. If you close the tab, you lose the list, but any URLs already sent to speakers remain valid for their full 8h. Speaker sessions run entirely in the speaker's own browser and are not affected by the organizer closing the admin tab.

### Speaker

1. Open the signed URL in any modern browser (Chrome, Firefox, Edge).
2. Grant microphone access when prompted.
3. Click **Start mic**.
4. Share your screen.
5. Speak. Subtitles appear within about 2 seconds.
6. Click **Stop** when done. If you go 5 minutes without speaking, the stream auto-stops; tap the mic to resume.

Speaker URLs are valid for 8 hours from when the organizer generated them. Renewing an active mic session (a periodic credential refresh, not a page reload) reuses the same token, so it works for the full 8h window as long as the tab stays open.

## Teardown

```
Actions > destroy > Run workflow
```

This empties the S3 app bucket and runs `terraform destroy`.

> The state bucket created by bootstrap has `prevent_destroy = true` and is not removed by the destroy workflow. Delete it manually if you no longer need it.

## Updating your IP

Change `ADMIN_IPS` in GitHub Variables and re-run the `deploy` workflow. Terraform updates the WAF IP set.

## License

MIT. See [LICENSE](LICENSE).