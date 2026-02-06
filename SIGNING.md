# Helm chart signing (Artifact Hub "Signed" badge)

The release workflow can sign the Helm chart with PGP so Artifact Hub shows the **Signed** badge and users can verify with `helm verify` or `helm install --verify`.

## One-time setup

### 1. Create or use a PGP key

**Helm’s signer only supports RSA keys.** Ed25519 and other modern key types (e.g. from `gpg --full-generate-key` defaults) will fail with “public key type: 22”. Create an RSA key: `gpg --full-generate-key` and when prompted choose **RSA and RSA**, 4096 bits. Do not use the default “Ed25519” option.

List your secret keys to get the key UID (name/email) and fingerprint:

```bash
gpg --list-secret-keys --keyid-format long
```

The `--key` value for Helm must be a **substring of the key's UID** (e.g. your email or name), not the fingerprint.

### 2. Export the private key

Export the private key in armored form for the GitHub secret:

```bash
gpg --export-secret-keys --armor <key-id>
```

Copy the output (including `-----BEGIN PGP PRIVATE KEY BLOCK-----` and `-----END PGP PRIVATE KEY BLOCK-----`).

### 3. Add GitHub repository secrets

In the repo: **Settings → Secrets and variables → Actions**, add:

| Secret | Description |
|--------|-------------|
| `HELM_SIGNING_PRIVATE_KEY` | The armored private key from step 2. |
| `HELM_SIGNING_KEY_NAME` | A substring of the key UID (e.g. email or name) used by `helm package --key`. |
| `HELM_SIGNING_PASSPHRASE` | (Optional) Passphrase for the key. Omit or leave empty if the key has no passphrase. |

### 4. Publish the public key

The release workflow automatically exports the public key and publishes it to gh-pages as `pgp_keys.asc` alongside `index.yaml` and the chart tarballs. No extra step needed—once signing is configured, the key is available at:

**https://argoproj-labs.github.io/gitops-promoter-helm/pgp_keys.asc**

### 5. Update Chart.yaml with the key fingerprint

In `chart/Chart.yaml`, replace the key fingerprint in the `artifacthub.io/signKey` annotation with your key fingerprint (from `gpg --list-secret-keys --keyid-format long`).

## What happens on release

When a new chart version is pushed to `main`:

- If `HELM_SIGNING_KEY_NAME` and `HELM_SIGNING_PRIVATE_KEY` are set, the workflow imports the key, runs `helm package --sign`, exports the public key to `docs/pgp_keys.asc`, and publishes the chart, its `.prov` file, and `pgp_keys.asc` to the `gh-pages` docs.
- If those secrets are not set, the chart is packaged without signing (no `.prov` file); the workflow still succeeds so you can enable signing later.

After the next release that includes a `.prov` file, Artifact Hub will show the Signed badge on its next index run.
