# txt2img

Renders text onto a PNG image from the command line. Uses bitmap fonts (BDF/PCF) and outputs standard PNG files.

## Install

Grab a binary from the [releases page](../../releases).

Or build from source (requires Zig master):

```sh
zig build --release=small
```

## Usage

```
txt2img "text to draw" [<options>]

Options:
    -o, --output <file>         Output filename (default: image.png)
    -s, --size <width>x<height> Image dimensions (default: 512x512)
    -w, --width <value>         Width only
    -H, --height <value>        Height only
    -p, --pos <x,y>             Text origin (default: 16,32)
    -x <value>                  X position only
    -y <value>                  Y position only
    -bg <color>                 Background color (default: white)
    -fg <color>                 Foreground color (default: black)
    -f, --font <path>           BDF or PCF font file
    -S, --scale <factor>        Scale factor (default: 1.0)
    -d, --display               Render to terminal
    -h, --help                  Show this help
```

Colors accept named values (`white`, `black`, `red`, `green`, `blue`, `gray`, `yellow`, `cyan`, `magenta`), `#RRGGBB`, or `#RRGGBBAA`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full history of changes.

## License

[MIT](LICENSE)
