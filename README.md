# Cadence

Native macOS menu bar app for your agenda and tasks. Open the **Calendário** tab
to browse the month. Select **Hoje** to return to the current date.

## Install on macOS

Download the **.pkg** for Apple Silicon from [the latest release](https://github.com/LucasMazei/cadence/releases/latest).
On macOS 14 or later, double-click the package and follow the prompts in Installer.
Cadence starts in the menu bar and launches again at login. Open the gear and
choose **Contas** → **Conectar** to link your Google account.

The installer includes uv. On first sync it uses the internet to download Python
and the locked Google API dependencies. Updates preserve your accounts and OAuth
tokens. Each release also includes a ZIP with **Install.command** and SHA-256
files for both downloads.

The app has an ad-hoc signature. The installer is unsigned and the release has
no Apple notarization. Gatekeeper or managed Mac policies may block installation.

## Google backend

Cadence vendors the Google Calendar and Google Tasks backend previously used by
the Waylandar Quickshell plugin. It fetches the upcoming 31 days of Calendar
events, lists tasks from every Google Tasks list, and supports toggling task
completion.

The backend writes `events.json` and `tasks.json` atomically to the configured
cache directory. The app only reads those files, so its UI never directly uses
macOS Calendar.

## Configuration

Cadence reads `~/.config/cadence/config.json` by default. Set
`CADENCE_CONFIG_PATH` before launching it to use a different file. The installer
copies [`Resources/config.example.json`](Resources/config.example.json) when no
configuration exists.

The configurable paths are:

- `cacheDirectory`: JSON cache for events, tasks, and the OAuth token.
- `syncScript`: command the refresh button uses.
- `backendCommand`: command used when changing a task's status.
- `syncIntervalMinutes`: background Google sync interval (default 30, minimum 1).
- `completedTaskDays`: completed-task history retained in the UI.
- `accounts`: Google profiles to synchronize.

Each account has an `id`, optional `label`, `credentialsPath`, independent
`tokenPath`, and boolean `calendar` and `tasks` flags. Events from every account
with `calendar: true` are aggregated in Agenda. Tasks are loaded only from
accounts with `tasks: true`, and task updates return through that same account.

The default configuration enables Calendar and Tasks for `personal`, and only
Calendar for `work`.

## Sync strategy

The app syncs with Google on launch, every `syncIntervalMinutes`, and after the
Mac wakes from sleep. Opening the popover syncs only if the last sync is older
than 60 seconds; the refresh button always syncs. A separate 60-second local
tick re-reads the cache to keep the menu bar title current and auto-open
accepted meetings. The footer shows the time of the last successful sync.

## Keyboard shortcut

With Cadence running, open the gear, select **Atalho**, and click **Gravar
atalho**. Press a combination such as ⌃⌥C to open the panel from any app.
Cadence remembers the shortcut on this Mac. Click the combination to change it
or **Remover** to disable it.

## Managing accounts

Open the gear menu in Cadence to add, edit, connect, or remove accounts. The
account screen lets you select an OAuth credentials JSON, choose Calendar and
Tasks independently, and starts OAuth only after clicking Connect. Removing an
account removes its token from this Mac but retains shared OAuth credentials.

## Contributing

Every change to `main`, including documentation, goes through a pull request.
If you have write access, work on a branch in this repository. Otherwise, fork
the repository and clone your fork.

1. Create a branch from the latest upstream `main`. From your clone, run:

   ```sh
   git fetch https://github.com/LucasMazei/cadence.git main
   git switch -c my-change FETCH_HEAD
   ```

2. Make your change. For changes to the app or backend, run `./scripts/quality.sh`
   from a graphical session on a Mac with Swift 6.1+, the macOS SDK, and `uv`.
   Use synthetic data for tests and examples. Keep local OAuth credentials,
   tokens, and calendar data out of commits and screenshots.

3. Commit your changes and push the branch with `git push -u origin my-change`.
   Open a pull request against `LucasMazei/cadence:main`. Describe what changed,
   why, and how you verified it.

4. Keep the branch up to date with `main`. Once the required `Quality` check
   passes, a maintainer can merge the PR.

## Development and release

Use a Mac with Swift 6.1+ and the macOS SDK. From the checkout run:

```sh
./scripts/quality.sh           # formatter, Swift/Python tests, release build, signature and panel checks
./scripts/install.sh           # build and install for the signed-in user
./scripts/package-release.sh   # PKG, ZIP and SHA-256 files in dist/
```

The UI check opens a temporary panel in the current graphical session. It uses
an empty cache and isolated configuration. The build selects the active macOS
SDK, with a compatibility fallback for Command Line Tools 27 when SDK 26.5 is
available. CI audits the locked Python dependencies and tests a fresh package
install and upgrade. Pushing a version tag matching the app version (for example
`v0.1.1`) publishes the tested PKG, ZIP and their checksums to Releases.

## Google OAuth setup

1. In Google Cloud Console, enable the Google Calendar API and Google Tasks API.
2. Create an OAuth 2.0 Desktop Client and download its JSON credentials.
3. Save it at the configured `credentialsPath` (the default profiles share
   `~/.config/cadence/credentials.json`).
4. In **Contas**, click **Conectar** for each enabled account and complete the
   browser flow. Each token is saved with owner-only access.
