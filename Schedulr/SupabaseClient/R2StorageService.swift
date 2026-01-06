import Foundation

/// Service for uploading files to Cloudflare R2 storage via pre-signed URLs.
/// This replaces direct Supabase Storage uploads.
actor R2StorageService {
    static let shared = R2StorageService()
    
    /// Storage folders (previously Supabase buckets)
    enum Folder: String {
        case avatars
        case eventCovers = "event-covers"
    }
    
    /// Errors that can occur during upload
    enum UploadError: LocalizedError {
        case missingConfiguration
        case failedToGetPresignedURL(String)
        case uploadFailed(String)
        case invalidResponse
        case notAuthenticated
        
        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Storage configuration is missing. Please check CDN_URL in Info.plist."
            case .failedToGetPresignedURL(let message):
                return "Failed to get upload URL: \(message)"
            case .uploadFailed(let message):
                return "Upload failed: \(message)"
            case .invalidResponse:
                return "Received an invalid response from the server."
            case .notAuthenticated:
                return "You must be signed in to upload files."
            }
        }
    }
    
    /// Response from the upload-url Edge Function
    private struct PresignedURLResponse: Decodable {
        let uploadUrl: String
        let publicUrl: String
        let key: String
    }
    
    /// Error response from the Edge Function
    private struct ErrorResponse: Decodable {
        let error: String
    }
    
    private init() {}
    
    /// Uploads image data to R2 storage and returns the public CDN URL.
    /// - Parameters:
    ///   - data: The image data to upload
    ///   - filename: The filename for the uploaded file (e.g., "avatar_1234567890.jpg")
    ///   - folder: The storage folder (avatars or event-covers)
    ///   - contentType: The MIME type (e.g., "image/jpeg")
    /// - Returns: The public CDN URL of the uploaded file
    func upload(
        data: Data,
        filename: String,
        folder: Folder,
        contentType: String = "image/jpeg"
    ) async throws -> URL {
        // Step 1: Get access token
        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            throw UploadError.notAuthenticated
        }
        let accessToken = session.accessToken
        
        // Step 2: Get Supabase URL for calling the Edge Function
        guard let supabaseURL = SupabaseManager.shared.configuration?.url else {
            throw UploadError.missingConfiguration
        }
        
        // Step 3: Call the upload-url Edge Function to get a pre-signed URL
        let presignedResponse = try await getPresignedURL(
            supabaseURL: supabaseURL,
            accessToken: accessToken,
            filename: filename,
            folder: folder,
            contentType: contentType
        )
        
        // Step 4: Upload the file directly to R2 using the pre-signed URL
        try await uploadToR2(
            uploadURL: presignedResponse.uploadUrl,
            data: data,
            contentType: contentType
        )
        
        // Step 5: Return the public CDN URL
        guard let publicURL = URL(string: presignedResponse.publicUrl) else {
            throw UploadError.invalidResponse
        }
        
        return publicURL
    }
    
    // MARK: - Private Methods
    
    private func getPresignedURL(
        supabaseURL: URL,
        accessToken: String,
        filename: String,
        folder: Folder,
        contentType: String
    ) async throws -> PresignedURLResponse {
        let url = supabaseURL.appendingPathComponent("functions/v1/upload-url")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "filename": filename,
            "folder": folder.rawValue,
            "contentType": contentType
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            return try decoder.decode(PresignedURLResponse.self, from: data)
        } else {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw UploadError.failedToGetPresignedURL(errorResponse.error)
            }
            throw UploadError.failedToGetPresignedURL("HTTP \(httpResponse.statusCode)")
        }
    }
    
    private func uploadToR2(
        uploadURL: String,
        data: Data,
        contentType: String
    ) async throws {
        guard let url = URL(string: uploadURL) else {
            throw UploadError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        // R2/S3 returns 200 for successful PUT
        guard httpResponse.statusCode == 200 else {
            throw UploadError.uploadFailed("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Convenience Extensions

extension R2StorageService {
    /// Generates a unique filename for an avatar upload
    /// Note: The user ID is added by the Edge Function, so this only returns the filename
    /// - Returns: A unique filename like "avatar_TIMESTAMP.jpg"
    static func avatarFilename() -> String {
        return "avatar_\(Int(Date().timeIntervalSince1970)).jpg"
    }
    
    /// Generates a unique filename for an event cover upload
    /// Note: The user ID is added by the Edge Function, so this only returns the filename
    /// - Returns: A unique filename like "cover_TIMESTAMP.jpg"
    static func eventCoverFilename() -> String {
        return "cover_\(Int(Date().timeIntervalSince1970)).jpg"
    }
}

