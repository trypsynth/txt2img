# Changelog

### Version 0.2.0
* Added the `--line-spacing` flag to control vertical gap between lines.
* Added the `--align` flag for text alignment (left, center, right).
* Added support for multiline text.
* Added the `--fit` flag to automatically fit text within image bounds.
* Added the `--padding` flag to specify text padding.
* Added the `--shadow` flag for text shadows.
* Improved the CLI help output and formatting.
* Improved error handling for missing font files.
* Updated GitHub Actions to upload raw binaries instead of zip/tarball archives.

### Version 0.1.0
* Initial release of the txt2img CLI tool.
* Support for basic text rendering on images.
* Support for custom bitmap fonts (BDF/PCF).
* Basic CLI interface with position and size flags.
* GitHub Actions workflow for cross-platform releases.
* Statically link libc for better portability.
