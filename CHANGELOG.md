# Changelog

## [build-52] - 2026-11-23

## Verified changes since build-50

- Only start paired bridge Govee monitoring after Equinox login ([`0ea75056`](https://github.com/soum91/ColdFront/commit/0ea750567fc15a3aa6d1c15decb3fedfa6fe0670); `ColdFront/App/ColdFrontApp.swift`)
- Learn pinned Govee identity from Keystone even while the bridge reading is stale ([`777de906`](https://github.com/soum91/ColdFront/commit/777de906dd9efa5a58b8a8600a6a5ec3bb82065b); `ColdFront/App/HomeBridge.swift`)

[Inspect exact code changes](https://github.com/soum91/ColdFront/compare/build-50...build-52)

## [build-50] - 2026-11-23

## Verified changes since build-49

- Allow Equinox to forward Keystone's exact pinned Govee without a local BLE UUID link ([`45326250`](https://github.com/soum91/ColdFront/commit/45326250c765f47bb3f5a92ca397e2ce1464cf7d); `ColdFront/Model/Govee.swift`)

[Inspect exact code changes](https://github.com/soum91/ColdFront/compare/build-49...build-50)

## [build-49] - 2026-11-23

## Verified changes since build-48

- Start Equinox Govee scanner when Keystone is paired even without local sensor link ([`67a029ba`](https://github.com/soum91/ColdFront/commit/67a029ba73326a6248a6afc53a2c0afb3a693c1a); `ColdFront/App/ColdFrontApp.swift`)

[Inspect exact code changes](https://github.com/soum91/ColdFront/compare/build-48...build-49)

## [build-48] - 2026-11-23

## Verified changes since build-47

- Use explicit byte checks for Govee advertised name in Equinox feed ([`fe917d1a`](https://github.com/soum91/ColdFront/commit/fe917d1a14e6abf9a391565578444127c6bef1ff); `ColdFront/Model/Govee.swift`)

[Inspect exact code changes](https://github.com/soum91/ColdFront/compare/build-47...build-48)

## [build-47] - 2026-11-23

## Verified changes since build-45

- Document Equinox-to-Keystone primary Govee feed ([`5002ed2e`](https://github.com/soum91/ColdFront/commit/5002ed2e611c2bcc308b30544fcff37fabf3ef7e); `README.md`)
- Feed selected Equinox Govee BLE readings to Keystone over local Wi-Fi ([`e8e2ab13`](https://github.com/soum91/ColdFront/commit/e8e2ab13230b81e3c1c48b4c962e0e015dad0835); `ColdFront/Model/Govee.swift`)

[Inspect exact code changes](https://github.com/soum91/ColdFront/compare/build-45...build-47)

## [build-44] - 2026-11-07

## Verified changes since build-43

- Turbo auto-off: manual Turbo stops within 3°C of the set temperature ([`e7e7c3ee`](https://github.com/soum91/ColdFront/commit/e7e7c3ee971ffce2339b5ad7e223a46c62bf4a76); `ColdFront/Model/Store.swift`, `ColdFront/Model/TurboGuard.swift`, `ColdFront/Views/ControlView.swift`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/ColdFront/compare/build-43...build-44)

This log records verified, release-specific changes. The [Factual release changelog](.github/workflows/release-changelog.yml) GitHub Action adds entries based on the actual commits between published releases. Entries are not fabricated for older versions that have not been audited.

