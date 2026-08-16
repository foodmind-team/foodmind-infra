# FoodMind Stable Repository Tags - 2026-08-15

**Purpose:** Record the reviewed cross-repository source baselines used for the FoodMind recommendation showcase and collaborative-filtering release evidence.

**Verification date:** 2026-08-15
**Authoritative source:** Each repository's GitHub `origin` remote

## Stable tag inventory

| Repository | Stable tag | Peeled commit SHA |
| --- | --- | --- |
| [Backend](https://github.com/foodmind-team/foodmind-backend) | [`user-centered-recommendation-showcase-stable-20260815`](https://github.com/foodmind-team/foodmind-backend/tree/user-centered-recommendation-showcase-stable-20260815) | `11c7b30e6573c3f9fd82c9a5670cfd7e2a7d1d9b` |
| [Intelligence](https://github.com/foodmind-team/foodmind-intelligence) | [`collaborative-filtering-stable-20260815`](https://github.com/foodmind-team/foodmind-intelligence/tree/collaborative-filtering-stable-20260815) | `92c4e3ecb7cdd7abd8df0e901e9616f06a5ed613` |
| [Web](https://github.com/foodmind-team/foodmind-web) | [`user-centered-recommendation-showcase-stable-20260815`](https://github.com/foodmind-team/foodmind-web/tree/user-centered-recommendation-showcase-stable-20260815) | `eb3abfcbbed08a2627dd61c9464c91af87072af1` |
| [Android](https://github.com/foodmind-team/foodmind-android) | [`user-centered-recommendation-showcase-stable-20260815`](https://github.com/foodmind-team/foodmind-android/tree/user-centered-recommendation-showcase-stable-20260815) | `3083e01b2f06fe30db7e28274ef2c813d6f3ebea` |
| [Infra](https://github.com/foodmind-team/foodmind-infra) | [`user-centered-recommendation-showcase-stable-20260815`](https://github.com/foodmind-team/foodmind-infra/tree/user-centered-recommendation-showcase-stable-20260815) | `1d562a5ca63ea17949f07f8d023c2e35652c8159` |
| [ML](https://github.com/foodmind-team/foodmind-ml) | [`collaborative-filtering-stable-20260815`](https://github.com/foodmind-team/foodmind-ml/tree/collaborative-filtering-stable-20260815) | `04b7f57669fdf8c3c6d522d7f3f507d1b820f0f0` |
| [Docs](https://github.com/foodmind-team/foodmind-docs) | [`user-centered-recommendation-showcase-stable-20260815`](https://github.com/foodmind-team/foodmind-docs/tree/user-centered-recommendation-showcase-stable-20260815) | `6586f1f9a00d69cc01401dd744d2a27797c6168d` |

## Annotated tag verification

All seven entries are annotated tags. For an annotated tag, `git ls-remote` returns both the tag object and its peeled commit:

```bash
git ls-remote --tags origin \
  'refs/tags/TAG_NAME' \
  'refs/tags/TAG_NAME^{}'
```

The first result is the annotated tag object. The `^{}` result is the source commit recorded in the table above and is the value to use when comparing source code or release evidence.

The verified tag-object SHAs are retained below for audit purposes:

| Repository | Annotated tag-object SHA |
| --- | --- |
| Backend | `b20601b7d92ea9f41889e3503f4e1c1caaff8b5e` |
| Intelligence | `e2564566af31eb8f0fe605220795aeff11d6a80b` |
| Web | `07787db32104a6b69a8ddd8473416ef0fba0f972` |
| Android | `8aaf0a0c294465e1caaca5941a46f1e27db205dd` |
| Infra | `8614b5ffb40a99b155d0d7c0ff0ced644728b379` |
| ML | `9cc8904ee64f18393feadbf9e180feb32851403e` |
| Docs | `add36d9357155fa680102797c9bbb6f5397416e0` |

## Intended use

- Use these tags as human-readable, immutable source baselines for the classroom showcase and supporting evidence.
- Use the peeled 40-character commit SHAs for exact source comparisons and automated validation.
- Continue to use full Amazon ECR `@sha256:...` image digests in deployment manifests; Git tags identify source code but do not replace deployed-artifact digests.
- Do not move or recreate these tag names. A correction should use a new tag and a new dated inventory.

## Scope note

The tag names intentionally differ by repository. Intelligence and ML use the collaborative-filtering baseline because they own the collaborative model and inference implementation. Backend, Web, Android, Infra, and Docs use the broader user-centered recommendation showcase baseline.
