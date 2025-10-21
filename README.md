# MacOS Live Screensaver

A macOS screensaver that plays live video streams. Supports YouTube videos and direct HLS streams.

**Disclaimer**: This project was entirely vibe-coded. I've never written Swift before in my life.

**Note**: This was tested exclusively on macOS Tahoe on an M2 MacBook. Your mileage may vary on other versions/hardware.

## Why?

Turn any live stream into your screensaver/lockscreen. Some examples:

### [Namib Desert Wildlife](https://www.youtube.com/watch?v=ydYDqZQpim8)
<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/19b39408-8d67-4699-87c9-bb218198190d" />

### [Times Square](https://www.youtube.com/watch?v=rnXIjl_Rzy4)
<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/5db52a77-24a2-4bd1-9698-d3f2258b4890" />

### [The News](https://www.youtube.com/watch?v=iipR5yUp36o)

<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/1d528a72-3d1b-4151-8e9c-347cdfe8d94c" />

## Requirements

- macOS
- Swift compiler (Xcode Command Line Tools)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (optional, for YouTube support)

## Installation

### Install yt-dlp (for YouTube support)

Using Homebrew:
```bash
brew install yt-dlp
```

Or using pip:
```bash
pip install yt-dlp
```

### Build and Install

1. Build:
```bash
bash build.sh
```

2. Install:
```bash
open build/LiveScreensaver.saver
```

Or manually:
```bash
cp -r build/LiveScreensaver.saver ~/Library/Screen\ Savers/
```

## Usage

1. Open **System Preferences** → **Screen Saver**
2. Select **Live Screensaver**
3. Click **Options** to configure
4. Enter a video URL:
   - YouTube: `https://www.youtube.com/watch?v=VIDEO_ID` **(live streams only)**
   - HLS stream: `https://example.com/stream.m3u8`

**Note**: Only live YouTube videos are supported. Regular (non-live) YouTube videos will not work.

**Note**: macOS screensaver UI can be buggy. If the Options button is unresponsive, try closing and reopening System Settings. PRs welcome for anyone who can figure out why.

## Troubleshooting

**YouTube videos don't play**:
- Make sure yt-dlp is installed and in your PATH
- Verify you're using a **live** YouTube stream - regular videos are not supported

**Black screen**: Wait a few seconds for loading, or try a different URL
