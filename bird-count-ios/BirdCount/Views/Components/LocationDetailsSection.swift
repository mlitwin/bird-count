import SwiftUI
import MapKit
import Contacts

struct LocationDetailsSection: View {
    let record: ObservationRecord
    let onSearchStateChanged: ((Bool) -> Void)?
    @Environment(ObservationStore.self) private var observationStore
    @State private var isEditing = false
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchState: SearchState = .idle
    @State private var selectedLocation: ObservationLocation?
    @State private var tempLocation: ObservationLocation?
    @State private var cameraPosition: MapCameraPosition
    @State private var searchTimer: Timer?
    @State private var showSearchResults = false
    @State private var recentSearches: [String] = []
    @FocusState private var isSearchFocused: Bool
    
    private let recentSearchesKey = "LocationSearch.RecentSearches"
    private let maxRecentSearches = 5
    
    enum SearchState {
        case idle
        case searching
        case results([MKMapItem])
        case noResults
        case error(String)
    }
    
    init(record: ObservationRecord, onSearchStateChanged: ((Bool) -> Void)? = nil) {
        self.record = record
        self.onSearchStateChanged = onSearchStateChanged
        
        // Initialize camera position
        if let location = record.location, location.isValid {
            let coordinate = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: span)))
        } else {
            // Default to San Francisco if no location
            let coordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: span)))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Only show header when not actively searching
            if !showSearchResults {
                HStack {
                    Text("Location")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if !isEditing {
                        Button(action: { isEditing = true }) {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            if isEditing {
                VStack(spacing: 16) {
                    // Enhanced search bar - always visible when editing
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.body)
                            
                            TextField(Strings.Location.Edit.searchPlaceholder.string, text: $searchText)
                                .focused($isSearchFocused)
                                .textContentType(.location)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    performSearch()
                                }
                                .onChange(of: searchText) { _, newValue in
                                    handleSearchTextChange(newValue)
                                }
                                .onChange(of: isSearchFocused) { _, focused in
                                    if focused {
                                        showSearchResults = true
                                    } else if searchText.isEmpty {
                                        showSearchResults = false
                                        searchState = .idle
                                    }
                                }
                            
                            if !searchText.isEmpty {
                                Button(action: clearSearch) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel(Strings.Location.Edit.clearField.string)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.systemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    // Show search results when searching, or map and controls when not searching
                    if showSearchResults {
                        // Search results take up the available space
                        LocationSearchResultsPopup(
                            searchState: searchState,
                            recentSearches: recentSearches,
                            onLocationSelected: { location in
                                selectSearchResult(location)
                            },
                            onRecentSearchSelected: { searchTerm in
                                searchText = searchTerm
                                performSearch()
                            },
                            onDismiss: {
                                dismissSearchResults()
                            }
                        )
                        .frame(minHeight: 100, maxHeight: 400) // Give it generous space with minimum
                        
                        Spacer(minLength: 0)
                        
                    } else {
                        // Show map and controls when not searching
                        ScrollView {
                            VStack(spacing: 16) {
                                // Editable Map View
                                EditableLocationMapView(
                                    location: tempLocation ?? record.location,
                                    cameraPosition: $cameraPosition,
                                    onLocationSelected: { location in
                                        tempLocation = location
                                    }
                                )
                                .id("map-\(tempLocation?.latitude ?? 0)-\(tempLocation?.longitude ?? 0)-\(tempLocation?.name ?? "none")")
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                
                                // Edit controls
                                HStack {
                                    Button(Strings.Location.Edit.cancel.string) {
                                        cancelEdit()
                                    }
                                    .foregroundStyle(.red)
                                    
                                    Spacer()
                                    
                                    Button(Strings.Location.Edit.accept.string) {
                                        acceptEdit()
                                    }
                                    .foregroundStyle(.blue)
                                    .disabled(tempLocation == nil && record.location == nil)
                                }
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
                
            } else if !showSearchResults {
                // Read-only view - only show when not searching
                // Use the latest record from the observation store so the view reflects recent updates
                let currentRecord = observationStore.findRecord(by: record.id) ?? record
                if let location = currentRecord.location, location.isValid {
                    // Map View
                    LocationMapView(location: location)
                        .id("loc-\(location.latitude)-\(location.longitude)-\(Int(location.timestamp.timeIntervalSince1970))")
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    
                    // Location Details
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Name", value: location.displayName)
                        DetailRow(label: "Coordinates", value: location.formattedCoordinates())
                        DetailRow(label: "Accuracy", value: "\(location.accuracyDescription) (±\(Int(location.horizontalAccuracy)))m")
                        
                        if let altitude = location.altitude {
                            DetailRow(label: "Altitude", value: "\(Int(altitude))m")
                        }
                        
                        DetailRow(label: "Recorded", value: location.timestamp.formatted(date: .omitted, time: .standard))
                        
                        if let notes = location.notes, !notes.isEmpty {
                            DetailRow(label: "Notes", value: notes)
                        }
                    }
                } else {
                    Text("No location data available")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .onAppear {
            loadRecentSearches()
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside search field
            if isSearchFocused {
                isSearchFocused = false
            }
        }
    }
    
    private func handleSearchTextChange(_ newValue: String) {
        searchTimer?.invalidate()
        
        if newValue.isEmpty {
            searchState = .idle
            showSearchResults = isSearchFocused
            onSearchStateChanged?(isSearchFocused)
        } else {
            searchState = .searching
            showSearchResults = true
            onSearchStateChanged?(true)
            
            // Debounce search to avoid too many API calls
            searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                performSearch()
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchState = .idle
            return
        }
        
        searchState = .searching
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        
        // Improve search configuration for better results
        request.resultTypes = [.pointOfInterest, .address]
        
        // Use a broader region if available, otherwise default to worldwide
        if let currentLocation = record.location, currentLocation.isValid {
            let coordinate = CLLocationCoordinate2D(
                latitude: currentLocation.latitude,
                longitude: currentLocation.longitude
            )
            let span = MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0) // Broader search area
            request.region = MKCoordinateRegion(center: coordinate, span: span)
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Search error: \(error.localizedDescription)")
                    searchState = .error(error.localizedDescription)
                } else if let response = response {
                    print("Search found \(response.mapItems.count) results for '\(searchText)'")
                    let results = Array(response.mapItems.prefix(8)) // Show up to 8 results
                    if results.isEmpty {
                        searchState = .noResults
                    } else {
                        searchState = .results(results)
                    }
                } else {
                    print("Search returned no response for '\(searchText)'")
                    searchState = .noResults
                }
            }
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchState = .idle
        if !isSearchFocused {
            showSearchResults = false
            onSearchStateChanged?(false)
        }
    }
    
    private func dismissSearchResults() {
        showSearchResults = false
        isSearchFocused = false
        searchState = .idle
        onSearchStateChanged?(false)
    }
    
    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }
    
    private func saveRecentSearch(_ searchTerm: String) {
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty, !recentSearches.contains(trimmedTerm) else { return }
        
        recentSearches.insert(trimmedTerm, at: 0)
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }
    
    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        let location = ObservationLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            horizontalAccuracy: 10.0, // Assume good accuracy for search results
            timestamp: Date(),
            altitude: nil,
            verticalAccuracy: nil,
            name: item.name,
            notes: nil
        )
        
        // Update temp location first - this should trigger map update immediately
        tempLocation = location
        
        // Update camera position with animation to show the selected location
        withAnimation(.easeInOut(duration: 1.0)) {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            cameraPosition = .region(region)
        }
        
        // Save search term to recent searches
        if !searchText.isEmpty {
            saveRecentSearch(searchText)
        }
        
        // Clear search and hide results
        searchText = ""
        showSearchResults = false
        searchState = .idle
        isSearchFocused = false
        onSearchStateChanged?(false)
    }
    
    private func cancelEdit() {
        isEditing = false
        searchText = ""
        searchState = .idle
        showSearchResults = false
        tempLocation = nil
        searchTimer?.invalidate()
        searchTimer = nil
        isSearchFocused = false
        onSearchStateChanged?(false)
    }
    
    private func acceptEdit() {
        if let newLocation = tempLocation {
            observationStore.updateLocation(for: record.id, location: newLocation)
        }
        isEditing = false
        searchText = ""
        searchState = .idle
        showSearchResults = false
        tempLocation = nil
        searchTimer?.invalidate()
        searchTimer = nil
        isSearchFocused = false
        onSearchStateChanged?(false)
    }
}

// MARK: - Supporting Views

private struct LocationSearchResultsPopup: View {
    let searchState: LocationDetailsSection.SearchState
    let recentSearches: [String]
    let onLocationSelected: (MKMapItem) -> Void
    let onRecentSearchSelected: (String) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch searchState {
            case .idle:
                // Show recent searches when field is focused but empty
                if recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Search for places and addresses")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        Spacer()
                    }
                    .frame(minHeight: 80, idealHeight: 80)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(Strings.Location.Edit.recent.string)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        
                        ForEach(recentSearches, id: \.self) { searchTerm in
                            Button(action: {
                                onRecentSearchSelected(searchTerm)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 24, height: 24)
                                    
                                    Text(searchTerm)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if searchTerm != recentSearches.last {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .frame(minHeight: 40, maxHeight: min(CGFloat(recentSearches.count * 40 + 40), 200))
                }
                
            case .searching:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(Strings.Location.Edit.searching.string)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(minHeight: 60, idealHeight: 60)
                
            case .results(let items):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items, id: \.self) { item in
                            LocationSearchResultRow(
                                item: item,
                                onTap: {
                                    onLocationSelected(item)
                                }
                            )
                            
                            if item != items.last {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
                .frame(minHeight: 54, maxHeight: min(CGFloat(items.count * 54), 280)) // Limit height
                
            case .noResults:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text(Strings.Location.Edit.noResults.string)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Try a different search term")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(minHeight: 80, idealHeight: 80)
                
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Search Error")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(minHeight: 80, idealHeight: 80)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
            removal: .opacity.combined(with: .move(edge: .top))
        ))
    }
}

private struct LocationSearchResultRow: View {
    let item: MKMapItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Location icon
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Unknown Location")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    
                    if let address = item.placemark.formattedAddress {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LocationMapView: View {
    let location: ObservationLocation
    
    @State private var cameraPosition: MapCameraPosition
    
    init(location: ObservationLocation) {
        self.location = location
        
        // Initialize camera position centered on the location
        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        
        // Set zoom level based on accuracy - less accurate locations get zoomed out more
        let span: MKCoordinateSpan
        if location.horizontalAccuracy <= 50 {
            span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // Close zoom for accurate locations
        } else if location.horizontalAccuracy <= 200 {
            span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02) // Medium zoom
        } else {
            span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05) // Wider zoom for less accurate locations
        }
        
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: span)))
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            // Location pin
            Annotation("Observation Location", coordinate: coordinate) {
                LocationPin()
            }
            
            // Accuracy circle if accuracy is reasonable to show
            if location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 1000 {
                MapCircle(center: coordinate, radius: location.horizontalAccuracy)
                    .foregroundStyle(.blue.opacity(0.2))
                    .stroke(.blue.opacity(0.5), lineWidth: 1)
            }
        }
        .mapStyle(.standard)
        .mapControlVisibility(.hidden) // Hide default controls for cleaner look in details view
        .onChange(of: location) { _, _ in
            updateCameraPosition()
        }
    }
    
    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }
    
    private func updateCameraPosition() {
        // Compute appropriate span based on accuracy
        let span: MKCoordinateSpan
        if location.horizontalAccuracy <= 50 {
            span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        } else if location.horizontalAccuracy <= 200 {
            span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        } else {
            span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        }
        
        let region = MKCoordinateRegion(center: coordinate, span: span)
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
    }
}

