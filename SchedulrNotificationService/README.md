# Notification Service Extension

This is a Notification Service Extension target for Schedulr that enables rich notifications with images.

## Setup Instructions

1. In Xcode, go to File > New > Target
2. Select "Notification Service Extension"
3. Name it "SchedulrNotificationService"
4. Set the bundle identifier to `uk.co.schedulr.Schedulr.SchedulrNotificationService` (or your app's bundle ID + `.SchedulrNotificationService`)
5. Replace the generated `NotificationService.swift` with the provided file
6. Copy the `Info.plist` to the extension target
7. Ensure the extension target has the same deployment target as the main app

## Features

- Downloads cover images from notification payload
- Attaches images to notifications for rich media display
- Adds emoji to notification titles when present in payload

## Testing

To test rich notifications:
1. Ensure your app has notification permissions
2. Create an event with a category that has a cover image
3. Send a notification (invite, update, or reminder)
4. The notification should display with the cover image attached

