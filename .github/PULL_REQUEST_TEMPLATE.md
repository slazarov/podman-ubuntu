<!-- Thanks for contributing! Keep PRs focused; see CONTRIBUTING.md. -->

## What & why

<!-- What does this change and why? Link any related issue: Closes #NN -->

## Type of change

- [ ] `fix` — bug fix
- [ ] `feat` — new capability
- [ ] `ci` — CI/CD or workflow change
- [ ] `chore` / `docs` / `test` / `refactor`

## Checklist

- [ ] Commits follow **Conventional Commits** (`feat:`, `fix(ci):`, …)
- [ ] `shellcheck` is clean on touched scripts (or new findings are justified)
- [ ] `bash -n` passes on touched scripts
- [ ] Relevant `tests/*.sh` pass; added/updated a test if logic changed
- [ ] No hardcoded version/distro — values thread through `config.sh` (`${VAR:-default}`)
- [ ] Packaging touched? Exercised `package_all.sh` and confirmed `.deb` output (CI/VM)
- [ ] Docs updated if behavior/config/repo layout changed
- [ ] No secrets, credentials, or machine-local paths committed

## Testing

<!-- How did you verify this? macOS `bash -n` + unit tests, an Ubuntu VM/container
     build, a CI run, etc. Builds only run on Linux — see CONTRIBUTING.md. -->
