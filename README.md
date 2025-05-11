Create GitHub Pages Documentation using DocC
============================================

<p>
  <a href="https://github.com/features/actions">
    <img src="https://img.shields.io/badge/GitHub-Action-blue?logo=github" alt="GitHub Action" />
  </a>
  <a href="https://help.github.com/en/actions/automating-your-workflow-with-github-actions/virtual-environments-for-github-hosted-runners#supported-runners-and-hardware-resources">
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-darkgreen" alt="Supports macOS and Linux" />
  </a>
  <a href="https://swift.org">
    <img src="https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white" alt="Swift 5.10" />
  </a>
  <a href="https://github.com/mipalgu/swiftpm-generate-documentation/releases/latest">
    <img src="https://img.shields.io/github/v/release/mipalgu/swiftpm-generate-documentation?sort=semver" alt="Latest release" />
  </a>
</p>

*A [GitHub Action](https://github.com/features/actions) for generating DocC documentation and deploying to GitHub Pages*

## Usage

To run the action to generate documentation with the latest Xcode or Swift version available
and deploy to GitHub pages, add the action as a step in your workflow:

```yaml
- uses: mipalgu/swiftpm-generate-documentation@main
```

A specific Xcode or Swift version can be set using the `swift-version` input:

```yaml
- uses: mipalgu/swiftpm-generate-documentation@main
  with:
    swift-version: "5.10"
```

The following section shows the input parameter variables that can be configured.

## Configuration

Here are the input parameters (and their default values) that can be set up in the YAML configuration:

```yaml
inputs:
  output-path:
    description: The path containing the generated docs.
    required: false
    default: "./docs"
  working-directory:
    description: The directory containing the swift package.
    required: false
    default: ""
  hosting-base-path:
    description: The the website will be hosted.
    required: false
    default: ${{ github.event.repository.name }}
  minimum-access-level:
    description: The minimum access level that must be included in the docs.
    default: "public"
  swift-version:
    description: The version of Xcode/Swift used to execute the docC package plugin.
    default: latest
```

## Note about versions

This project uses [swift-actions/setup-swift@v1](https://github.com/swift-actions/setup-swift)
to set up Swift on Linux and
[maxim-lobanov/setup-xcode@v1](https://github.com/maxim-lobanov/setup-xcode)
to set up Xcode on macOS.
See the corresponding actions for details on their versioning system, but it is important to note
that they use strict semantic versioning to determine what version of Swift to configure.
In particular, for [setup-swift](https://github.com/swift-actions/setup-swift)
this differs from the official convention used by Swift, in that if a patch version
is omitted, the lates patch version is used.

For example, there is a Swift version `5.9` but using this as value for `swift-version`
will be interpreted as a version _range_ of `5.9.x` where `x` will match the latest patch version
available for that major and minor version.

In other words specifying...
- `"5.9.0"` will resolve to version `5.9`
- `"5.9"` will resolve to latest patch version (e.g. `5.9.2`)
- `"5"` will resolve to latest minor and patch version (e.g. `5.10.x`)

### Caveats

Quote your inputs as YAML interprets eg. `5.0` as a float, causing GitHub actions to then interpret that as `5`,
which will result in eg. Swift 5.9.2 being resolved. Thus:

```
- uses: mipalgu/swiftpm-generate-documentation@main
  with:
    swift-version: '5.0'
```

Not:

```
- uses: mipalgu/swiftpm-generate-documentation@main
  with:
    swift-version: 5.0
```

## Keeping the action up-to-date

You have two options for keeping this action up-to-date: either you use the main branch (i.e. `@main`)
or you define a specific version (such as `@v1.2.3`) or use the major version tag (as in `@v1`).

### Dependabot

We recommend using a specific version tag together with
[Dependabot](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/about-dependabot-version-updates) to keep the action up-to-date. This way, you will automatically get notified when the action updates
and you can read the ChangeLog directly in the PR opened by dependabot.

### Main Version Tag

If you don't plan on keeping tabs on updates or don't want to use Dependabot but still would like to always use the latest version, you can use the `@main` version tag.

## Legal
See [LICENSE.txt](https://raw.githubusercontent.com/rhx/swiftpm-generate-documentation/main/LICENSE.txt) for details. 
The Swift logo is a trademark of Apple Inc.

