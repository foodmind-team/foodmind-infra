# FoodMind DevSecOps toolchain

This diagram reflects the implemented repositories and AWS staging path. Dashed elements are prepared in source but require deployment or repository-policy activation before they can be presented as operational controls.

```mermaid
flowchart LR
    Dev["Developer"] --> PR["GitHub pull request"]

    subgraph Repositories["GitHub repositories"]
        AppCI["Backend / Web / Android CI"]
        IntelCI["Intelligence quality, tests, contracts, security, image"]
        MlCI["ML quality, tests, pip-audit, licenses, Gitleaks"]
        InfraCI["Infra Compose validation and stack smoke test"]
    end

    PR --> AppCI
    PR --> IntelCI
    PR -.-> MlCI
    PR --> InfraCI

    AppCI --> Merge["Reviewed default branch"]
    IntelCI --> Merge
    MlCI -.-> Merge
    InfraCI --> Merge

    Merge --> Publish["GitHub Actions: publish immutable images"]
    Publish --> ECR["Amazon ECR private repositories\nimmutable tags + scan on push"]
    ECR --> Manifest["Digest-pinned release manifest"]
    Manifest --> Deploy["GitHub OIDC + AWS Systems Manager deployment"]
    Deploy --> EC2["EC2 staging host\nDocker Compose + Caddy"]
    EC2 --> RDS["Private encrypted RDS PostgreSQL"]
    EC2 --> S3["Private S3 media bucket"]

    EC2 -.-> Logs["CloudWatch Logs + EC2/RDS alarms"]
    Deploy -.-> ZAP["OWASP ZAP passive baseline"]
    ZAP -.-> Evidence["Versioned security report + CI artifact"]

    Protect["Required PR reviews and status checks"] -.-> PR

    classDef prepared stroke-dasharray: 5 5;
    class MlCI,Logs,ZAP,Evidence,Protect prepared;
```

## Where to demonstrate each control

| Control | Authoritative location | Presentation evidence |
| --- | --- | --- |
| Source and review | GitHub repository Pull requests and branch rules | Reviewed PR, required checks, protected default branch |
| CI quality gates | Each repository's **Actions** tab | Successful gate jobs and uploaded test evidence |
| Dependency and secret security | Intelligence and ML Actions workflows | `pip-audit`, license, Gitleaks, SBOM, Trivy results |
| Artifact integrity | Infra release manifest and Amazon ECR | SHA-256 image digests, immutable tags, scan-on-push |
| Deployment identity | Infra `Deploy staging` workflow | GitHub OIDC role session; no long-lived AWS key |
| Runtime isolation | EC2 security group and Docker Compose | Only ports 80/443 public; RDS private; services unexposed |
| Dynamic testing | Infra `Staging DAST` workflow | Initial findings, fixed headers, successful ZAP rescan artifact |
| Runtime monitoring | CloudWatch Logs, Alarms, SNS | Current streams, alarm states, confirmed notification |

Prepared controls shown with dashed lines must not be described as active until their PRs are merged and their runtime evidence is captured.
