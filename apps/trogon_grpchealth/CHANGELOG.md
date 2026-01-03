# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-01-02

### Added

- Initial release with gRPC health check service
- Macro-based service generation using `use Trogon.GrpcHealth.StaticHealth`
- Dynamic service health status from application configuration
- Compatibility with Google's gRPC health check protocol
- Integration with standard tools: `grpcurl`, `grpc-health-probe`, Kubernetes
