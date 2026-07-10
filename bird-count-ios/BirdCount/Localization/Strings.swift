import Foundation
import SwiftUI

// MARK: - Localization Helper

/// A type-safe wrapper for localized strings
struct LocalizedString {
    let key: String
    let comment: String?
    
    init(_ key: String, comment: String? = nil) {
        self.key = key
        self.comment = comment
    }
    
    /// Returns the localized string value
    var string: String {
        NSLocalizedString(key, comment: comment ?? "")
    }
    
    /// Returns a LocalizedStringKey for use with SwiftUI Text views
    var localizedStringKey: LocalizedStringKey {
        LocalizedStringKey(key)
    }
}

// MARK: - String Constants

/// Type-safe localized string constants
enum Strings {
    
    // MARK: - General
    enum General {
        static let ok = LocalizedString("general.ok")
        static let cancel = LocalizedString("general.cancel")
        static let done = LocalizedString("general.done")
        static let close = LocalizedString("general.close")
        static let clear = LocalizedString("general.clear")
        static let loading = LocalizedString("general.loading")
        static let error = LocalizedString("general.error")
        static let menu = LocalizedString("general.menu")
        static let user = LocalizedString("general.user")
    }
    
    // MARK: - User
    enum User {
        static let email = LocalizedString("user.email")
        static let emailPlaceholder = LocalizedString("user.email.placeholder")
        static let queuedForUpload = LocalizedString("user.queued.for.upload")
        static let peerQueued = LocalizedString("user.peer.queued")
        static let connectionAvailable = LocalizedString("user.connection.available")
        static let connectionUnavailable = LocalizedString("user.connection.unavailable")
    }
    
    // MARK: - Tabs
    enum Tab {
        static let home = LocalizedString("tab.home")
        static let summary = LocalizedString("tab.summary")
        static let log = LocalizedString("tab.log")
    }
    
    // MARK: - Home Screen
    enum Home {
        static let title = LocalizedString("home.title")
        static let loading = LocalizedString("home.loading")
        
        enum Filter {
            static let placeholder = LocalizedString("home.filter.placeholder")
            static let clear = LocalizedString("home.filter.clear")
        }
    }
    
    // MARK: - Species
    enum Species {
        static let species = LocalizedString("species")
        static let observed = LocalizedString("species.observed")
        static let individuals = LocalizedString("species.individuals")
        static let inRange = LocalizedString("species.in.range")
        
        enum List {
            static let empty = LocalizedString("species.list.empty")
            static let emptyDescription = LocalizedString("species.list.empty.description")
        }
    }
    
    // MARK: - Observation
    enum Observation {
        static let count = LocalizedString("observation.count")
        static let add = LocalizedString("observation.add")
        static let edit = LocalizedString("observation.edit")
        static let none = LocalizedString("observation.none")
        static let noneInRange = LocalizedString("observation.none.range")
        static let unknown = LocalizedString("observation.unknown")
        static let delete = LocalizedString("observation.delete")
        static let adjust = LocalizedString("observation.adjust")
        static let details = LocalizedString("observation.details")
        static let observer = LocalizedString("observation.observer")
        static let status = LocalizedString("observation.status")
        
        enum Status {
            static let pending = LocalizedString("observation.status.pending")
            static let completed = LocalizedString("observation.status.completed")
        }
    }
    
    // MARK: - Date Range
    enum DateRange {
        static let allTime = LocalizedString("date.range.all.time")
        static let today = LocalizedString("date.range.today")
        static let custom = LocalizedString("date.range.custom")
        static let from = LocalizedString("date.range.from")
        static let to = LocalizedString("date.range.to")
        static let previous = LocalizedString("date.range.previous")
        static let next = LocalizedString("date.range.next")
        static let all = LocalizedString("date.range.all")
    }
    
    // MARK: - Settings
    enum Settings {
        static let title = LocalizedString("settings.title")
        static let checklist = LocalizedString("settings.checklist")
        static let commonness = LocalizedString("settings.commonness")
    }
    
    // MARK: - Summary
    enum Summary {
        static let title = LocalizedString("summary.title")
        static let observations = LocalizedString("summary.observations")
        static let exportTitle = LocalizedString("summary.export.title")
    }
    
    // MARK: - Share & Export
    enum Share {
        static let title = LocalizedString("share.title")
        static let export = LocalizedString("share.export")
        static let sendNearby = LocalizedString("share.send.nearby")
        static let receiveNearby = LocalizedString("share.receive.nearby")
        static let includeCounts = LocalizedString("share.include.counts")
        
