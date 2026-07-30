# stir

**Sleep soundly, wake up ready to live.**

stir covers your whole night. White noise helps you fall and stay asleep, fades to silence before your wake window, then stir listens for the subtle sounds of you naturally stirring and wakes you at the perfect moment — never later than your "up by" time.

## Features

- **One Nightly Input** - Just set the time you want to be up by
- **White Noise** - White, pink, or brown noise and nature sounds all night, with crossfade looping
- **Gradual Fade** - White noise fades out smoothly, ending a quiet gap before listening begins
- **Smart Detection** - Adjustable sensitivity detects subtle movements or only louder sounds
- **Gentle Alarm** - Volume builds gradually over 60 seconds
- **No-Alarm Mode** - The gentlest wake: when the white noise is gone, it's time
- **Multiple Sounds** - Gentle chimes, soft bells, ocean waves, or import your own
- **Haptic Patterns** - Heartbeat, pulse, escalating, or steady vibrations
- **Color Themes** - Ocean, Sunset, Forest, Lavender, Midnight, Coral
- **Live Activity** - See your night's status on your lock screen
- **Private by Design** - All processing on-device, nothing recorded or sent anywhere

## How It Works

1. Set the time you want to be up by (e.g., 7:00 AM)
2. Tap Start and drift off to white noise
3. The white noise fades out before your wake window opens
4. When stir detects you stirring, it gently wakes you — or the alarm fires at your "up by" time
5. Start your day feeling ready

## Requirements

- iOS 17.0+
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open stir.xcodeproj
```

## Privacy

stir uses your microphone solely to detect movement sounds during your wake window. Audio is processed on your device in real-time. Nothing is ever recorded, stored, or sent anywhere.

## Links

- [Website](https://timroman.github.io/stir/)
- [Privacy Policy](https://timroman.github.io/stir/privacy.html)
- [App Store](https://apps.apple.com/app/stir)

## License

MIT licensed — see LICENSE. © 2026 Pure Inference Ventures, LLC.
