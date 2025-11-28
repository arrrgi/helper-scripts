# helper-scripts

A collection of useful POSIX-compliant shell scripts accessible directly via cURL.

## Overview

This repository contains helper shell scripts that are served via GitHub Pages at **[utils.bald.engineer](https://utils.bald.engineer)**.

## Usage

Scripts can be executed directly using the `curl` and pipe method:

```sh
curl -fsSL https://utils.bald.engineer/<script-name>.sh | sh
```

### Curl Flags Explained

- `-f` — Fail (exit with error) on HTTP errors (4xx/5xx status codes)
- `-s` — Silent mode (no progress meter)
- `-S` — Show errors when silent mode is enabled
- `-L` — Follow redirects

## Compatibility

Scripts in this repository are designed to be **POSIX-compliant** for maximum compatibility across different Unix-like systems and shells.

## License

This project is licensed under the [MIT License](LICENSE).
