# k

`k` is the CLI tool used to interact with the Reclaim the Stack platform. It wraps `kubectl` and some other CLI tools and interfaces with configured ArgoCD gitops repos.

## Installation

Note: A recent version of `ruby` is recommended to run `k`. You may get away with the MacOS default Ruby installation but there are probably commands which won't work correctly. We recommend a version manager such as [rbenv](https://github.com/rbenv/rbenv) to install and use the latest Ruby version. Once things stabilize we'll likely package `k` with a pre-baked Ruby runtime to avoid the dependency.

Via Homebrew:

```
brew install --HEAD reclaim-the-stack/tap/k
```

Without Homebrew:

Install the dependencies: [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl), [kail](https://github.com/boz/kail#installing), [kubeseal](https://github.com/bitnami-labs/sealed-secrets#installation) and [yq](https://github.com/mikefarah/yq#install)

Then download the [k](k) file from this repository, make it executable and put it in your PATH.

### Usage

Run `k` to get a list of commands.

We don't provide any rigorous documentation as of yet. If you've used the Heroku CLI tool a lot of things will seem familiar. Feel free to explore the available commands and provide feedback if something is hard to understand or broken.