        enum Accessibility {
            static let label = LocalizedString("share.accessibility.label")
            static let settings = LocalizedString("share.accessibility.settings")
            static let editRange = LocalizedString("share.accessibility.edit.range")
        }
    }
    
    // MARK: - Export Formats
    enum Export {
        static let format = LocalizedString("export.format")
        static let formatSummary = LocalizedString("export.format.summary")
        static let formatJSON = LocalizedString("export.format.json")
        static let subject = LocalizedString("export.subject")
    }
    
    // MARK: - Import
    enum Import {
        static let importData = LocalizedString("import.import")
        static let selectFile = LocalizedString("import.select.file")
        static let instructions = LocalizedString("import.instructions")
        static let error = LocalizedString("import.error")
        static let success = LocalizedString("import.success")
        static let successMessage = LocalizedString("import.success.message")
        static let unknownError = LocalizedString("import.unknown.error")
    }
    
    // MARK: - Sync
    enum Sync {
        static let title = LocalizedString("sync.title")
        static let pairDevice = LocalizedString("sync.pair.device")
        static let pairedAutoSyncs = LocalizedString("sync.paired.auto.syncs")
        static let unpair = LocalizedString("sync.unpair")
        static let pairedDevices = LocalizedString("sync.paired.devices")
        static let pairExplanation = LocalizedString("sync.pair.explanation")
        static let noPairedDevices = LocalizedString("sync.no.paired.devices")
        static let includesSynced = LocalizedString("sync.includes.synced")
        static let fromSyncedUsers = LocalizedString("sync.from.synced.users")
        static let pairTitle = LocalizedString("sync.pair.title")
        static let pairNewDevice = LocalizedString("sync.pair.new.device")
        static let pairInstructions = LocalizedString("sync.pair.instructions")
        static let pairUnsupported = LocalizedString("sync.pair.unsupported")
        static let badgeQueued = LocalizedString("sync.badge.queued")
        static let badgeSyncing = LocalizedString("sync.badge.syncing")
        static let processing = LocalizedString("sync.processing")
        static let looking = LocalizedString("sync.looking")
        static let foundDevices = LocalizedString("sync.found.devices")
        static let waitingConnection = LocalizedString("sync.waiting.connection")
        static let connecting = LocalizedString("sync.connecting")
        static let connected = LocalizedString("sync.connected")
        static let sendObservations = LocalizedString("sync.send.observations")
        static let sending = LocalizedString("sync.sending")
        static let receiving = LocalizedString("sync.receiving")
        static let complete = LocalizedString("sync.complete")
        static let failed = LocalizedString("sync.failed")
        static let findDevices = LocalizedString("sync.find.devices")
        static let waitConnection = LocalizedString("sync.wait.connection")
        static let sendDescription = LocalizedString("sync.send.description")
        static let receiveDescription = LocalizedString("sync.receive.description")
        static let makeSure = LocalizedString("sync.make.sure")
        static let waitReceive = LocalizedString("sync.wait.receive")
        static let successSent = LocalizedString("sync.success.sent")
        static let successReceived = LocalizedString("sync.success.received")
        static let recordSentSingle = LocalizedString("sync.record.sent.single")
        static let recordSentMultiple = LocalizedString("sync.record.sent.multiple")
        static let recordReceivedSingle = LocalizedString("sync.record.received.single")
        static let recordReceivedMultiple = LocalizedString("sync.record.received.multiple")
        
        enum Approval {
            static let request = LocalizedString("sync.request")
            static let from = LocalizedString("sync.from")
            static let importSummary = LocalizedString("sync.import.summary")
            static let observationsLabel = LocalizedString("sync.observations.label")
            static let speciesLabel = LocalizedString("sync.species.label")
            static let dateRangeLabel = LocalizedString("sync.date.range.label")
            static let to = LocalizedString("sync.to")
            static let disclaimer = LocalizedString("sync.disclaimer")
            static let accept = LocalizedString("sync.accept")
            static let decline = LocalizedString("sync.decline")
            static let incoming = LocalizedString("sync.incoming")
        }
    }
    
    // MARK: - Accessibility
    enum Accessibility {
        static let speciesObserved = LocalizedString("accessibility.species.observed")
        static let countLabel = LocalizedString("accessibility.count.label")
    }
    
