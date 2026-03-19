# Contributing

## Chart version (`version` in `chart/Chart.yaml`)

The chart’s `version` field must change whenever we publish a new chart revision. **If you edit the chart by hand** (anything that is not produced solely by the automated GitOps Promoter update flow), **bump the patch version in the same pull request** so installs and Artifact Hub show a new chart release for that change.

Examples of changes that require a manual patch bump:

- Edits to templates, `values.yaml`, RBAC, webhooks, or docs that ship with the chart
- Bug fixes or behavior changes outside the version-update automation

The workflow that updates GitOps Promoter (see `.github/workflows/update-gitops-promoter-version.yaml`) already bumps `version` according to app semver; you do not need an extra bump **only** for files that PR updates via KubeBuilder and `hack/update-controllerconfiguration.sh`.

## Controller configuration defaults

Default `ControllerConfiguration` **spec** lives in `chart/values.yaml` under `controllerConfiguration`, inside the `# BEGIN controllerConfiguration` / `# END controllerConfiguration` markers. Do not edit that block by hand: it is copied from upstream [`config/config/controllerconfiguration.yaml`](https://github.com/argoproj-labs/gitops-promoter/blob/main/config/config/controllerconfiguration.yaml) by:

```bash
./hack/update-controllerconfiguration.sh --gitops-promoter-repo /path/to/gitops-promoter
```

The Helm template `chart/templates/extra/controllerconfiguration.yaml` injects that structure into the `ControllerConfiguration` CR. Users override or extend behavior by changing `controllerConfiguration` in their own values when installing the chart.

After changing the sync script or the template, run `helm lint chart` and `helm template` locally before opening a PR.