private struct EditableLocationMapView: View {
    let location: ObservationLocation?
    @Binding var cameraPosition: MapCameraPosition
    let onLocationSelected: (ObservationLocation) -> Void
    
    var body: some View {
        MapReader { reader in
            Map(position: $cameraPosition) {
                // Current location pin if available
                if let location = location, location.isValid {
                    Annotation(location.displayName, coordinate: currentCoordinate) {
                        LocationPin()
                    }
                    .tag("current-location") // Add tag to help with updates
                    
                    // Accuracy circle if accuracy is reasonable to show
                    if location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 1000 {
                        MapCircle(center: currentCoordinate, radius: location.horizontalAccuracy)
                            .foregroundStyle(.blue.opacity(0.2))
                            .stroke(.blue.opacity(0.5), lineWidth: 1)
                    }
                }
            }
            .mapStyle(.standard)
            .mapControlVisibility(.visible) // Show controls for editing
            .onTapGesture { screenCoordinate in
                handleMapTap(at: screenCoordinate, with: reader)
            }
        }
        .onChange(of: location) { newLocation, _ in
            // Update binding when location changes
            if let newLocation = newLocation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: newLocation.latitude, longitude: newLocation.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }
    
    private var currentCoordinate: CLLocationCoordinate2D {
        if let location = location {
            return CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
        return CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // Default to SF
    }
    
    private func handleMapTap(at screenCoordinate: CGPoint, with reader: MapProxy) {
        // Convert screen coordinate to map coordinate
        if let mapCoordinate = reader.convert(screenCoordinate, from: .local) {
            let newLocation = ObservationLocation(
                latitude: mapCoordinate.latitude,
                longitude: mapCoordinate.longitude,
                horizontalAccuracy: 10.0, // Assume good accuracy for manual selection
                timestamp: Date(),
                altitude: nil,
                verticalAccuracy: nil,
                name: nil, // Will be nil initially, user can search to get named location
                notes: nil
            )
            
            onLocationSelected(newLocation)
        }
    }
}

private struct LocationPin: View {
    var body: some View {
        ZStack {
            // Pin shadow
            Circle()
                .fill(.black.opacity(0.3))
                .frame(width: 20, height: 20)
                .offset(x: 1, y: 1)
            
            // Pin background
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(.gray.opacity(0.3), lineWidth: 1)
                )
            
            // Pin center (bird icon color)
            Circle()
                .fill(.blue)
                .frame(width: 12, height: 12)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Extensions

private extension MKPlacemark {
    var formattedAddress: String? {
        guard let postalAddress = postalAddress else { return nil }
        return CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let mockLocation = ObservationLocation(
        latitude: 37.7749,
        longitude: -122.4194,
        horizontalAccuracy: 5.0,
        timestamp: Date().addingTimeInterval(-300),
        altitude: 100,
        verticalAccuracy: 3.0,
        name: "Golden Gate Park",
        notes: "Near the Japanese Tea Garden"
    )
    
    let mockRecord = ObservationRecord(
        id: UUID(),
        taxonId: "amecro",
        begin: Date().addingTimeInterval(-3600),
        end: Date(),
        count: 3,
        location: mockLocation
    )
    
    LocationDetailsSection(record: mockRecord)
        .environment(TaxonomyStore())
        .environment(ObservationStore())
        .padding()
}
#endif
