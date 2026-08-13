#!/usr/bin/env python3
"""Reject high-risk or non-reproducible local Compose definitions before smoke tests."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


ONE_SHOT_SERVICES = {"minio-init", "model-package"}
SENSITIVE_ASSIGNMENT = re.compile(r"^\s+[A-Z0-9_]*(?:PASSWORD|SECRET|TOKEN|API_KEY):\s*(.*)$")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: check-compose-policy.py COMPOSE_SOURCE RENDERED_JSON")

    source_name, rendered_name = sys.argv[1:]
    source_path = Path(source_name)
    source = source_path.read_text(encoding="utf-8")
    rendered_text = sys.stdin.read() if rendered_name == "-" else Path(rendered_name).read_text(encoding="utf-8")
    rendered: dict[str, Any] = json.loads(rendered_text)
    services = rendered.get("services")
    if not isinstance(services, dict) or not services:
        raise SystemExit("Compose policy failed: rendered configuration has no services")

    errors: list[str] = []
    for service_name, service in services.items():
        if service.get("privileged") is True:
            errors.append(f"{service_name}: privileged containers are forbidden")
        if service.get("network_mode") == "host" or service.get("pid") == "host":
            errors.append(f"{service_name}: host namespaces are forbidden")
        if service_name not in ONE_SHOT_SERVICES and not service.get("healthcheck"):
            errors.append(f"{service_name}: long-running services require a healthcheck")

        for port in service.get("ports", []):
            host_ip = port.get("host_ip") if isinstance(port, dict) else None
            if host_ip not in {"127.0.0.1", "::1"}:
                errors.append(f"{service_name}: published ports must bind to loopback")

        image = service.get("image")
        if isinstance(image, str) and (image.endswith(":latest") or ":" not in image.split("/")[-1]):
            errors.append(f"{service_name}: images must not use an implicit or latest tag")

    for line in source.splitlines():
        match = SENSITIVE_ASSIGNMENT.match(line)
        if not match:
            continue
        value = match.group(1).strip().strip("\"'")
        if value and not value.startswith(("${", "$$")):
            errors.append(f"compose source contains a literal sensitive value: {line.strip()}")

    if errors:
        raise SystemExit("Compose policy failed:\n- " + "\n- ".join(errors))
    print(f"Compose policy passed for {len(services)} services.")


if __name__ == "__main__":
    main()
