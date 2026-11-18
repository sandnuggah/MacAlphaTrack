# Releasing MacAlphaTrack

MacAlphaTrack is distributed through Homebrew as a formula that builds from source. The
formula lives in its own tap repository, `homebrew-MacAlphaTrack`
(`Formula/macalphatrack.rb`), kept next to this one. A source build is not quarantined, so it needs no Developer ID
signature or notarization.

## Cutting a release

1. Make sure `swift test --build-system native` and
   `python3 -m unittest discover -s LiveRemoteScript/tests` pass.
2. Tag and push:

   ```sh
   git tag v0.1.0
   git push origin main v0.1.0
   ```

3. Get the checksum of the tag tarball:

   ```sh
   curl -sL https://github.com/OWNER/MacAlphaTrack/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
   ```

4. Put the new `url` and `sha256` into `Formula/macalphatrack.rb` in the tap repository,
   commit and push it. Users then get the release with `brew upgrade`.

## Testing the formula before publishing

The formula can be built in Homebrew's sandbox from a local tarball, without any remote:

```sh
git archive --format=tar.gz --prefix=MacAlphaTrack-0.1.0/ -o /tmp/v0.1.0.tar.gz HEAD
brew tap-new --no-git local/macalphatrack-test
# copy the tap's Formula/macalphatrack.rb into the test tap's Formula folder, with
#   url "file:///tmp/v0.1.0.tar.gz" and the tarball's sha256
brew install --build-from-source local/macalphatrack-test/macalphatrack
brew test local/macalphatrack-test/macalphatrack
brew audit --strict --formula local/macalphatrack-test/macalphatrack
brew uninstall macalphatrack && brew untap local/macalphatrack-test
```

Verified this way on 2026-11-18 (Homebrew 7.0.14, Xcode 27.2): build, test, audit and style
all pass; the installed app is validly ad-hoc signed and carries no quarantine attribute.

## What the formula does

- Builds the `macalphatrack` command-line tool and, through `Scripts/make-app.sh`,
  `MacAlphaTrack.app`. The version comes from `MACALPHATRACK_VERSION`, since a tarball has
  no git metadata; `SWIFT_BUILD_FLAGS=--disable-sandbox` lets SwiftPM run inside
  Homebrew's own sandbox.
- Installs the app into the formula prefix (`$(brew --prefix)/opt/macalphatrack/`), the Live
  script next to it, and a `brew services` definition that runs the headless driver.
- Requires Xcode 26 or later to build, because the app icon is an Icon Composer package.

## Known limits

- "Launch at login" registers the app at its Cellar path, which changes with every
  version. The caveats suggest copying the app to /Applications.
- The app and the `brew services` driver must not run together: only one process can hold
  the unit.
