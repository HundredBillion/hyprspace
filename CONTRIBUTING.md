# Contributing

* Make your patch, commit message and tests look like the ones that are already in the repo
* Every behavior change needs a test. Run `./swift-test.sh` before you submit
* New commands need documentation in `docs/hyprspace-<command>.adoc` and an entry in `docs/commands.adoc`.
  Run `./generate.sh --ignore-xcodeproj` to regenerate the help files
* See [dev-docs/development.md](./dev-docs/development.md) for build instructions
