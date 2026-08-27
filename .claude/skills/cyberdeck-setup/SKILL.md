---
name: cyberdeck-setup
description: Sets up a matrix-green / cyber-purple "Cyberdeck" developer environment on Linux — Starship prompt, a correctly-metriced Nerd Font, a matching 16-color terminal palette, a Claude Code status line, modern CLI tools (eza, bat, fzf, zoxide), git delta, zellij, btop, and bash aliases with a `dh` help command. Use when the user asks to set up, theme, or customize their terminal/shell/dev environment on Linux, or wants a "cyberdeck" or similarly-themed dev machine.
---

# Cyberdeck Setup

Builds a cohesive, matrix-green/cyber-purple terminal environment across every tool a
Linux developer touches daily — one shared palette, not eleven mismatched ones.

This skill was reverse-engineered from a real end-to-end session, including the bugs
hit along the way. Follow it as a runbook, not a suggestion list — several steps exist
specifically because the naive approach silently breaks (see **Known gotchas** below).

## Ground rules

- **Linux + bash only.** If `uname -s` isn't `Linux`, or the user's shell isn't bash
  (check `$SHELL`), stop and tell the user this skill doesn't cover their setup yet.
- **Never run `sudo` yourself.** This environment usually has no interactive TTY for a
  password prompt, and even when it does, silently escalating is not this skill's call
  to make. Every install in this skill uses a **no-sudo, user-local** pattern
  (`~/.local/bin`, `~/.local/share/fonts`, tarball/binary downloads) specifically so
  root is never required. If a step genuinely needs `apt`/`dnf`/etc., say so and hand
  the user the exact command — don't run it for them.
- **Idempotent and non-destructive.** Before writing to a dotfile that might already
  have user content (`~/.bashrc`, `~/.bash_aliases`, `~/.gitconfig`), read it first.
  Never blind-overwrite. Append with a clear marker comment, or merge structured files
  (JSON/TOML) programmatically instead of clobbering.
- **Verify every step**, don't just assume success. Run `--version`, config-validate
  commands (`starship print-config`, `zellij setup --check`, `bash -n file`), and where
  possible a live smoke test with sample input. A step isn't done until you've checked.
- **Ask before you build**, per Step 1 below — don't install things nobody asked for.

## Step 0 — Detect the environment

Gather this before doing anything else:

```bash
uname -s                      # must be Linux
uname -m                      # x86_64 / aarch64 / etc. — determines which release asset to fetch
echo "$SHELL"                 # must be bash (or /bin/bash)
sudo -n true 2>&1             # passwordless sudo available? (informational only — never rely on it)
command -v starship eza bat fzf zoxide delta zellij btop code 2>&1  # what's already installed
```

**Terminal emulator detection** (determines whether the palette/font steps in Step 2
can be automated or need manual instructions):

```bash
# Walk up the process tree looking for a known terminal emulator name
ps -o comm= -p $PPID 2>/dev/null
# Common values to match on: gnome-terminal-, ptyxis, konsole, xfce4-terminal,
# alacritty, kitty, wezterm, xterm, tilix
```

Also check for terminal-specific config surfaces:
```bash
which ptyxis 2>/dev/null && gsettings list-schemas 2>/dev/null | grep -q "^org.gnome.Ptyxis$" && echo "ptyxis: gsettings-controllable"
which gnome-terminal 2>/dev/null && echo "gnome-terminal: dconf-controllable"
```

