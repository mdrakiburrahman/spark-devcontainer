<!-- PROJECT LOGO -->
<p align="center">
  <img src="https://spark.apache.org/images/spark-logo-rev.svg" alt="Logo" width="30%">
  <h3 align="center">Apache Spark VSCode Devcontainer</h3>
  <p align="center">
    A Visual Studio Code Devcontainer for Apache Spark.
    <br />
    <br />
    ·
    <a href="https://code.visualstudio.com/docs/devcontainers/containers">Devcontainer Overview</a>
    ·
    <a href="https://blog.fabric.microsoft.com/en-us/blog/sql-telemetry-intelligence-how-we-built-a-petabyte-scale-data-platform-with-fabric?ft=01-2024:date">Spark Devcontainer benefits</a>
    .
  </p>
</p>

## Context

This repository contains the automation necessary to build and push an Apache Spark Devcontainer.

## Quickstart

1. Follow [CONTRIBUTING](contrib/README.md) to get a windows devbox ready to build the devcontainer
2. Run:

   ```bash
   npx nx run devcontainer:publish --skip-nx-cache
   ```