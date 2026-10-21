# Homebrew tap for Isomux

```sh
brew install isomux/isomux/isomux
brew services start isomux
```

The setup link is in `$(brew --prefix)/var/log/isomux.log`. To update:

```sh
brew upgrade isomux
brew services restart isomux
```

macOS only. Guide: https://isomux.com/docs/hosting-local#install-with-homebrew

A workflow checks for a new [Isomux release](https://github.com/nmamano/isomux/releases)
every hour, installs and boots it on Apple silicon and Intel Macs, and
updates the formula only when both pass.
