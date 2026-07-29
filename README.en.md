# CLIProxy GUI

English | [简体中文](README.md)

CLIProxy GUI is a native macOS SwiftUI client for managing multiple
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) nodes from one place.

The project is at an early stage. Changes to the Management API or upstream quota
endpoints may require corresponding updates here.

> This is an independent community project. It is not affiliated with or endorsed
> by CLIProxyAPI, OpenAI, Anthropic, or Moonshot AI.

## Features

- Save, switch between, and concurrently check multiple CLIProxyAPI nodes
- Inspect latency, versions, credential health, account quotas, models, daily usage,
  plugins, and runtime settings
- Read and edit the complete `config.yaml`
- Manage client API keys
- View, upload, enable, disable, and delete JSON authentication files
- View, search, and clear server logs
- Inspect CAP Token Usage Tracker trends, models, dimensions, requests, and costs
- Store Management Keys in macOS Keychain
- Enforce a single running app instance
- Open the node's built-in Management Center
- Connect to HTTP nodes when required, although HTTPS is strongly recommended

Account quota checks currently support Codex, Claude, and Kimi OAuth credentials.
Checks run concurrently per account and no more than once every three minutes per
node, unless authentication files change.

The application UI is currently in Simplified Chinese.

## Requirements

- macOS 14 Sonoma or later
- A CLIProxyAPI node with remote management enabled
- Xcode 26 to build from source
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) when changing project settings
- `cap-token-usage-tracker` on the node for the usage dashboard

## Usage

1. Enable remote management in CLIProxyAPI and configure a strong Management Key.
2. Launch the app and add the node address and Management Key.
3. Addresses may be `host:port`, complete HTTP(S) URLs, or URLs ending in
   `/v0/management` or `/management.html`.

An address without a URL scheme defaults to HTTP. HTTP transmits the Management Key
and management data without transport encryption and should only be used on a
trusted network.

## Build from source

The generated Xcode project is checked in:

```bash
open CLIProxyGUI.xcodeproj
```

Build and run the test suite from the command line:

```bash
./Scripts/ci.sh
```

`project.yml` is the source of truth for project structure. Regenerate the Xcode
project after changing it:

```bash
xcodegen generate
```

## Data and networking

- Node names and addresses are stored locally in `UserDefaults`.
- Management Keys are stored in macOS Keychain and are not written to the repository
  or application logs.
- The app contains no telemetry, analytics, advertising, or project-operated service.
- Normal requests travel directly from the Mac to user-configured CLIProxyAPI nodes.
- For account quota checks, the app sends an `auth_index` and request template to the
  node's Management `api-call` endpoint. The node injects the OAuth credential and
  contacts the upstream provider; the OAuth token is not returned to this app.

See [SECURITY.md](SECURITY.md) for the complete security boundary and vulnerability
reporting process.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing.

## License

CLIProxy GUI is available under the [MIT License](LICENSE).
