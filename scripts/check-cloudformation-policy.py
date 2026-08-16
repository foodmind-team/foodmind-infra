#!/usr/bin/env python3
"""Small, reviewable Compliance-as-Code policy for FoodMind CloudFormation."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml


class CloudFormationLoader(yaml.SafeLoader):
    pass


def intrinsic(loader: CloudFormationLoader, tag_suffix: str, node: yaml.Node) -> object:
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    return loader.construct_mapping(node)


CloudFormationLoader.add_multi_constructor("!", intrinsic)


def check_template(path: Path) -> list[str]:
    template = yaml.load(path.read_text(encoding="utf-8"), Loader=CloudFormationLoader)
    failures: list[str] = []
    for logical_id, resource in template.get("Resources", {}).items():
        resource_type = resource.get("Type")
        properties = resource.get("Properties", {})
        prefix = f"{path.name}:{logical_id}"
        if resource_type == "AWS::ECR::Repository":
            if properties.get("ImageTagMutability") != "IMMUTABLE":
                failures.append(f"{prefix} must use immutable image tags")
            if properties.get("ImageScanningConfiguration", {}).get("ScanOnPush") is not True:
                failures.append(f"{prefix} must scan images on push")
            if properties.get("EncryptionConfiguration", {}).get("EncryptionType") not in {"AES256", "KMS"}:
                failures.append(f"{prefix} must encrypt images at rest")
        elif resource_type == "AWS::EC2::Instance":
            if properties.get("MetadataOptions", {}).get("HttpTokens") != "required":
                failures.append(f"{prefix} must require IMDSv2 tokens")
        elif resource_type == "AWS::RDS::DBInstance":
            if properties.get("StorageEncrypted") is not True:
                failures.append(f"{prefix} must encrypt storage")
            if properties.get("PubliclyAccessible") is not False:
                failures.append(f"{prefix} must not be publicly accessible")
            if properties.get("ManageMasterUserPassword") is not True:
                failures.append(f"{prefix} must use an AWS-managed master password")
            if int(properties.get("BackupRetentionPeriod", 0)) < 7:
                failures.append(f"{prefix} must retain backups for at least seven days")
            if properties.get("DeletionProtection") is not True:
                failures.append(f"{prefix} must enable deletion protection")
        elif resource_type == "AWS::S3::Bucket":
            if resource.get("DeletionPolicy") != "Retain":
                failures.append(f"{prefix} must retain data on stack deletion")
            if resource.get("UpdateReplacePolicy") != "Retain":
                failures.append(f"{prefix} must retain data when replaced")
            public_access = properties.get("PublicAccessBlockConfiguration", {})
            for setting in (
                "BlockPublicAcls",
                "BlockPublicPolicy",
                "IgnorePublicAcls",
                "RestrictPublicBuckets",
            ):
                if public_access.get(setting) is not True:
                    failures.append(f"{prefix} must set {setting}=true")
        elif resource_type in {"AWS::IAM::Role", "AWS::IAM::ManagedPolicy"}:
            policy_documents = [policy.get("PolicyDocument", {}) for policy in properties.get("Policies", [])]
            if resource_type == "AWS::IAM::ManagedPolicy":
                policy_documents.append(properties.get("PolicyDocument", {}))
            for policy_document in policy_documents:
                for statement in nested_statements(policy_document.get("Statement", [])):
                    actions = statement.get("Action", [])
                    if isinstance(actions, str):
                        actions = [actions]
                    resource_value = statement.get("Resource")
                    if "secretsmanager:GetSecretValue" in actions and resource_value in {"*", None}:
                        failures.append(f"{prefix} must scope secretsmanager:GetSecretValue to an exact ARN")
    return failures


def nested_statements(value: object):
    if isinstance(value, dict):
        if "Effect" in value and "Action" in value:
            yield value
        for nested in value.values():
            yield from nested_statements(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from nested_statements(nested)


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit("usage: check-cloudformation-policy.py <template> [<template> ...]")
    failures = [failure for value in sys.argv[1:] for failure in check_template(Path(value))]
    if failures:
        print("CloudFormation compliance gate failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("CloudFormation compliance gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
