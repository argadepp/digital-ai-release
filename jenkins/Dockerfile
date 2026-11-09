FROM jenkins/jenkins:lts-jdk21

USER root

ARG TERRAFORM_VERSION=1.11.4

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && chmod 0755 /usr/local/bin/terraform \
    && rm -f /tmp/terraform.zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
