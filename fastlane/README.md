fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios validate

```sh
[bundle exec] fastlane ios validate
```

Valida localmente pacotes e app, sem Apple; exige simulator_udid ou LINKA_SIMULATOR_UDID

### ios beta

```sh
[bundle exec] fastlane ios beta
```

TestFlight local autorizado: main limpa, SHA remoto, validate obrigatório e evidência por tentativa

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
