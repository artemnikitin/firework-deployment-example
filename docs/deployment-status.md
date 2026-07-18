# Deployment status access

The control plane has two public origins:

- `api_url` / `status_domain` — the authenticated deployment UI and read-only API
- `events_webhook_url` — the GitHub webhook endpoint only; do not use it for the UI or `fireworkctl`

The operator token is stored in the provider's secret manager. Terraform outputs
the secret identifier, not the token value.

## AWS

Run these commands from `terraform/control-plane/aws` after the stack is
deployed:

```bash
STATUS_URL="$(terraform output -raw api_url)"
TOKEN_FILE="$PWD/operator-token"

umask 077
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw operator_token_secret_arn)" \
  --query SecretString --output text > "$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
```

## GCP

Run these commands from `terraform/control-plane/gcp` after the control plane
and Events edge have been applied. `gcloud` must use the same project as the
Terraform stack (add `--project "$GCP_PROJECT"` if it is not your active
project):

```bash
STATUS_URL="$(terraform output -raw api_url)"
TOKEN_FILE="$PWD/operator-token"

umask 077
gcloud secrets versions access latest \
  --secret="$(terraform output -raw operator_token_secret_id)" > "$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
```

## Open the UI

Open the value of `STATUS_URL` in a browser. When the login page asks for the
operator token, paste the contents of `TOKEN_FILE` (for example, on macOS run
`pbcopy < "$TOKEN_FILE"` and paste). The token is the same one used by the CLI.

## Connect `fireworkctl`

Use the status URL and token file together:

```bash
fireworkctl --endpoint "$STATUS_URL" --token-file "$TOKEN_FILE" nodes
```

For a persistent CLI configuration and command examples, see the
[`fireworkctl` user guide](https://github.com/artemnikitin/firework/blob/deployment-status/docs/fireworkctl.md).

Keep the token file mode `0600` and out of source control. If the token is
rotated, publish a new secret version and restart the control-plane API role so
it reads the new value; existing UI sessions then need to log in again.