This skill has fully automated palette + font wiring for **Ptyxis** (GNOME's modern
VTE-based terminal). For any other terminal, still install the font and write the
palette file, but tell the user how to point their terminal at it manually (see the
per-terminal notes inside Step 2's palette section) rather than guessing at that
terminal's config format.

## Step 1 — Ask what to install

Use `AskUserQuestion` (multiSelect) with one line per component, e.g.:

- **VS Code** — installed as a portable user-local build, with a desktop launcher (no sudo/snap/apt needed)
- **Starship prompt** — matrix-green/cyber-purple two-line prompt (git, language runtimes, cmd duration)
- **Nerd Font + terminal font fix** — required for the icons Starship/btop/etc. use
- **Terminal color palette** — 16-color ANSI theme so `ls`, `man`, `less`, everything matches (Ptyxis only, automated)
- **Claude Code status line** — themed status line inside Claude Code itself
- **Modern CLI tools** — eza, bat, fzf, zoxide
- **git delta** — themed side-by-side diffs
- **zellij** — themed terminal multiplexer
- **btop** — themed system monitor
- **bash aliases + `dh` help command** — dev shortcuts (git, docker, npm, etc.) plus a colorized help listing

Don't install anything the user didn't select. Each is independent — none depend on
another except that most of them look better once the font step has run.

## Step 2 — Install each selected component

For every binary in this section: **resolve the latest release for the detected
architecture via the GitHub API**, don't hardcode a version or a single-arch URL.
Pattern:

```bash
curl -sSL "https://api.github.com/repos/<owner>/<repo>/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*<ASSET_PATTERN>"' \
  | head -1 | cut -d'"' -f4
```

Where `<ASSET_PATTERN>` matches the detected `uname -m` (e.g. `x86_64-unknown-linux-gnu`,
`aarch64-unknown-linux-musl` — check each project's actual release asset names, they
aren't consistent). Download to a scratch dir, extract, `cp` the binary into
`~/.local/bin/`, `chmod +x`. Confirm `~/.local/bin` is on `$PATH` in `~/.bashrc`
(add `export PATH="$HOME/.local/bin:$PATH"` once, guarded by a grep-check so it's
never duplicated on a re-run).

### VS Code

Install as a portable tarball — no root, no snap, no apt:

```bash
curl -sSL "https://code.visualstudio.com/sha/download?build=stable&os=linux-x64" -o /tmp/vscode.tar.gz
mkdir -p ~/.local/share/vscode
tar -xzf /tmp/vscode.tar.gz -C ~/.local/share/vscode --strip-components=1
ln -sf ~/.local/share/vscode/bin/code ~/.local/bin/code
```
(For non-x64, VS Code's download endpoint also accepts `os=linux-arm64`/`linux-armhf`.)

Add a desktop launcher so it appears in the app grid, not just the terminal:
```bash
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/code.desktop << EOF
[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editing. Redefined.
Exec=$HOME/.local/share/vscode/bin/code %F
Icon=$HOME/.local/share/vscode/resources/app/resources/linux/code.png
Type=Application
StartupNotify=true
StartupWMClass=Code
Categories=Utility;TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;application/x-code-workspace;
EOF
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

Verify: `code --version` (this works headlessly; actually launching the GUI needs a
display, so `--version` is the practical check here).

### Starship prompt

```bash
curl -sSL https://starship.rs/install.sh -o /tmp/install_starship.sh
BIN_DIR=~/.local/bin sh /tmp/install_starship.sh -y
```

Copy `assets/starship.toml` to `~/.config/starship.toml` (create `~/.config` if
missing). If a starship.toml already exists there, ask the user before overwriting —
offer to back it up to `starship.toml.bak` first.

Add to `~/.bashrc` (only if not already present — grep for `starship init` first):
```bash
eval "$(starship init bash)"
```

Validate: `starship print-config >/dev/null && echo OK`.

### Nerd Font + terminal font fix

**Use the plain `NerdFont` build, never the `NerdFontMono` build.** The "Mono" patch
forces *every* glyph — including plain ASCII — into an oversized fixed-width cell to
keep icons aligned, which produces badly-spread letter-spacing in VTE-based terminals
(GNOME Terminal, Ptyxis). This is a real, reported upstream issue
(ryanoasis/nerd-fonts#1511) affecting multiple font families, not a one-off bug in a
specific font. The plain variant keeps the base font's real metrics.

```bash
mkdir -p ~/.local/share/fonts
curl -sSL -o /tmp/JetBrainsMono.zip \
  "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
unzip -o -q /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMonoNF
mkdir -p ~/.local/share/fonts/JetBrainsMonoNerdFont
cp /tmp/JetBrainsMonoNF/JetBrainsMonoNerdFont-*.ttf ~/.local/share/fonts/JetBrainsMonoNerdFont/
fc-cache -f ~/.local/share/fonts
```

Verify it registered correctly: `fc-match "JetBrainsMono Nerd Font"` should resolve to
one of the files you just copied, and `fc-query --format='%{spacing}\n' <file>` should
print `100` (monospace).

**Wiring the terminal to actually use it:**

- **Ptyxis:**
  ```bash
  gsettings set org.gnome.Ptyxis use-system-font false
  gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 11'
  ```
- **GNOME Terminal:** set the font on the relevant profile UUID under
  `org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:<uuid>/`.
- **Other terminals (Konsole, Alacritty, kitty, xterm, etc.):** don't guess at the
  config file. Tell the user the exact font name (`JetBrainsMono Nerd Font`) and point
  them at that terminal's font preference — every terminal exposes this differently.

**Important:** font changes only apply to *new* panes/windows/tabs — GTK terminals in
particular cache the font at pane-creation time. Always tell the user to open a new
tab (not reuse the current one) to see the change, and warn that a genuinely stuck
pane may need the whole app restarted, not just a new tab.

### Terminal color palette (Ptyxis-automated; other terminals: manual)

Ptyxis ships dozens of bundled palettes as GResources and supports user palettes
dropped into a specific directory, referenced by profile:

```bash
mkdir -p ~/.local/share/org.gnome.Ptyxis/palettes
cp assets/Cyberdeck.palette ~/.local/share/org.gnome.Ptyxis/palettes/Cyberdeck.palette

UUID=$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")
gsettings set "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$UUID/" palette 'Cyberdeck'
```

(`ptyxis --import-palette FILE` also works if the file isn't already at that exact
path — but don't call it if you just wrote the file there yourself, it'll error
claiming the file already exists.)

For any other terminal, still write `assets/Cyberdeck.palette` somewhere durable
(e.g. `~/.config/cyberdeck/Cyberdeck.palette`) and tell the user it's a standard
16-color-plus-bg/fg/cursor palette they can translate into their terminal's own format
(most terminals — kitty, Alacritty, Konsole — have a "import palette"/theme mechanism,
just not a shared file format).

### Claude Code status line

Check `~/.claude/settings.json` first — read it, don't overwrite it. If a `statusLine`
key already exists, ask the user before replacing it.

```bash
cp assets/statusline.sh ~/.claude/statusline.sh
```

Merge (don't overwrite) the settings file — use a small Python/`jq` snippet that loads
the existing JSON, sets `statusLine`, and writes it back, preserving every other key:

```python
import json
path = "/home/user/.claude/settings.json"
with open(path) as f:
    data = json.load(f)
data["statusLine"] = {"type": "command", "command": 'bash "$HOME/.claude/statusline.sh"'}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
```

Verify with a mock payload before declaring success:
```bash
echo '{"model":{"display_name":"Claude Sonnet 5"},"workspace":{"current_dir":"'$HOME'"},"context_window":{"used_percentage":34}}' \
  | bash ~/.claude/statusline.sh
```
Confirm colored output actually appears, not an error or blank line.

### Modern CLI tools — eza, bat, fzf, zoxide

Resolve + install each via the GitHub-releases pattern above. Asset name fragments to
match (adjust for detected arch):
- eza: `eza-community/eza`, asset `eza_<arch>-unknown-linux-gnu.tar.gz`
- bat: `sharkdp/bat`, asset `bat-v*-<arch>-unknown-linux-gnu.tar.gz` (binary is nested
  one directory deep inside the tarball)
- fzf: `junegunn/fzf`, asset `fzf-*-linux_<goarch>.tar.gz` (`amd64`/`arm64`, not
  `x86_64`/`aarch64` — fzf uses Go arch naming)
- zoxide: `ajeetdsouza/zoxide`, asset `zoxide-*-<arch>-unknown-linux-musl.tar.gz`

Add to `~/.bashrc` (guarded against duplication):
```bash
eval "$(fzf --bash)"
eval "$(zoxide init bash)"
```

### git delta

Install `dandavison/delta`, asset `delta-*-<arch>-unknown-linux-gnu.tar.gz`.

Don't overwrite `~/.gitconfig` wholesale — the user may already have `[user]` identity
or other sections in it. Instead, apply each key with `git config --global`:
```bash
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.line-numbers true
git config --global delta.side-by-side true
git config --global delta.syntax-theme Dracula
git config --global delta.file-style '"#9d4bff" bold'
git config --global delta.file-decoration-style '"#7d5bed" ul'
git config --global delta.hunk-header-style "file line-number syntax"
git config --global delta.hunk-header-decoration-style '"#00fff9" box'
git config --global delta.line-numbers-left-color '"#5c5c6e"'
git config --global delta.line-numbers-right-color '"#5c5c6e"'
git config --global delta.line-numbers-minus-color '"#ff003c"'
git config --global delta.line-numbers-plus-color '"#39ff14"'
git config --global delta.minus-style 'syntax "#2d0a14"'
git config --global delta.minus-emph-style 'syntax "#5c1428"'
git config --global delta.plus-style 'syntax "#0d2818"'
git config --global delta.plus-emph-style 'syntax "#145c34"'
git config --global merge.conflictstyle diff3
git config --global diff.colorMoved default
```
(`assets/gitconfig-delta.txt` has the same values in raw `.gitconfig` block form, for
reference or for a user with no existing `~/.gitconfig` at all — safe to use directly
as the whole file only in that empty case.)

Verify: pipe a real diff through delta directly (piped commands bypass `core.pager`,
so testing via `git diff` alone won't actually invoke it):
```bash
git diff --color=always <file> | delta --paging never
```

### zellij

Install `zellij-org/zellij`, asset `zellij-<arch>-unknown-linux-musl.tar.gz`.

```bash
mkdir -p ~/.config/zellij
cp assets/zellij-config.kdl ~/.config/zellij/config.kdl   # ask before overwriting if one exists
zellij setup --check   # must print "[CONFIG FILE]: Well defined."
```

### btop

Install `aristocratos/btop`, asset `btop-<arch>-unknown-linux-musl.tar.gz` (binary is
at `btop/bin/btop` inside the tarball). Bundle also ships a `themes/` dir — ignore it,
we provide our own.

```bash
mkdir -p ~/.config/btop/themes
cp assets/cyberdeck.theme ~/.config/btop/themes/cyberdeck.theme
if [ ! -f ~/.config/btop/btop.conf ]; then
  btop --default-config > ~/.config/btop/btop.conf
fi
# then set (don't blind-overwrite the whole conf if it already existed):
sed -i 's/^color_theme = .*/color_theme = "cyberdeck"/' ~/.config/btop/btop.conf
```

Validate the theme file structurally (btop needs a real TTY to run, so this is the
practical verification): every line should match `theme[a-z_]+="#[0-9a-fA-F]{6}"`.

Optional: alias `top`/`htop` to `btop` in the bash aliases step below.

### bash aliases + `dh` help command

`assets/bash_aliases` is a complete, ready-to-use file (Claude Code aliases, git,
docker, python/conda, node, navigation, the modern-CLI-tools aliases, zellij, system/
network, utility functions, and the `devhelp`/`dh` function that prints all of it in
the cyberdeck palette).

If `~/.bash_aliases` doesn't exist, copy it directly. If it does, **read it first** —
either merge in only the sections/aliases the user doesn't already have, or append the
whole file under a clearly marked `# --- cyberdeck-setup additions ---` block, and
flag any alias name collisions to the user instead of silently overriding them.

Ensure `~/.bashrc` sources it (standard Debian/Ubuntu bashrc already has this — check
before adding):
```bash
grep -q 'bash_aliases' ~/.bashrc || cat >> ~/.bashrc << 'EOF'
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
EOF
```

Validate: `bash -n ~/.bash_aliases`, then a live check that `dh` resolves and runs
without error in an interactive shell.

## Step 3 — Final verification pass

Before reporting done, actually re-check everything, don't just trust each step's own
"it worked" — mirror what a human would do:
- `bash -n` every shell file touched
- `--version`/`--check`/`print-config` on every tool with a validation flag
- At least one live rendered sample per visual component (a mock starship prompt via
  `starship prompt --status=0`, a mock statusline payload, a real diff through delta)
- Confirm nothing in `~/.bashrc`/`~/.bash_aliases`/`~/.gitconfig` got duplicated if this
  skill is being re-run on a machine it already touched

## Step 4 — Report back

Tell the user plainly:
- What was installed and where (paths matter — these are all user-local, nothing
  touched `/usr` or needed root)
- What requires a new terminal tab/window (or full app restart) to actually show up
- What was terminal-specific and either automated or left as manual instructions
- Run `dh` for the full alias/shortcut reference

## Known gotchas (read before debugging from scratch)

- **`NerdFontMono` vs `NerdFont`**: the "Mono" patch variant is the one with the
  spacing bug. Always use the plain variant.
- **Private-Use-Area glyphs can silently vanish** when an LLM types them directly into
  a generated config file — some pipelines drop raw BMP PUA characters (`U+E000`–
  `U+F8FF`) even though nearby Supplementary-Plane PUA characters (`U+F0000`+) survive.
  If Claude is filling in Nerd Font icon values, prefer pulling exact codepoints from
  `starship preset nerd-font-symbols` (or writing them via explicit `\uXXXX` Python
  escapes) over typing the glyph character directly, and always verify with `tomllib`/
  a strict parser afterward rather than trusting a visual diff.
- **GTK terminal font/palette changes need a fresh pane.** `gsettings set` doesn't
  retroactively re-render an already-open tab.
- **`git diff | delta` won't show delta's styling if you only set `core.pager`** — git
  only invokes the configured pager for direct TTY output, not piped/redirected output.
  Test by piping into delta explicitly.
- **No sudo, no problem**: every tool here ships a portable Linux binary/tarball on its
  GitHub releases page. Don't reach for `apt`/`snap` first — they need root and this
  skill is designed to never need it.
