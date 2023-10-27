# Rust Builder Image base on CentOS 7

Why? To cross build dynamically linked binaries with glibc 2.17, the minimal glibc version that rust toolchain supported and compatible with most linux distributions.

## How to use it

Put your rust toolchain version in `rust-toolchain`; and then use this template to run a GitHub Actions workflow in your project.

```yaml
name: Continuous Integration (CI)
on: [push]

jobs:
  test:
    runs-on: ubuntu-22.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: true
      - uses: Swatinem/rust-cache@v2
      - name: cargo test
        run: |
          rustup component add rustfmt
          cargo check
          cargo fmt --check
          cargo test --workspace
  release:
    name: release ${{ matrix.binary.name }} ${{ matrix.arch.name }}
    needs: [test]
    runs-on: ubuntu-22.04
    strategy:
      fail-fast: false
      matrix:
        binary:
          - workspace: .
            name: your-binary-name-here
        arch:
          - name: amd64
            runtime-image: "debian@sha256:9b42b2e7eddd84eaddb67b45567cdc0e03ec826bf252352f300147cfb8ce5a6d"
          - name: aarch64
            runtime-image: "debian@sha256:c583ed77e10b69b167c09cba3d82f903a9a7af481cbb75166d5307135f7b2c77"
    steps:
      - name: Checkout
        uses: actions/checkout@v3
        with:
          submodules: true
      - name: Setup QEMU
        if: matrix.arch.name != 'amd64'
        run: docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
      - name: Setup Rust
        run: |
          rm -rf ~/.cargo
          docker run -d --name=init \
            -v $PWD/${{ matrix.binary.workspace }}:/repo/ -w /repo \
            ghcr.io/innopals/rust-centos7:$(cat rust-toolchain)-${{ matrix.arch.name }} \
            tail -f /etc/issue
          # Initial cargo installation to be cached
          docker cp init:/root/.cargo ~/.cargo
          mkdir -p ${HOME}/.local/bin
          # Use cargo & rustc in the container to obtain rust version and to clean up artifacts
          cd ${HOME}/.local/bin
          echo '#!/bin/bash' > rustc
          echo 'docker exec init rustc $@' > rustc
          echo '#!/bin/bash' > cargo
          echo 'docker exec init cargo $@' > cargo
          chmod +x *
          rustc -vV
      - uses: Swatinem/rust-cache@v2
        with:
          key: ${{ matrix.binary.workspace }}/${{ matrix.binary.name }}-${{ matrix.arch.name }}
          cache-on-failure: true
          workspaces: ${{ matrix.binary.workspace }} -> target
      - name: Start Build Container
        run: |
          docker run -d --name=build \
            -v $PWD/${{ matrix.binary.workspace }}:/repo/ -v $HOME/.cargo:/root/.cargo -w /repo \
            ghcr.io/innopals/rust-centos7:$(cat rust-toolchain)-${{ matrix.arch.name }} \
            tail -f /etc/issue
      - name: Build Artifacts
        run: |
          docker exec build bash -c 'set -e
            cargo build --release
            strip target/release/${{ matrix.binary.name }}
            cp target/release/${{ matrix.binary.name }} target/release/${{ matrix.binary.name }}-${{ matrix.arch.name }}
          '
          sudo chown -R runner:docker ${{ matrix.binary.workspace }}/target
          sudo chown -R runner:docker $HOME/.cargo
      - name: Publish Artifacts
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v1
        with:
            files: |
              ${{ matrix.binary.workspace }}/target/release/${{ matrix.binary.name }}-${{ matrix.arch.name }}
      - name: Draft Artifacts
        if: ${{ !startsWith(github.ref, 'refs/tags/') }}
        uses: softprops/action-gh-release@v1
        with:
            draft: true
            name: "latest"
            tag_name: "latest"
            files: |
              ${{ matrix.binary.workspace }}/target/release/${{ matrix.binary.name }}-${{ matrix.arch.name }}
      - name: Log in to the Container registry
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Nightly Docker Image
        run: |
          export IMAGE_TAG="ghcr.io/${{ github.repository }}-nightly:${{ matrix.arch.name }}-${{ github.sha }}"
          echo "Building image $IMAGE_TAG"
          docker buildx build \
            --push \
            --build-arg RUNTIME_IMAGE=${{ matrix.arch.runtime-image }} \
            -t $IMAGE_TAG .
  release-image:
    if: startsWith(github.ref, 'refs/tags/')
    name: release docker image
    needs: [release]
    runs-on: ubuntu-22.04
    steps:
      - name: Log in to the Container registry
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Publish Docker Image
        run: |
          docker pull ghcr.io/${{ github.repository }}-nightly:amd64-${{ github.sha }}
          docker pull ghcr.io/${{ github.repository }}-nightly:aarch64-${{ github.sha }}
          export IMAGE_TAG="ghcr.io/${{ github.repository }}:${{ github.ref_name }}"
          docker manifest create $IMAGE_TAG \
            --amend ghcr.io/${{ github.repository }}-nightly:amd64-${{ github.sha }} \
            --amend ghcr.io/${{ github.repository }}-nightly:aarch64-${{ github.sha }}
          docker manifest push --purge $IMAGE_TAG
```

## Known issues

### Toolchain version not found?

Create an issue, the workflow is currently triggered manually.

### Building with openssl?

`openssl-dev` not included in the builder; if you're trying to build with openssl, use the vendored version by adding the following dependency in your `Cargo.toml`:

```toml
openssl = { version = "0.10.45", features = ["vendored"] }
```
