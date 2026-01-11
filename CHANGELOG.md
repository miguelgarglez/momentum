# Changelog

## [1.6.0](https://github.com/miguelgarglez/momentum/compare/v1.5.0...v1.6.0) (2026-01-11)


### Features

* **projects:** improve domain entry ([a810653](https://github.com/miguelgarglez/momentum/commit/a81065388a3f09fce0a974ef5a7ca57b827eaa36))

## [1.5.0](https://github.com/miguelgarglez/momentum/compare/v1.4.2...v1.5.0) (2026-01-11)


### Features

* add settings section header ([7b8f594](https://github.com/miguelgarglez/momentum/commit/7b8f594573bc2d532fcfc3db760d14d5d6835c86))
* add settings section intro copy ([fbc8881](https://github.com/miguelgarglez/momentum/commit/fbc8881c268e0fcb804cc97d6d25c2758f117604))
* add settings section model ([fc85d2c](https://github.com/miguelgarglez/momentum/commit/fc85d2c67fa749fe5fa75c89bcf26b5bf0398d9f))
* add settings shell view ([3262981](https://github.com/miguelgarglez/momentum/commit/32629812bebb85bee528a95950f9edfa9c5ec55d))
* add settings sidebar view ([25ac0b8](https://github.com/miguelgarglez/momentum/commit/25ac0b8cb7cbb5585d3bc272be65c009d20df2eb))
* add sidebar previews for empty sections ([d4ded67](https://github.com/miguelgarglez/momentum/commit/d4ded67f38b7226b4005d047ce1d72800ab48382))
* centralize settings shell layout ([32c84f5](https://github.com/miguelgarglez/momentum/commit/32c84f58083c0281b35fb29106dd7ba0d097d365))
* extract appearance settings section ([71b2ca5](https://github.com/miguelgarglez/momentum/commit/71b2ca5b7ae6acdc2bccfd4ffd757b52c89af846))
* extract assignment rules settings section ([c2f8d61](https://github.com/miguelgarglez/momentum/commit/c2f8d61b4bf9bee9c363971339d07d6d15feaebd))
* extract exclusions settings section ([a45e854](https://github.com/miguelgarglez/momentum/commit/a45e85404fd2564f5b949d6475259576899021d4))
* extract idle settings section ([48e45f2](https://github.com/miguelgarglez/momentum/commit/48e45f21994e932b9005b429525c5584c824dfb6))
* extract privacy settings section ([84afd3e](https://github.com/miguelgarglez/momentum/commit/84afd3e658919d17bb713b2f8950a5bdf061ec17))
* extract settings tracking section view ([32f9717](https://github.com/miguelgarglez/momentum/commit/32f97170f2e2c1ec13bc5f908c9ac21cebefc5d0))
* reorder settings sidebar sections ([ec6cbb7](https://github.com/miguelgarglez/momentum/commit/ec6cbb78e27a8ff11b478436b4367b0674a01c59))
* resize settings window for split view ([1874663](https://github.com/miguelgarglez/momentum/commit/1874663b3bfda3cb497bf7f2f573c7a43e971ce7))
* route settings sections in detail view ([0198d23](https://github.com/miguelgarglez/momentum/commit/0198d23c24b4d26924e115dcf03fc6590201d53c))
* **settings:** refresh settings shell layout ([2ac53be](https://github.com/miguelgarglez/momentum/commit/2ac53be9f5dcbc2dc5f5ece12d624c5b9a8cd5cf))


### Bug Fixes

* add accessibility to settings sidebar ([3b0dbaf](https://github.com/miguelgarglez/momentum/commit/3b0dbaf6c55bfa3699e795abeae57e1ffe7d4c7d))
* align settings split view spacing ([f809df8](https://github.com/miguelgarglez/momentum/commit/f809df8c5d0fe53b58cc48e10194cd21e0118e4f))
* default settings section selection ([abfebce](https://github.com/miguelgarglez/momentum/commit/abfebcebec842638ab1880fa11ebfad1ab08ec06))
* reset settings draft on close ([5d18e2b](https://github.com/miguelgarglez/momentum/commit/5d18e2b6de0edebea7139dd7a1791d4408e5bf10))
* scope settings navigation stack ([533e16b](https://github.com/miguelgarglez/momentum/commit/533e16baf5e81290a54645e16a58f0763479781d))
* widen settings window minimum size ([8d54791](https://github.com/miguelgarglez/momentum/commit/8d547919d0b6b6f4e5dd64dabdcefd23539dc06f))


### Refactors

* split settings sections ([beb64c6](https://github.com/miguelgarglez/momentum/commit/beb64c60e8b18e74c883d5b21445993338172a66))


### Documentation

* document settings split layout ([2964853](https://github.com/miguelgarglez/momentum/commit/29648531903cc06512d5ebb11e13209bfa42f06a))


### Chores

* add settings layout UX note ([980c291](https://github.com/miguelgarglez/momentum/commit/980c29124eb918f6b319637ffbfcd601f08a1a0f))
* complete SET-026 dependency check ([9b7c0b9](https://github.com/miguelgarglez/momentum/commit/9b7c0b91a7f6826055b9ab77c56f5631f71c75bd))
* mark settings sidebar icons complete ([6f7da5e](https://github.com/miguelgarglez/momentum/commit/6f7da5ed080585902c13e1268c33e044098168ed))


### Style

* **settings:** drop MainActor annotation ([91fa368](https://github.com/miguelgarglez/momentum/commit/91fa36885688e1b3493251a09e540431b67ced38))

## [1.4.2](https://github.com/miguelgarglez/momentum/compare/v1.4.1...v1.4.2) (2026-01-10)


### Bug Fixes

* isolate status item controller to main actor ([bab1ef1](https://github.com/miguelgarglez/momentum/commit/bab1ef1db7b1feee1888e5267052a6ad77bf6e67))
* resolve swift 6 concurrency errors ([a9f3d89](https://github.com/miguelgarglez/momentum/commit/a9f3d89e5b949cc09d001dfd707256b083281b3e))


### Refactors

* **services:** centralize AppleScript runner ([363100a](https://github.com/miguelgarglez/momentum/commit/363100ac7174de42ade78cee42ceb2652150c9c5))
* **tracking:** simplify perf budget wiring ([001e35e](https://github.com/miguelgarglez/momentum/commit/001e35e5bfcfd77de291661de69ea99d3e0ded55))


### Tests

* disable idle monitoring in tracker scenarios ([969bf9e](https://github.com/miguelgarglez/momentum/commit/969bf9e8cfb9ffd51409f290ab433f2945a13290))
* stabilize tracker idle behavior in tests ([587ff43](https://github.com/miguelgarglez/momentum/commit/587ff437d5f29174e9ce547ce9cb205bc8fab3b9))


### Chores

* **build:** update Xcode project file ([707b30d](https://github.com/miguelgarglez/momentum/commit/707b30d2505e4bb3885e0e5327dab53e042b6f36))

## [1.4.1](https://github.com/miguelgarglez/momentum/compare/v1.4.0...v1.4.1) (2026-01-10)


### Style

* **ui:** normalize formatting updates ([01ef559](https://github.com/miguelgarglez/momentum/commit/01ef55904a7cb3b40055a19fa9d0b449a8f3b1a9))

## [1.4.0](https://github.com/miguelgarglez/momentum/compare/v1.3.0...v1.4.0) (2026-01-10)


### Features

* add color picker for project color ([073bb56](https://github.com/miguelgarglez/momentum/commit/073bb5667cf97671f459710e5f4b558a64e95ef2))
* **projects:** add usage summary support ([c5466b3](https://github.com/miguelgarglez/momentum/commit/c5466b3e3ea4245988dd1b72b31cdac1bf5818aa))
* **ui:** add navigation to project details ([a49549f](https://github.com/miguelgarglez/momentum/commit/a49549f4119392a53fcf6e7df6e8930a36decfc8))


### Bug Fixes

* close color panel after selection ([dc7a9d3](https://github.com/miguelgarglez/momentum/commit/dc7a9d3c8883351d4fae3575c4a7a5f196535cf3))
* close color panel on cancel ([443af15](https://github.com/miguelgarglez/momentum/commit/443af15cb2f32ae2021fe2cfb4b81e9e4ffda1e2))
* close color panel on save ([f2a7ca3](https://github.com/miguelgarglez/momentum/commit/f2a7ca32e5f41526fa68b8790e82785561d6a169))
* match file chip delete style ([b9fd585](https://github.com/miguelgarglez/momentum/commit/b9fd58512624f1352e47b7e1b8879ef88fd93859))
* remove leftover recents hook ([826dcea](https://github.com/miguelgarglez/momentum/commit/826dcea6d569c9f3c3800d6fea43e5e74e085162))


### Refactors

* **app:** swift 6.2 and tighten tracking and UI code ([b2aaa2e](https://github.com/miguelgarglez/momentum/commit/b2aaa2ea7ed83c852f963a7e3104eab67555e388))
* extract removable chip component ([d778cfb](https://github.com/miguelgarglez/momentum/commit/d778cfbb73172c79c98a50293e2e2cf456617fd7))
* reuse chip styling in detail view ([6fddc58](https://github.com/miguelgarglez/momentum/commit/6fddc58e00e0ff217d4e6ed195080ea2b3e21d96))
* reuse removable chip in settings ([5e2bf7c](https://github.com/miguelgarglez/momentum/commit/5e2bf7cc499fde35977f0566be6505b3ae1eefa4))
* **ui:** split project detail views ([af5daeb](https://github.com/miguelgarglez/momentum/commit/af5daeb5766fa3dff0ba8d0665719d2245128aca))
* unify removable chip styling ([77effcf](https://github.com/miguelgarglez/momentum/commit/77effcf446be0494fc88ce8d3abd298ffbfcde2c))

## [1.3.0](https://github.com/miguelgarglez/momentum/compare/v1.2.1...v1.3.0) (2026-01-10)


### Features

* **tracking:** add file tracking support ([88ec98d](https://github.com/miguelgarglez/momentum/commit/88ec98d6935a0d9821544b20aa6aa989343b0f84))


### CI

* **release:** verify version marker in pbxproj ([6a506bc](https://github.com/miguelgarglez/momentum/commit/6a506bcd735a87bb76d9a78d567db5cc4dcefa51))
* **workflows:** add SwiftLint cache ([0b41058](https://github.com/miguelgarglez/momentum/commit/0b41058ad88c252ee077ea9958e2476fe9d87907))


### Chores

* **tooling:** add SwiftLint/SwiftFormat setup ([24b3da5](https://github.com/miguelgarglez/momentum/commit/24b3da5f10fb168a404dd9ef6513683c9473999f))


### Style

* **ui:** apply swiftformat tweaks ([38647d9](https://github.com/miguelgarglez/momentum/commit/38647d96874e7397e56bf1ae8f8b039573dd0c83))

## [1.2.1](https://github.com/miguelgarglez/momentum/compare/v1.2.0...v1.2.1) (2026-01-08)


### Tests

* **ui:** document and tune ui tests ([bf5d3f8](https://github.com/miguelgarglez/momentum/commit/bf5d3f8a9e22fbe3d8e45c9142089470e66f3e87))

## [1.2.0](https://github.com/miguelgarglez/momentum/compare/v1.1.0...v1.2.0) (2026-01-08)


### Features

* **onboarding:** add welcome flow and permissions ([e65f73f](https://github.com/miguelgarglez/momentum/commit/e65f73fd77bd050741d7a8ebd0970e3f0ceeac3f))

## [1.1.0](https://github.com/miguelgarglez/momentum/compare/v1.0.2...v1.1.0) (2026-01-08)


### Features

* **models:** add longest streak tracking ([910f2b5](https://github.com/miguelgarglez/momentum/commit/910f2b547a667800f709c2cef4b11e2046472e05))
* **tracking:** add manual tracking support ([a51db66](https://github.com/miguelgarglez/momentum/commit/a51db665a45e39dfc446f1ee7818ca9894a7b31e))

## [1.0.2](https://github.com/miguelgarglez/momentum/compare/v1.0.1...v1.0.2) (2026-01-08)


### Refactors

* **ui:** split views into modules ([d3bb32e](https://github.com/miguelgarglez/momentum/commit/d3bb32ed14c2a12824658270e6fbbb8757a3450f))


### Tests

* **ui:** stabilize dashboard assertions ([40573f1](https://github.com/miguelgarglez/momentum/commit/40573f18a9ec6bc33fc26c1390f1664d1e2f9dbe))

## [1.0.1](https://github.com/miguelgarglez/momentum/compare/v1.0.0...v1.0.1) (2026-01-06)


### Refactors

* **ui:** align project metrics layout ([2ceda97](https://github.com/miguelgarglez/momentum/commit/2ceda97ab1985909754222b6ee840d8c1d43fd89))

## 1.0.0 (2026-01-05)


### Features

* Add comprehensive documentation for architecture, diagnostics, testing, and project requirements ([876eae8](https://github.com/miguelgarglez/momentum/commit/876eae87f3b29ec2dd18ddbcdc3a438acaf09a72))
* Add context usage tracking and improve session management ([a3c7846](https://github.com/miguelgarglez/momentum/commit/a3c7846e7404c7263556006081bcd39807fc32cb))
* Add project priority, tracker settings, and status item controller ([e2b55e7](https://github.com/miguelgarglez/momentum/commit/e2b55e79ca0148ad4a9a0d2836457408f19ac06a))
* Enhance project assignment resolver to prioritize domain matching and add related tests ([77cb7bd](https://github.com/miguelgarglez/momentum/commit/77cb7bdf0760db50fac86ceb0834111db003604d))
* Enhance project management with toast notifications and project edition ([b85af02](https://github.com/miguelgarglez/momentum/commit/b85af028d47772bbd85084d3947631d5347cb836))
* implement conflict management MVP ([27d7dc5](https://github.com/miguelgarglez/momentum/commit/27d7dc53b53b4892736a650045c0f2b971bdd014))
* Implement project assignment and session overlap resolution ([a0e72eb](https://github.com/miguelgarglez/momentum/commit/a0e72eb72f94b956acb83c816df5172cf453316a))
* **prd:** Refactor Momentum app structure and introduce new models ([62daa4c](https://github.com/miguelgarglez/momentum/commit/62daa4cff6664460f725550a7750e6036754c936))
* **rules:** add assignment rule management ([c26e6d5](https://github.com/miguelgarglez/momentum/commit/c26e6d5257a35b771ba72aee25c96c128d14f82c))
* **ui:** add activity history insights ([b1cc26b](https://github.com/miguelgarglez/momentum/commit/b1cc26b7eac5a682d59dcbc5cff3f5780b453534))
* **ui:** add theme preference preview ([027c119](https://github.com/miguelgarglez/momentum/commit/027c119b1ed784dd66e3a505899c9fc9e2c74b4a))
* **ui:** refine project detail layout ([adee653](https://github.com/miguelgarglez/momentum/commit/adee653776ffc15ae5bf7abb8cd6dadb3ba3f0b7))


### Bug Fixes

* **app:** init status item after launch ([8145e86](https://github.com/miguelgarglez/momentum/commit/8145e861258958a74f83316ff685c3ca90ef31e6))


### Refactors

* **app:** move status item lifecycle ([e49edb9](https://github.com/miguelgarglez/momentum/commit/e49edb9f492f4066681e97145faf63d36e293072))
* **ui:** extract heatmap intensity logic ([e5b7484](https://github.com/miguelgarglez/momentum/commit/e5b7484dd95b72650a2fd223b641810ac25e79cb))
* **ui:** improve split view layout ([7d85761](https://github.com/miguelgarglez/momentum/commit/7d8576181e0f31c84859b193ff9cc97b7b52483b))
* **ui:** polish assignment rules view ([0e80c2d](https://github.com/miguelgarglez/momentum/commit/0e80c2d410c0da37ce0b3ebbfcb3530277b62d48))
* **ui:** refine sidebar layout ([cd2435b](https://github.com/miguelgarglez/momentum/commit/cd2435b690409de2e5ec7ce1581f67508309d021))


### Documentation

* **ci:** document CI workflows ([3798d71](https://github.com/miguelgarglez/momentum/commit/3798d713606ef2c4549cdbb43054bffd9a73277e))


### Tests

* **ui:** add conflict resolution coverage ([8179aaf](https://github.com/miguelgarglez/momentum/commit/8179aafe81f96bf8e4e409fcd1fdfb5a50c03e39))


### CI

* harden xcodebuild workflows ([ad42386](https://github.com/miguelgarglez/momentum/commit/ad4238672cd5b41055d7f5f3b0da8e2f77303866))
* **release:** add release-please pipeline ([858b8dd](https://github.com/miguelgarglez/momentum/commit/858b8dd0c7da16e70131d53058e53f6af04a9486))


### Chores

* **assets:** add app icon set and scheme ([aaebdb7](https://github.com/miguelgarglez/momentum/commit/aaebdb79c04b9de0b02eb6128b1348487a449166))
* **dev:** add local dev tooling ([4eba824](https://github.com/miguelgarglez/momentum/commit/4eba824636f95210d771a7c80875000b3f9f12c4))
* **release:** add DMG packaging docs ([0c19143](https://github.com/miguelgarglez/momentum/commit/0c1914389f64fa10547ad6461554535820e31f32))
* **release:** reset version to 0.0.0 ([799f0e4](https://github.com/miguelgarglez/momentum/commit/799f0e497f2059654e088c0bf332561222815776))
* use Icon Composer app icon format ([b3ff847](https://github.com/miguelgarglez/momentum/commit/b3ff847e0b97fe34c6b9eeb76d5bde1e7492443c))

## 0.0.0
- Bootstrap release.
