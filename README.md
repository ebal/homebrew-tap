# ebal/homebrew-tap

[Homebrew](https://brew.sh) formulae by Evaggelos Balaskas.

| Formula    | Description                                                                          |
|------------|--------------------------------------------------------------------------------------|
| `lilyterm` | [LilyTerm](https://github.com/ebal/LilyTerm), a light and easy to use VTE based terminal emulator |

## Installation

```bash
brew install ebal/tap/lilyterm
```

That is the same as:

```bash
brew tap ebal/tap
brew install lilyterm
```

LilyTerm is also released as a ready-made app for Apple Silicon:
`LilyTerm-VERSION-macos-arm64.dmg` on the
[releases page](https://github.com/ebal/LilyTerm/releases), with GTK+ 3
and VTE inside, no Homebrew needed. This formula is the other way: it
installs the `lilyterm` command, built from source.

This tap has no bottles (prebuilt packages), so Homebrew builds LilyTerm
from source. Its dependencies (`gtk+3`, `vte3`, `glib`, `gettext`) come as
bottles from Homebrew itself on macOS with Apple Silicon and on Linux. On an
Intel Mac, `vte3` has no bottle and is built from source as well, which
takes a while.

To build the latest commit of the `main` branch instead of the release:

```bash
brew install --HEAD ebal/tap/lilyterm
```

## Usage

```bash
lilyterm
lilyterm --help
man lilyterm
```

The settings of every user are in `~/.config/lilyterm/default.conf`
(create it with [Save settings] in the right click menu). The system wide
settings are in `$(brew --prefix)/etc/xdg/lilyterm.conf`.

## LilyTerm on macOS

LilyTerm runs with the native macOS (Quartz) backend of GTK+ 3, without X11
or XQuartz. Some things work differently than on Linux:

- Start it from a terminal: Homebrew installs a command, not an app in
  `/Applications`, so it is not in Launchpad or the Dock until it runs.
- macOS has no `/proc`. Tab names do not follow the running command or
  the current directory, a new tab opens in the start directory, and
  there is no warning about running programs when a tab is closed.
- Window transparency is off: GTK+ 3 on macOS would draw the title bar
  clear as well, so the window could not be moved. Set `use_rgba = 1` in
  `~/.config/lilyterm/default.conf` to turn it on anyway.
- Key bindings use Ctrl, not Cmd. Change them with [Set key binding] in
  the right click menu.

LilyTerm 0.10.0 and later build on macOS as they are: the formula has no
patches.

## Testing the formula

```bash
brew install --build-from-source --verbose ebal/tap/lilyterm
brew test ebal/tap/lilyterm
brew audit --strict --online ebal/tap/lilyterm
brew style ebal/tap/lilyterm
lilyterm
```

To test changes to a local clone of this tap:

```bash
brew tap ebal/tap
cd "$(brew --repository ebal/tap)"
# edit Formula/lilyterm.rb, then
brew reinstall --build-from-source --verbose ebal/tap/lilyterm
```

## Update and uninstall

```bash
brew update && brew upgrade lilyterm
brew uninstall lilyterm
brew untap ebal/tap
```

## Support

Report problems with the formula in the
[issues of this tap](https://github.com/ebal/homebrew-tap/issues), and
problems with LilyTerm itself in the
[issues of LilyTerm](https://github.com/ebal/LilyTerm/issues).

## License

The formulae are under the
[BSD 2-Clause License](https://opensource.org/license/bsd-2-clause), like
Homebrew itself. LilyTerm is under the GPL 3.0 or later.
