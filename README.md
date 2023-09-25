# k

`k` is the CLI tool used to interact with the Reclaim the Stack platform. It wraps `kubectl` and some other CLI tools and interfaces with configured ArgoCD gitops repos.

## Installation

Note: A recent version of `ruby` is recommended to run `k`. You may get away with the MacOS default Ruby installation but there are probably commands which won't work correctly. We recommend a version manager such as [rbenv](https://github.com/rbenv/rbenv) to install and use the latest Ruby version. Once things stabilize we'll likely package `k` with a pre-baked Ruby runtime to avoid the dependency.

**Via Homebrew**

```
brew install --HEAD reclaim-the-stack/tap/k
```

**Without Homebrew**

Install the dependencies: [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)

Then download the latest k [release](https://github.com/reclaim-the-stack/k/releases) package and put it in your `PATH`.

### Configuration

The first step when using `k` will be to configure a "context". A context is a combination of:
1. A GitHub repository containing ArgoCD platform and applications manifests
2. A Kubernetes cluster (ie. a locally configured kubectl context)
3. A Docker registry + namespace containing Docker images to be deployed as applications

Run `k contexts:add <github-gitops-url>` to add your first context.

Note that `k` stores all its configuration in YAML at `~/.k/config`. Feel free to inspect this file and make changes by hand if you so desire.

### Usage

Run `k` to get a list of commands.

We don't provide any rigorous documentation as of yet. If you've used the Heroku CLI tool a lot of things will seem familiar. Feel free to explore the available commands and provide feedback if something is hard to understand or broken.
