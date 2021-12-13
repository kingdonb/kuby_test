# README

## Using `kuby` in your Rails app

## How to integrate GitHub Actions

There are two main requirements when deploying with Kuby: an environment which can Docker Build, and Ruby must be installed in order to run `kuby`.

Kuby itself runs Docker and within Docker must install Kuby as well. So there are two places in the CI process where gems will be installed: inside and outside of the Docker image.

If both cannot be cached effectively, then many minutes will be wasted every build re-installing Ruby gems and re-compiling native extensions every build. Correct configuration of caching avoids this waste that slows our build and does not add value.

### Caching Rubygems Installation

The `ruby/setup-ruby@v1` action installs Ruby and provides caching of the bundle artifacts (outside of the Docker image.)

```yaml
    - uses: ruby/setup-ruby@v1
      with:
        ruby-version: 2.7.5
        bundler-cache: true
        cache-version: 1
```

You can increment `cache-version` to destroy the cache when and if it ever gets corrupted. This step runs `bundle install`.

No configuration is needed; the [GitHub Actions caching service](https://github.com/marketplace/actions/cache) is underneath.

### Building and Pushing Docker Image Layers

Kuby uses Docker to build and push container images to an image registry.

This section of `kuby.rb` tells Kuby where our images are stored, and what creds can be used to push or pull them:

```ruby
Kuby.define 'KubyTest' do
  environment :production do
    # ...
    docker do
      credentials do
        username app_creds[:KUBY_DOCKER_USERNAME]
        password ENV['GITHUB_TOKEN']
        email app_creds[:KUBY_DOCKER_EMAIL]
      end
    
      image_url 'ghcr.io/kingdonb/kuby-tester'
    end
  # ...
```

In `credentials.yml.enc` we have stored some encrypted values in `app_creds` according to [the Kuby guide](https://getkuby.io/docs/#configuring-docker). We placed a value in `KUBY_DOCKER_USERNAME` that is used as an `imagePullSecret`, and a corresponding token in `KUBY_DOCKER_PASSWORD` which should not be given write access to the package registry. This is for secure image pull access only, (and could be omitted altogether for public images.)

By using an environment variable instead of storing a PAT in the rails encrypted credentials file, we can enable using ambient credentials with Kuby to substitute a token with `write:packages` when needed. If a private repo is used, be aware that a token with `read:packages` will also be needed at build-time, as Kuby assets images include a copy of the assets' prior version, so the builder needs to be able to pull from the registry.

We can add a repository secret `CR_PAT` (or anything else other than `GITHUB_TOKEN`) and populate it with a Personal Access Token scoped for `write:packages` as described in [GitHub Docs](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry). This may be helpful for creating a new package, when no existing package repository already falls within the git repository's scope.

If you still need to create a package registry on `ghcr.io`, you can start by generating a Personal Access Token now.

Creation of a new GitHub package happens implicitly when the first image is pushed. If the package registry name doesn't match the source repository, it may also be necessary to [connect the repo to the package](https://docs.github.com/en/packages/learn-github-packages/connecting-a-repository-to-a-package) since GitHub won't be able to connect them implicitly.

Configure the package settings now, in case you would like to [make this registry public](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)!

#### Using Ambient Credentials on GitHub Actions

```yaml
jobs:
  build:
    permissions:
      packages: write
      contents: read
```

After properly associating our Git repo with the package, we can update our workflows as above. It may also be necessary to grant write access to workflows; review the GitHub documentation linked above for more information.

With that configuration, the ambient `GITHUB_TOKEN` can be used for pushes. This mitigates a risk of compromise; since no one will need to handle a Personal Access Token with `write:packages` ever again, it can be deleted now and will not be at risk any further.

It may have been unnecessary to generate a PAT in order to create a new GHCR.io package/image registry, but we can now delete it, or let it expire after our package registry is created!

```yaml
    - run: bundle exec kuby -e production build
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}

    - run: bundle exec kuby -e production push
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
```

#### Encrypted Credentials with Kuby and GitHub Actions

`GITHUB_TOKEN` is an ambient secret and is populated automatically by GitHub Actions with a Repository-scoped secret.

Populate another secret for `RAILS_MASTER_KEY` in order for Kuby to build assets. Save a copy of `config/master.key` securely, and destroy the original! I have simply moved mine outside of the repository path into my project workspace, on the laptop.

```
export RAILS_MASTER_KEY=$(cat ../kuby_test-master.key)
```

Kuby always expects to find a `RAILS_MASTER_KEY` in the environment at `kuby build`-time.

Depending on your app initializers other access could also be needed.

We should also note that `kuby build` is not running any tests. If your app has tests, then make another workflow and run them separately.

### Secrets in `credentials.yml.enc`

You must have added several variables to the Rails encrypted credentials store for Kuby during Kuby setup:

```shell
secret_key_base: 5b12d6fe5afdac2f910cf3d316ea1bc9f6d779f4950f8333e2c7a6a6b85b67dbb9665deb3f380f881f0ebdc2de9acb371efb2c5caa863d8c359eded864d4e547
# Rails has randomly generated a secret_key_base, above. Run `rails credentials:edit` and provide your own values for the variables below:

KUBY_DOCKER_USERNAME: kingdonb
KUBY_DOCKER_PASSWORD: ghp_XXXinvalid12345abcdefghijklmnopqrstu
KUBY_DOCKER_EMAIL: example@example.com
KUBY_DB_USER: kuby_test
KUBY_DB_PASSWORD: Oosh0sadooz5osh@eir2Ioj
KUBY_DIGITALOCEAN_ACCESS_TOKEN: XXXinvalidHuferiuKe4Yexoo9nohngaen3aiZieQuecoh6quai2ielae8ongoob
KUBY_DIGITALOCEAN_CLUSTER_ID: 8704193d-a88c-41b9-b9c0-cd290774d34e
```

Depending on your choice of Kubernetes hosting provider, you may or may not have to include any access tokens or database passwords. The remaining details of this configuration are out of scope for this document.

The docker password will be used as an `imagePullSecret` in the default configuration from Kuby. Our configuration doesn't use this value at all. Setting up `imagePullSecrets` on your manifests may be necessary for many registries simply to prevent rate limiting. Kuby generates a `dockerconfigjson` secret, based on your configuration from the `docker`.`credentials` block referenced before.

### Caching Docker: Option 1 - Self-Hosted Runner

The `kuby build` or `kuby -e production build` step can complete in a few seconds if caches are perfect and no assets have changed. If assets must be precompiled or recompiled, then that would be the only layer that should need to be recompiled. Kuby creates a complex Dockerfile in-memory to decide this.

With an ideal caching configuration, builds that do not update `Gemfile` or `Gemfile.lock` should be possible to finish in well under 2 minutes. (Precise benchmarks were not available at press time because my workstation is an M1 Macbook Pro, so everything runs in `x86_64` emulation and is much slower than on GitHub. The caching configuration at press time was also not ideal.)

This option should be very easy to achieve if you're already using a self-hosted runner with the same architecture as your cloud. Simply arrange for the workloads to run on the same host every time, and there will be no requirement for any caches to be transported from one build node to the next.

Problem with this idea: maybe that node lives forever on the public cloud somewhere, and that costs a lot. GitHub Actions is free for public repos, but self-hosted runners take up physical real-estate and cost electricity to host, which is all not free. So this is not an actual free solution.

Ideally, our caching solution would not require for builds to use a self-hosted runner, or to always land each build for our project on the same node every time. Configuring a self-hosted runner is therefore discounted as a solution, and further exploration is beyond the scope of this document.

### Caching Docker: Option 2 - Buildkit / Buildx Local Cache

If `Kuby` can run builds through `docker buildx build`, then certain other options become available.

Look to [Flux's image reflector controller](https://github.com/fluxcd/image-reflector-controller/blob/62c06ea58cd14072fde2c9ada7c6970dedf580e5/.github/workflows/build.yaml#L57-L59) for inspiration. This approach also uses `actions/cache@v1`.

This option has not been fully explored yet, but any project without permanently hosted resources of their own can follow Flux's example.

Running builds are a job of the project infrastructure, and they can use the local cache when nodes are reused. GitHub will sometimes reuse our nodes, and we can opportunistically take advantage of that event when it does occur.

Expiring or invalidation of the cache will cause some builds to take longer. This is not a disaster, but should be considered as necessary and expected; builds will always take up some time, and no matter how well our cache strategies work, we will rarely if ever find them running at 100% hit ratios.

However, as the next option will show, depending on language runtimes, rebuilding a new container image from scratch might not always be necessary.

### Skipping Docker Build: Option 3 - Okteto CLI

If waiting 30 seconds between each push for CI to build and Kubernetes to deploy is still too long for your dev team's expectations or sensibilities, go ahead and build on something like Okteto where your changes [can be synced directly into a running pod](https://okteto.com/docs/samples/ruby/).

There you can run in `development` mode, taking advantage of every code hot-reloading feature that your language or chosen frameworks can provide! The Okteto CLI is completely open source and free for developers to use, and it can run dev pods on any Kubernetes cluster.

When implemented well, this approach can even help some members of your team participate in Ruby development while still avoiding a need to install or use Ruby locally. No one should let friends run `bundle install` on a laptop, (that's a job for robots in the cloud!)

We can spend some time to ensure we don't commit waste in our CI builds. But before spending too much time optimizing caches for every niche, we can look for solutions that help us to build less often.

If we can spend two minutes on a waste but "only this once," so that running a full build is not always a requirement of testing a change, then we will be able to run our sometimes-wasteful builds even less often! Now, let's try it out.
