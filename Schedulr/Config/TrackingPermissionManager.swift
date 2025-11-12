//
//  TrackingPermissionManager.swift
//  Schedulr
//
//  Created to handle App Tracking Transparency requests
//

import Foundation
import AppTrackingTransparency
import AdSupport

/// Manages App Tracking Transparency permission requests
@MainActor
public final class TrackingPermissionManager {
    public static let shared = TrackingPermissionManager()
    
    private init() {}
    
    /// Check if tracking authorization status is available (iOS 14+)
    var isTrackingAvailable: Bool {
        if #available(iOS 14, *) {
            return true
        }
        return false
    }
    
    /// Get current tracking authorization status
    @available(iOS 14, *)
    var trackingAuthorizationStatus: ATTrackingManager.AuthorizationStatus {
        ATTrackingManager.trackingAuthorizationStatus
    }
    
    /// Check if tracking is currently authorized
    var isTrackingAuthorized: Bool {
        if #available(iOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .authorized
        }
        return false
    }
    
    /// Request tracking authorization from the user
    /// - Returns: The authorization status after the request
    @available(iOS 14, *)
    func requestTrackingAuthorization() async -> ATTrackingManager.AuthorizationStatus {
        return await ATTrackingManager.requestTrackingAuthorization()
    }
    
    /// Request tracking authorization if not already determined
    /// This should be called before opening URLs that may track users
    /// - Returns: true if tracking is authorized or not available, false if denied
    public func requestTrackingIfNeeded() async -> Bool {
        guard #available(iOS 14, *) else {
            // Tracking not available on older iOS versions
            return true
        }
        
        let status = ATTrackingManager.trackingAuthorizationStatus
        
        // If already authorized, return true
        if status == .authorized {
            return true
        }
        
        // If denied or restricted, return false (don't open tracking URLs)
        if status == .denied || status == .restricted {
            return false
        }
        
        // If not determined, request permission
        if status == .notDetermined {
            let newStatus = await ATTrackingManager.requestTrackingAuthorization()
            return newStatus == .authorized
        }
        
        return false
    }
}

