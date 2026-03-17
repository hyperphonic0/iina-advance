# RAM Disk Integration for Screenshots

This implementation provides automatic RAM disk management for temporary screenshot storage in IINA.

## Overview

The system consists of three components:

1. **RAMDiskManager** - Low-level RAM disk creation/mounting using APFS
2. **ScreenshotStorageManager** - High-level manager that integrates with IINA's preferences
3. **Integration** - Hooked into AppDelegate and MPV initialization

## Features

- **APFS filesystem** - Modern, efficient filesystem for macOS
- **Automatic cleanup** - RAM disk is unmounted when app terminates
- **Preference-based** - Can be enabled/disabled via preferences
- **Hot-reload** - Changes to size or enabled status are applied immediately
- **Fallback** - Gracefully falls back to standard temp directory if RAM disk creation fails
- **Thread-safe** - All operations are protected with locks

## Usage

### For Users

Add these preferences to enable RAM disk for screenshots:

```swift
// Enable RAM disk for temporary screenshots
Preference.set(true, for: .screenshotUseRAMDisk)

// Set RAM disk size (minimum 32 MB for APFS)
Preference.set(100, for: .screenshotRAMDiskSizeMB)  // 100 MB
```

### For Developers

The system is automatically initialized on app launch. To get a temporary screenshot URL:

```swift
// In your screenshot code
let tempURL = ScreenshotStorageManager.shared.getTemporaryScreenshotURL(format: "png")

// Take screenshot, save to tempURL
// ...

// The file will be on the RAM disk (if enabled) for fast I/O
```

### Manual Control

```swift
// Setup manually (if needed)
ScreenshotStorageManager.shared.setup()

// Get the current temporary directory (RAM disk or fallback)
let tempDir = ScreenshotStorageManager.shared.getTemporaryDirectory()

// Cleanup manually (usually automatic on app termination)
ScreenshotStorageManager.shared.cleanup()

// Reload if preferences changed
ScreenshotStorageManager.shared.reloadIfNeeded()
```

## Benefits

1. **Performance** - RAM is significantly faster than SSD for temporary file operations
2. **SSD longevity** - Reduces unnecessary writes to SSD
3. **Privacy** - Temporary files are automatically cleared when RAM disk unmounts
4. **Clean** - No leftover temp files on disk

## Technical Details

### RAM Disk Size

- Minimum: 32 MB (APFS requirement)
- Default: 100 MB
- Recommended: 50-200 MB depending on screenshot frequency

### Filesystem

- Uses APFS (Apple File System)
- Case-insensitive by default
- Can be changed to case-sensitive if needed

### Mount Point

- Location: `/Volumes/IINAScreenshots`
- Automatically created when RAM disk is mounted
- Removed when RAM disk is unmounted

### Integration Points

1. **AppDelegate.applicationDidFinishLaunching** - Initial setup
2. **AppDelegate.registerUserDefaultValues** - Register default preferences
3. **AppDelegate.prefDidChange** - Handle preference changes
4. **MPV_Init.mpvSetOptionsFromPrefs** - Set screenshot directory
5. **NSApplication.willTerminateNotification** - Cleanup on app termination

## Error Handling

All operations have comprehensive error handling:

- Creation failures fall back to standard temp directory
- Mounting errors are logged but don't crash the app
- Unmounting errors are logged for debugging

## Logging

All operations are logged via IINA's logging system:

```swift
RAMDiskManager.log       // Low-level RAM disk operations
ScreenshotStorageManager.log  // High-level storage management
```

## Configuration

Default configuration can be changed in `ScreenshotStorageManager`:

```swift
// Change volume name
volumeName: "MyCustomName"

// Change to case-sensitive APFS
formatProcess.arguments = ["erasevolume", "Case-sensitive APFS", volumeName, devicePath]
```

## Performance Characteristics

- **Creation time**: ~200-500ms (one-time at startup)
- **Unmount time**: ~100-200ms (on app termination)
- **Read/write speed**: RAM speed (~10-20 GB/s)
- **Overhead**: Minimal memory overhead for small temp files

## Troubleshooting

### RAM disk not created

1. Check if user has admin privileges
2. Verify size is at least 32 MB
3. Check system logs for errors
4. Ensure sufficient RAM available

### Falls back to temp directory

Normal behavior if:
- Preference is disabled
- Creation failed
- Not in interactive launch mode

### Old files remain

The RAM disk is volatile - all files are lost when unmounted. If files persist, they're in the fallback directory (`Utility.screenshotCacheURL`), not on the RAM disk.

## Future Enhancements

Possible improvements:

1. Add size monitoring to prevent disk full
2. Add automatic size adjustment based on usage
3. Support multiple RAM disks for different purposes
4. Add encryption for sensitive temporary files
5. Add metrics/statistics for usage tracking
