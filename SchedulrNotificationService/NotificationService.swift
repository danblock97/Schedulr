import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            // Get image URL from notification payload
            let imageUrlString = request.content.userInfo["image_url"] as? String
            let emoji = request.content.userInfo["emoji"] as? String
            
            if let imageUrlString = imageUrlString,
               let imageUrl = URL(string: imageUrlString) {
                // Download the image
                downloadAndAttachImage(url: imageUrl) { [weak self] attachment in
                    if let attachment = attachment {
                        bestAttemptContent.attachments = [attachment]
                    }
                    
                    // Modify notification content if needed (e.g., add emoji to title if not already present)
                    if let emoji = emoji,
                       !bestAttemptContent.title.contains(emoji) {
                        bestAttemptContent.title = "\(emoji) \(bestAttemptContent.title)"
                    }
                    
                    contentHandler(bestAttemptContent)
                }
            } else {
                // No image URL, just modify title if emoji is present
                if let emoji = emoji,
                   !bestAttemptContent.title.contains(emoji) {
                    bestAttemptContent.title = "\(emoji) \(bestAttemptContent.title)"
                }
                
                contentHandler(bestAttemptContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    private func downloadAndAttachImage(url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { (downloadedUrl, response, error) in
            guard let downloadedUrl = downloadedUrl, error == nil else {
                completion(nil)
                return
            }
            
            // Move the downloaded file to a temporary directory with a proper extension
            let fileManager = FileManager.default
            let tmpSubFolderURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: true)
            
            do {
                try fileManager.createDirectory(at: tmpSubFolderURL, withIntermediateDirectories: true, attributes: nil)
                
                // Determine file extension from URL or content type
                var fileExtension = url.pathExtension
                if fileExtension.isEmpty {
                    // Try to get extension from content type
                    if let httpResponse = response as? HTTPURLResponse,
                       let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                        if contentType.contains("png") {
                            fileExtension = "png"
                        } else if contentType.contains("gif") {
                            fileExtension = "gif"
                        } else {
                            fileExtension = "jpg"
                        }
                    } else {
                        fileExtension = "jpg"
                    }
                }
                
                let fileURL = tmpSubFolderURL.appendingPathComponent("image.\(fileExtension)")
                try fileManager.moveItem(at: downloadedUrl, to: fileURL)
                
                // Create attachment
                let attachment = try UNNotificationAttachment(identifier: "image", url: fileURL, options: nil)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        
        task.resume()
    }
}
