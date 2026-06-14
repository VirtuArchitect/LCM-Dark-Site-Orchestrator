# Best Practice Coding Repository Template

Use this repository as a starting point for production-grade projects. It
includes Codex instructions, testing standards, security review guidance, GitHub
templates, and CI placeholders.

## Included Standards

- `AGENTS.md`: Codex project instructions and definition of done.
- `TESTING_GUIDE.md`: testing strategy and smoke-test requirements.
- `SECURITY_REVIEW.md`: defensive security review checklist.
- `CODE_REVIEW.md`: review checklist and output format.
- `PENTEST_SCOPE_TEMPLATE.md`: authorization template for security testing.
- `CONTRIBUTING.md`: contribution workflow.
- `SECURITY.md`: vulnerability reporting policy.
- `.github/pull_request_template.md`: PR verification checklist.
- `.github/workflows/ci.yml`: customizable CI skeleton.

## First-Time Setup

1. Create a new repository from this template.
2. Replace placeholder project details in this `README.md`.
3. Update `AGENTS.md` with the exact install, lint, test, build, and run commands.
4. Customize `.github/workflows/ci.yml` for the project stack.
5. Enable branch protection and require CI checks before merge.
6. Add stack-specific source code under `src/` and tests under `tests/`.

## Definition of Done

Changes are complete only when implementation, tests, smoke testing, and any
required security review are finished or explicitly documented as blocked.

