# Security Policy

Voltune intentionally performs privileged Windows operations. Treat every change that touches services, registry, networking, Appx packages, or boot configuration as security-sensitive.

## Supported versions
Only the latest tagged release is supported during the pre-1.0 period.

## Reporting a vulnerability
Please do not open a public issue for a vulnerability that could enable privilege escalation, command injection, unsafe file deletion, or destructive system changes. Use GitHub's private vulnerability reporting feature when enabled on the repository.

## Project guarantees
Voltune aims to be safe by default, but it is not a security boundary. Advanced Mode intentionally exposes operations with greater system impact. Review changes before running them on production or business-critical machines.
