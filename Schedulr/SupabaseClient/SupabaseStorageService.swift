import Foundation
import Supabase

/// Service for uploading files to Supabase Storage buckets.
/// Replaces the previous Cloudflare R2 implementation.
actor SupabaseStorageService {
    static let shared = SupabaseStorageService()

    /// Storage buckets
    enum Bucket: String {
        case avatars
        case eventCovers = "event-covers"
    }

    /// Errors that can occur during upload
    enum UploadError: LocalizedError {
        case notAuthenticated
        case uploadFailed(String)
        case invalidResponse
        case failedToConstructURL

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to upload files."
            case .uploadFailed(let message):
                return "Upload failed: \(message)"
            case .invalidResponse:
                return "Received an invalid response from the server."
            case .failedToConstructURL:
                return "Failed to construct the public URL for the uploaded file."
            }
        }
    }

    private init() {}

    /// Uploads image data to Supabase Storage and returns the public URL.
    /// - Parameters:
    ///   - data: The image data to upload
    ///   - filename: The filename for the uploaded file (e.g., "avatar_1234567890.jpg")
    ///   - bucket: The storage bucket (avatars or event-covers)
    ///   - contentType: The MIME type (e.g., "image/jpeg")
    /// - Returns: The public URL of the uploaded file
    func upload(
        data: Data,
        filename: String,
        bucket: Bucket,
        contentType: String = "image/jpeg"
    ) async throws -> URL {
        // Get authenticated user ID
        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            print("❌ [SupabaseStorage] Upload failed: not authenticated")
            throw UploadError.notAuthenticated
        }

        // Use lowercased UUID to match RLS policy which uses lower()
        let userId = session.user.id.uuidString.lowercased()

        // Construct the file path: {user_id}/{filename}
        let filePath = "\(userId)/\(filename)"

        print("📤 [SupabaseStorage] Uploading to bucket: \(bucket.rawValue), path: \(filePath)")

        do {
            // Upload to Supabase Storage with upsert to allow replacing existing files
            _ = try await SupabaseManager.shared.client.storage
                .from(bucket.rawValue)
                .upload(
                    filePath,
                    data: data,
                    options: FileOptions(
                        contentType: contentType,
                        upsert: true
                    )
                )

            // Get the public URL
            let publicURL = try SupabaseManager.shared.client.storage
                .from(bucket.rawValue)
                .getPublicURL(path: filePath)

            print("✅ [SupabaseStorage] Upload successful, URL: \(publicURL)")
            return publicURL
        } catch {
            print("❌ [SupabaseStorage] Upload failed: \(error)")
            throw UploadError.uploadFailed(error.localizedDescription)
        }
    }

    /// Deletes a file from Supabase Storage.
    /// - Parameters:
    ///   - filename: The filename to delete
    ///   - bucket: The storage bucket
    func delete(filename: String, bucket: Bucket) async throws {
        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            throw UploadError.notAuthenticated
        }
        let userId = session.user.id.uuidString
        let filePath = "\(userId)/\(filename)"

        _ = try await SupabaseManager.shared.client.storage
            .from(bucket.rawValue)
            .remove(paths: [filePath])
    }
}

// MARK: - Convenience Extensions

extension SupabaseStorageService {
    /// Generates a unique filename for an avatar upload
    /// - Returns: A unique filename like "avatar_TIMESTAMP.jpg"
    static func avatarFilename() -> String {
        return "avatar_\(Int(Date().timeIntervalSince1970)).jpg"
    }

    /// Generates a unique filename for an event cover upload
    /// - Returns: A unique filename like "cover_TIMESTAMP.jpg"
    static func eventCoverFilename() -> String {
        return "cover_\(Int(Date().timeIntervalSince1970)).jpg"
    }
}