    // MARK: - Errors
    enum Error {
        static let taxonomyLoading = LocalizedString("error.taxonomy.loading")
        static let taxonomyEmpty = LocalizedString("error.taxonomy.empty")
        static let network = LocalizedString("error.network")
        static let unknown = LocalizedString("error.unknown")
        
        enum Sync {
            static let noDevice = LocalizedString("error.sync.no.device")
            static let transferFailed = LocalizedString("error.sync.transfer.failed")
            static let cancelled = LocalizedString("error.sync.cancelled")
            static let networkUnavailable = LocalizedString("error.sync.network.unavailable")
            static let security = LocalizedString("error.sync.security")
            static let timeout = LocalizedString("error.sync.timeout")
            static let unsupportedVersion = LocalizedString("error.sync.unsupported.version")
            static let invalidData = LocalizedString("error.sync.invalid.data")
            static let declined = LocalizedString("error.sync.declined")
            static let networkPolicy = LocalizedString("error.sync.network.policy")
            static let advertisingPolicy = LocalizedString("error.sync.advertising.policy")
            static let browserFailed = LocalizedString("error.sync.browser.failed")
            static let listenerFailed = LocalizedString("error.sync.listener.failed")
            static let sendFailed = LocalizedString("error.sync.send.failed")
            static let connectionFailed = LocalizedString("error.sync.connection.failed")
            static let advertisingFailed = LocalizedString("error.sync.advertising.failed")
            static let endpointNotFound = LocalizedString("error.sync.endpoint.not.found")
            static let unknownDevice = LocalizedString("error.sync.unknown.device")
        }
    }
    
    // MARK: - Location
    enum Location {
        static let capture = LocalizedString("location.capture")
        static let current = LocalizedString("location.current")
        static let unknown = LocalizedString("location.unknown")
        static let permissionRequest = LocalizedString("location.permission.request")
        static let permissionTitle = LocalizedString("location.permission.title")
        static let permissionMessage = LocalizedString("location.permission.message")
        static let settingsPrompt = LocalizedString("location.settings.prompt")
        static let settingsButton = LocalizedString("location.settings.button")
        
        enum Edit {
            static let searchPlaceholder = LocalizedString("location.edit.search.placeholder")
            static let recent = LocalizedString("location.edit.recent")
            static let clearField = LocalizedString("location.edit.clear.field")
            static let searching = LocalizedString("location.edit.searching")
            static let cancel = LocalizedString("location.edit.cancel")
            static let accept = LocalizedString("location.edit.accept")
            static let noResults = LocalizedString("location.edit.no.results")
        }
        
        enum Accuracy {
            static let excellent = LocalizedString("location.accuracy.excellent")
            static let good = LocalizedString("location.accuracy.good")
            static let fair = LocalizedString("location.accuracy.fair")
            static let poor = LocalizedString("location.accuracy.poor")
            static let invalid = LocalizedString("location.accuracy.invalid")
        }
        
        enum Error {
            static let servicesDisabled = LocalizedString("location.error.services.disabled")
            static let permissionDenied = LocalizedString("location.error.permission.denied")
            static let unknownStatus = LocalizedString("location.error.unknown.status")
            static let unavailable = LocalizedString("location.error.unavailable")
            
            enum Recovery {
                static let enableServices = LocalizedString("location.error.recovery.enable.services")
                static let grantPermission = LocalizedString("location.error.recovery.grant.permission")
                static let tryAgain = LocalizedString("location.error.recovery.try.again")
            }
        }
    }
}

// MARK: - SwiftUI Extensions

extension Text {
    /// Create a Text view from a LocalizedString
    init(_ localizedString: LocalizedString) {
        self.init(localizedString.localizedStringKey)
    }
}

extension LocalizedStringKey {
    /// Create a LocalizedStringKey from a LocalizedString
    init(_ localizedString: LocalizedString) {
        self.init(localizedString.key)
    }
}

// MARK: - String Interpolation Support

extension LocalizedString: ExpressibleByStringInterpolation {
    init(stringLiteral value: String) {
        self.init(value)
    }
    
    init(stringInterpolation: DefaultStringInterpolation) {
        self.init(String(stringInterpolation: stringInterpolation))
    }
}

// MARK: - CustomStringConvertible

extension LocalizedString: CustomStringConvertible {
    var description: String {
        string
    }
}
