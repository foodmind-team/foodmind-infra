FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir numpy==2.3.2 \
    && groupadd --gid 10001 foodmind \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin foodmind \
    && mkdir -p /model-package \
    && chown 10001:10001 /model-package

WORKDIR /ml
COPY artifacts/candidate/hybrid_lr_model.npz artifacts/candidate/hybrid_lr_model.npz
COPY scripts/build_runtime_package.py scripts/build_runtime_package.py

USER 10001:10001
ENTRYPOINT ["python", "scripts/build_runtime_package.py"]
