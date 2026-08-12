# Runtime topology

```mermaid
flowchart LR
  Client["Web development server\n(separate foodmind-web repository)"] --> Backend["Backend :8080"]
  Backend --> Chat["Chatbot :8001"]
  Backend --> Cooking["Cooking Agent :8003"]
  Backend --> Recommendation["Recommendation :8004"]
  Recommendation --> Inference["Inference :8002"]
  Backend --> Postgres["PostgreSQL 18.4 :5432"]
  Backend -. optional media .-> MinIO["MinIO :9000"]
  Model["ML source artifact"] --> Package["model-package job"] --> Inference
  Chat -. optional DeepSeek .-> DeepSeek["DeepSeek"]
  Cooking -. optional DeepSeek .-> DeepSeek
  Recommendation -. optional DeepSeek .-> DeepSeek
```

All calls between Backend and Agents use a private service token. Chatbot's
read-only Backend tools additionally carry a short-lived user delegation token;
the tool remains scoped to the requesting user's authorised records, products,
and places. No Compose secret is logged by health checks or the model build.

The model package job takes the versioned source artifact from the ML submodule
and generates `manifest.json` plus the six-feature runtime package in a named
volume. Inference starts only after that job succeeds, and Recommendation
starts only after Inference is healthy.
