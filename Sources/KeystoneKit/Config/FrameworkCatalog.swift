import Foundation

/// Apple's frameworks, grouped by what depending on one *means*.
///
/// This is the one roster the tool can safely hardcode, because it belongs to
/// the platform rather than to any project. A rule never says "domain must not
/// import SwiftUI" — it says "domain denies the `ui` category", and this table
/// is what turns the second sentence into the first.
public struct FrameworkCatalog: Sendable {
    public static let core = "core"
    public static let ui = "ui"
    public static let persistence = "persistence"
    public static let networking = "networking"
    public static let crypto = "crypto"
    public static let media = "media"
    public static let system = "system"
    public static let testing = "testing"

    public static let categories = [core, ui, persistence, networking, crypto, media, system, testing]

    private let moduleToCategory: [String: String]

    public init(overrides: [String: [String]] = [:]) {
        var table: [String: String] = [:]
        for (category, modules) in FrameworkCatalog.builtIn {
            for module in modules { table[module] = category }
        }
        // A project may reclassify a framework, or classify one Apple has
        // shipped since this table was written, without waiting for a release.
        for (category, modules) in overrides {
            for module in modules { table[module] = category }
        }
        self.moduleToCategory = table
    }

    /// The category a module belongs to, or nil when the module is not a
    /// platform framework at all — which is how first-party and third-party
    /// modules fall through to their own rules.
    public func category(of module: String) -> String? {
        moduleToCategory[module]
    }

    public func isPlatformFramework(_ module: String) -> Bool {
        moduleToCategory[module] != nil
    }

    public static let builtIn: [String: [String]] = [
        core: [
            "Swift", "Foundation", "FoundationNetworking", "Combine", "Observation",
            "Dispatch", "os", "OSLog", "Synchronization", "Darwin", "Glibc",
            "RegexBuilder", "SwiftUICore", "_Concurrency", "ObjectiveC"
        ],
        ui: [
            "SwiftUI", "UIKit", "AppKit", "WatchKit", "TVUIKit", "CarPlay",
            "SpriteKit", "SceneKit", "RealityKit", "ARKit", "MapKit", "WebKit",
            "PhotosUI", "QuickLook", "QuickLookUI", "QuickLookThumbnailing",
            "PencilKit", "VisionKit", "Charts", "TipKit", "WidgetKit",
            "ActivityKit", "MessageUI", "SafariServices", "CoreGraphics",
            "CoreAnimation", "CoreText", "UniformTypeIdentifiers", "SwiftUIIntrospect"
        ],
        persistence: [
            "CoreData", "SwiftData", "CloudKit", "CoreSpotlight", "FileProvider",
            "SQLite3", "CoreDataEvolution"
        ],
        networking: [
            "Network", "CFNetwork", "MultipeerConnectivity", "NetworkExtension",
            "WatchConnectivity"
        ],
        crypto: [
            "CryptoKit", "Security", "LocalAuthentication", "AuthenticationServices",
            "DeviceCheck", "CommonCrypto", "CryptoTokenKit"
        ],
        media: [
            "AVFoundation", "AVKit", "CoreMedia", "CoreAudio", "AudioToolbox",
            "VideoToolbox", "Photos", "CoreImage", "Vision", "PDFKit",
            "MediaPlayer", "CoreVideo", "Metal", "MetalKit", "ImageIO"
        ],
        system: [
            "CoreLocation", "CoreMotion", "HealthKit", "HomeKit", "EventKit",
            "Contacts", "ContactsUI", "UserNotifications", "BackgroundTasks",
            "StoreKit", "PassKit", "CoreBluetooth", "CoreNFC", "MetricKit",
            "Intents", "IntentsUI", "AppIntents", "CallKit", "Speech",
            "NaturalLanguage", "CoreML", "CreateML", "GameKit", "ExternalAccessory",
            "AdSupport", "AppTrackingTransparency", "SystemConfiguration",
            "MachO", "IOKit", "ServiceManagement"
        ],
        testing: [
            "XCTest", "Testing", "SwiftUITesting"
        ]
    ]
}
