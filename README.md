# r2d2

Simple shareable `r2d2` function package for teammates.

This helper is fixed to `code.levelup.cce.af.mil`.

## Files

- `r2d2.sh`: main implementation for Bash users
- `r2d2.zsh`: small Zsh wrapper that calls `r2d2.sh`

## Requirements

- `bash`
- `glab`
- `git`
- `jq`
- `column`

## Quick Install (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/austinkennethtucker/r2d2/main/install.sh | bash
```

This installs dependencies, downloads r2d2 to `~/.local/share/r2d2/`, and adds it to your shell rc.

## Manual Setup

Clone this repo anywhere you want to keep it:

```bash
git clone https://github.com/austinkennethtucker/r2d2.git
cd r2d2
```

Or download a tagged release from GitHub Releases and unpack it.

Bash, load it now:

```bash
source /path/to/r2d2/r2d2.sh
```

Bash, make it permanent:

```bash
echo 'source /path/to/r2d2/r2d2.sh' >> ~/.bashrc
source ~/.bashrc
```

macOS Bash users may prefer:

```bash
echo 'source /path/to/r2d2/r2d2.sh' >> ~/.bash_profile
source ~/.bash_profile
```

Zsh, load it now:

```zsh
source /path/to/r2d2/r2d2.zsh
```

Zsh, make it permanent:

```zsh
echo 'source /path/to/r2d2/r2d2.zsh' >> ~/.zshrc
source ~/.zshrc
```

## Usage

```bash
r2d2 --config
r2d2 --list
r2d2 --clone sec/security-internal
```

## CI/CD

- CI runs ShellCheck on `r2d2.sh`, parses `r2d2.zsh`, and smoke-tests Bash and Zsh sourcing on Ubuntu and macOS.
- Pushing a tag like `v1.0.0` builds `.tar.gz` and `.zip` release assets and publishes them to GitHub Releases.
- Each release also includes a SHA-256 checksum file.

Create a release:

```bash
git tag v1.0.0
git push origin main --tags
```
