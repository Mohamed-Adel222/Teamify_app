# Teamify

Teamify is an AI-powered team collaboration platform designed to help students, freelancers, and teams manage projects, assign tasks intelligently, track progress, and improve productivity.

## Features

- User Authentication
- Project Management
- Task Management
- AI Task Allocation
- AI Delay Prediction
- Meeting Summaries
- AI Mentor
- AI Resume Builder
- Chat and File Sharing
- Email notifications (Resend; see `teamify_flask_backend/docs/EMAIL.md`)
- Cybersecurity Monitoring

## My Role: Cybersecurity Engineer

As the Cybersecurity Engineer in Teamify, I was responsible for designing and implementing the security layer of the platform.

My contributions included:

- Designed the security architecture for the platform.
- Secured authentication using JWT and bcrypt password hashing.
- Implemented Role-Based Access Control (RBAC).
- Protected AI endpoints using authentication, authorization, input validation, and logging.
- Implemented Fernet encryption for sensitive messages.
- Applied SHA-256 integrity verification for uploaded files.
- Designed login auditing and security alert mechanisms.
- Added rate limiting and account lockout logic for suspicious login attempts.
- Performed manual security testing for authentication bypass, role abuse, token tampering, and invalid inputs.
- Created security documentation, test cases, and mitigation strategies.

## Security Features

- JWT Authentication
- Password Hashing with bcrypt
- Role-Based Access Control
- Input Validation
- AI Endpoint Protection
- Login Logs
- Security Alerts
- Rate Limiting
- Account Lockout
- Fernet Encryption
- SHA-256 File Integrity Check

## Tech Stack

- Flutter
- Python
- Flask
- Firebase
- PostgreSQL
- Machine Learning
- JWT
- bcrypt
- Fernet
- SHA-256

## Project Structure

```text
Teamify/
├── teamify_flutter/
├── teamify_flask_backend/
├── .vscode/
├── pyrightconfig.json
└── run_flutter.ps1
