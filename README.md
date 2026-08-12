# AppReso APK Builder

This repository is used by the [AppReso WordPress plugin](https://appreso.com) to build Android APKs from WordPress sites.

## How It Works

1. The AppReso WordPress plugin sends a build request to this repository via GitHub API
2. GitHub Actions builds a Flutter app configured with the user's site URL and branding
3. The generated APK is uploaded as a GitHub Release
4. A callback notifies the WordPress plugin that the APK is ready for download

## Manual Build

You can also trigger a build manually:

1. Go to the **Actions** tab
2. Select **Build APK** workflow
3. Click **Run workflow**
4. Enter your site URL and app name
5. Wait for the build to complete
6. Download the APK from the generated release

## Requirements

- This repository must be **public** for free GitHub Actions minutes
- The WordPress site must have the AppReso plugin installed and active

## License

GPL v2 or later
