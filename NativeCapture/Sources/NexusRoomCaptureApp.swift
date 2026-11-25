import ARKit
import RoomPlan
import SwiftUI
import UniformTypeIdentifiers
import simd

@main
struct NexusRoomCaptureApp: App {
    var body: some Scene { WindowGroup { LaboratoryScreen() } }
}

private struct LaboratoryScreen: View {
    @State private var capture = CaptureController()
    @State private var operations = LabOperationsStore()
    @State private var savedLaboratories = SavedLaboratories()
    @State private var activeSavedLab: LabImport.Entry?
    @State private var mode: LabViewMode = .room
    @State private var paintRoom = true
    @AppStorage("labFullRoomWalls") private var fullRoomWalls = false
    @State private var poweredOff = Set<String>()
    @State private var selection: LabPlacement?
    @State private var choose3DPlacement = false
    @State private var preview3DPlacement: LabPlacement?
    @State private var equipmentPlacement: EquipmentPlacementDraft?
    @State private var sync3DToAR = false
    @State private var syncARAssemblyID: UUID?
    @State private var syncARAssemblies: [LabARAssembly] = []
    @State private var layout3DMessage: String?
    @State private var orbit3DHeading: Float = .pi / 4
    @State private var layout3DEdits = Lab3DPositions()
    @State private var loaded3DScope = ""
    @State private var cableReviews3D = 0
    @State private var hardwareSelection: HardwareItem?
    @State private var trackingMessage: String?
    @State private var sceneReload = 0
    @State private var walkthrough = ARWalkthrough()
    @State private var tracedLinkID: String?
    @State private var inspectedPort: LabTopology.Port?
    @State private var inspectedPDU: RackPowerInspection?
    @State private var negotiatingLink: String?
    @State private var pingSelection: PingSelection?
    @State private var packetHop = 0
    @State private var fairMode = false
    @State private var fairChallenge: LabFairChallenge?
    @State private var fairOutcome: LabFairOutcome?
    @State private var fairMessage: String?
    @State private var fairScores: [LabFairScore] = []
    @State private var assistant = LabAssistantModel()
    @State private var assistantOpen = false
    @State private var inspectionDestination: LabInspectionDestination?
    @State private var inspectionRevision = 0
    @State private var lockedDeviceID: String?
    @AppStorage("labShowTraffic") private var showTraffic = true
    @AppStorage("labShowRackAirflow") private var showRackAirflow = false
    @AppStorage("labPhysicalOcclusion") private var physicalOcclusion = true
    @AppStorage("labTierPhysicalOcclusion") private var tierPhysicalOcclusion = false
    @AppStorage("openedMacLaboratory") private var openedMacLaboratory = ""
    @AppStorage("openedSiteLaboratory") private var openedSiteLaboratory = ""
    @State private var macReceipt: LabImport.Entry?
    @State private var showOptions = false
    @State private var peerSession = NexusPeerSession()
    @State private var showCollaborationSheet = false
    @State private var showPingDiagnostics = false
    @State private var showLabCatalog = false
    @State private var afterCatalogDismissal: (() -> Void)?
    @State private var afterOptionsDismissal: (() -> Void)?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var cameraAccessDenied = false
    @State private var retryImport = false
    @State private var projectProgress: LocalizedStringKey?
    @State private var cameraRevision = 0
    @State private var orbitReset = 0
    @State private var previewProject: LabProject?
    @State private var appliedTemplate: LabProject?
    private enum ScanTemplate { case tier, home }
    @State private var templateOnNextScan: ScanTemplate?
    @State private var roomTopology: LabTopology?
    @State private var deviceSelection: LabTopology.Device?
    @State private var catalystInspection = Catalyst2960Inspection()
    @State private var opensDeviceCLI = false
    @State private var linkSelection: LabTopology.Link?
    @State private var showImporter = false
    @State private var travelMode: LabTravelMode?
    @State private var showHomeGuide = false
    @State private var placementSavedInSession = false
    @State private var restoringPlacement = false
    @State private var requestingPreviewCamera = false
    @State private var showCables = true
    @State private var cableFilter: LabCableFilter?
    @State private var showingViewerSearch = false
    @State private var previewSession: ARSession?
    @State private var pendingTierConfiguration: ARWorldTrackingConfiguration?
    @State private var sceneZoom = 0
    @State private var fullScreen3D = false
    @State private var showCameraGestures = false
    @State private var homeARScale: LabARScale = .fullSize
    @State private var tierARScale: LabARScale = .tenth
    @State private var importedARScale: LabARScale = .tenth
    @State private var showARScales = false
    @State private var pendingARScale: LabARScale?
    @State private var arFocus: LabARFocus = .all
    @State private var pendingARFocus: LabARFocus?
    @State private var showARFocusPicker = false
    @State private var showARContext = false
    @State private var focusedARScale: LabARScale = .fullSize
    @State private var activeAssembly: LabARAssembly?
    @State private var assemblySheet: AssemblySheet?
    @State private var assemblyToOpen: LabARAssembly?
    @State private var rackForMonitors: String?
    @State private var assemblyList: [LabARAssembly] = []
    @State private var assemblyName = ""
    @State private var assemblyNameError: String?
    @State private var assemblyToRename: LabARAssembly?
    @State private var renamedAssemblyName = ""
    @State private var showAssemblyRename = false
    @State private var assemblyToDelete: LabARAssembly?
    @State private var showAssemblyDeletion = false
    @State private var assemblySearch = ""
    @State private var projectPartSearch = ""
    @State private var selectedAssemblyItem: LabARAssembly.Item?
    @State private var assemblyPlacement: AssemblyPlacement?
    @State private var assemblyCableRequest: AssemblyCableRequest?
    @State private var assemblyEdit: AssemblyEdit?
    @State private var waypointEdit: WaypointEdit?
    @State private var assemblyRackID: String?
    @State private var assemblyRackTarget: RackMount.Target?
    @State private var choosingAssemblyPorts = false
    @State private var assemblyPortRoute: AssemblyPortRoute?
    @State private var assemblyPortDestination: LabTopology.Port?
    @State private var assemblyCableConfirmation: String?
    @State private var assemblyPortDevice: String?
    @State private var nextAssemblySheet: AssemblySheet?
    @State private var powerOutletRack: LabARAssembly.Item?
    @State private var directPowerOutlets: [LabARAssembly.Item: LabRackPower.Outlet] = [:]
    @State private var powerOutletHint: String?
    @State private var powerOutletConfirmation: String?

    private enum AssemblySheet: String, Identifiable {
        case locations, catalog, equipment, network, rack, rackMonitors, rackDevices, port, portSettings
        var id: Self { self }
    }

    private enum AssemblyPlacement {
        case item(LabARAssembly.Item, LabARAssembly.CableLevel), all(LabARAssembly.CableLevel), origin
        case waypoint(String, Int)
    }

    private struct EquipmentPlacementDraft {
        let device: LabTopology.Device
        let original: LabProject
        let surface: LabEquipmentSurface
        var choice: EquipmentPlacementChoice?
        var hint: String?
    }

    private struct EquipmentPlacementChoice {
        let project: LabProject
        let assembly: LabARAssembly?
        let outline: LabPlacement
    }

    private enum AssemblyCableRequest {
        case item(LabARAssembly.Item), all, change(LabARAssembly.Item)
    }

    private struct AssemblyEdit {
        let id = UUID()
        let original: LabARAssembly.Piece
        var piece: LabARAssembly.Piece
        let adjustments: [LabARAssembly.Adjustment]
        var initialMode = LabARAssembly.Adjustment.move
    }

    private struct WaypointEdit {
        let id = UUID()
        let link: String
        let index: Int
        var value: SIMD2<Float>
    }

    private struct PingSelection {
        let scope: String
        let source: String
        let destination: String
    }

    private struct RackPowerInspection: Identifiable {
        let rack: LabARAssembly.Item
        var circuit: Int? = nil
        var outlet: Int? = nil
        var id: LabARAssembly.Item { rack }
    }
    private struct CatalystInspectionRequest: Equatable {
        let deviceID: String?
        let scope: String
        let attempt: Int
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var laboratoryNavigation: some View {
        NavigationStack {
            Group {
                if let view = capture.captureView { scanner(view: view) }
                else if capture.phase == .restoring || capture.phase == .permission || (requestingPreviewCamera && mode != .ar) {
                    ProgressView(capture.phase == .restoring ? "Abriendo laboratorio…" : "Preparando cámara…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let project = previewProject {
                    workspace(room: project.room, layout: project.layout, topology: currentTopology)
                } else if let project = appliedTemplate {
                    workspace(room: project.room, layout: project.layout, topology: operations.configured(project.topology))
                } else if let room = capture.room, let layout = capture.layout {
                    workspace(room: room, layout: layout, topology: roomTopology)
                } else { startScreen }
            }
            .disabled(projectProgress != nil)
            .allowsHitTesting(projectProgress == nil)
            .overlay {
                Group {
                    if let projectProgress {
                        ProgressView(projectProgress)
                            .padding(16)
                            .modifier(ViewerSurface(radius: 16, material: .thick))
                            .padding(16)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: projectProgress != nil)
            }
            .overlay(alignment: .top) {
                if let macReceipt, projectProgress == nil, mode == .room, !capture.isBusy, !fullScreen3D {
                    receivedLabBanner(macReceipt)
                        .padding(12)
                }
            }
            .navigationTitle(activeAssembly?.name ?? "Nexus AR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(fullScreen3D ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(fullScreen3D)
            .toolbar {
                if !capture.isBusy {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showCollaborationSheet = true
                        } label: {
                            Label(
                                "Sesión colaborativa",
                                systemImage: peerSession.status.isConnected ? "person.2.wave.2.fill" : "person.2.wave.2"
                            )
                        }
                        .tint(peerSession.status.isConnected ? .green : .accentColor)
                    }
                }
                if !capture.isBusy && canSearchViewer {
                    ToolbarItem(placement: .topBarTrailing) { viewerSearchButton }
                }
                if mode == .ar && !capture.isBusy {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Volver a 3D", systemImage: "chevron.left") { mode = .room }
                    }
                    if activeAssembly == nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Más opciones", systemImage: "ellipsis.circle") { showOptions = true }
                        }
                    }
                } else if !capture.isBusy {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { beginCapture() } label: { Label("Escanear cuarto", systemImage: "camera") }
                            .disabled(!capture.isSupported || projectProgress != nil)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showOptions = true } label: {
                            Label("Más opciones", systemImage: "ellipsis.circle")
                        }
                        .disabled(projectProgress != nil)
                    }
                    if previewProject?.layout.facility != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showARFocusPicker = true } label: {
                                Label("Colocar un equipo en AR", systemImage: "cube.transparent")
                            }
                            .disabled(projectProgress != nil)
                        }
                    }
                    if mode == .room, currentLayout != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Montajes AR", systemImage: "square.3.layers.3d", action: showAssemblyLocations)
                                .disabled(projectProgress != nil)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        laboratoryNavigation
        .tint(.accentColor)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // CoreDevice writes to the sandbox outside this process. Check only while the scene is active.
            while !Task.isCancelled {
                if macReceipt == nil {
                    let acknowledged = Set(UserDefaults.standard.stringArray(forKey: "acknowledgedMacLabs") ?? [])
                    let hidden = savedLaboratories.hiddenKeys.compactMap {
                        $0.hasPrefix("received/") ? String($0.dropFirst("received/".count)) : nil
                    }
                    let latest = try? await Self.nextMacReceipt(excluding: acknowledged.union(hidden))
                    guard !Task.isCancelled else { return }
                    macReceipt = latest
                }
                do { try await Task.sleep(for: .seconds(3)) }
                catch { return }
            }
        }
        .task {
            setupCollaborationHandlers()
            let previous = UserDefaults.standard.string(forKey: "activeLaboratory")
            await capture.selectSite(operations.siteStorageID)
            switch previous {
            case "demo": openDataCenter()
            case "home": openHomeLab()
            case LabDemo.vlanProfile: openVLANDemo()
            case "imported":
                restoreInventory(site: operations.siteStorageID, filename: openedSiteLaboratory)
            case "received":
                restoreInventory(site: nil, filename: openedMacLaboratory)
            default: break
            }
        }
        .onChange(of: capture.phase) { _, phase in
            switch phase {
            case .saved:
                let freshCapture = capture.arSession != nil
                if freshCapture {
                    walkthrough = ARWalkthrough()
                    arFocus = .all
                    previewSession?.pause()
                    previewSession = nil
                    previewProject = nil
                    activeSavedLab = nil
                    appliedTemplate = nil
                    sceneZoom = 0
                }
                if let room = capture.room, let layout = capture.layout {
                    roomTopology = try? LabDemo.roomLab(room: room, layout: layout)
                }
                mode = previewProject == nil && freshCapture ? .ar : .room
                paintRoom = false
                tracedLinkID = nil
                poweredOff.removeAll()
                selection = nil
                trackingMessage = nil
                if freshCapture {
                    UserDefaults.standard.set("scan", forKey: "activeLaboratory")
                    if let templateOnNextScan { applyTemplate(openAR: true, home: templateOnNextScan == .home) }
                    templateOnNextScan = nil
                } else {
                    let active = UserDefaults.standard.string(forKey: "activeLaboratory")
                    if active == "scan-tier" || active == "scan-home" { applyTemplate(openAR: false, home: active == "scan-home") }
                }
            case .ready:
                if capture.arSession == nil { mode = .room }
            case .failed(let message):
                errorMessage = message
                showError = true
                if capture.arSession == nil { mode = .room }
            default: break
            }
        }
        .onChange(of: operations.siteStorageID) { _, site in
            previewSession?.pause()
            previewSession = nil
            appliedTemplate = nil
            roomTopology = nil
            mode = .room
            cameraRevision += 1
            walkthrough = ARWalkthrough()
            Task {
                await capture.selectSite(site)
                guard operations.siteStorageID == site else { return }
                let active = UserDefaults.standard.string(forKey: "activeLaboratory")
                if active == "imported" {
                    restoreInventory(site: site, filename: "")
                } else if capture.room == nil && active == "scan-home" {
                    openHomeLab()
                } else if capture.room == nil && active == "scan-tier" {
                    openDataCenter()
                }
            }
        }
        .onChange(of: savedLaboratories.hiddenKeys) { _, hidden in
            if let macReceipt, hidden.contains(macReceipt.libraryKey) { self.macReceipt = nil }
            if let activeSavedLab, hidden.contains(activeSavedLab.libraryKey) { returnToRoom() }
        }
        .onChange(of: currentLayout?.placements) { _, _ in
            lockedDeviceID = nil
            inspectionDestination = nil
            preview3DPlacement = nil
        }
        .task(id: catalystInspectionRequest) {
            await catalystInspection.load(for: catalystInspectionRequest.deviceID)
        }
        .task(id: layout3DScope) {
            if pingSelection?.scope != layout3DScope { pingSelection = nil }
            cableFilter = nil
            preview3DPlacement = nil
            equipmentPlacement = nil
            layout3DMessage = nil
            layout3DEdits = UserDefaults.standard.data(forKey: layout3DScope)
                .flatMap { try? JSONDecoder().decode(Lab3DPositions.self, from: $0) } ?? Lab3DPositions()
            loaded3DScope = layout3DScope
            if mode == .room { restoreSharedInventory() }
        }
        .onChange(of: currentLayout != nil) { _, available in
            if !available { fullScreen3D = false }
        }
        .onChange(of: lockedDeviceID) { _, id in
            if inspectionDestination?.deviceID != id { inspectionDestination = nil }
        }
        .onChange(of: cameraRevision) { _, _ in
            lockedDeviceID = nil
            inspectionDestination = nil
            cancelPowerOutlet()
            directPowerOutlets.removeAll()
            powerOutletConfirmation = nil
            equipmentPlacement = nil
        }
        .onChange(of: mode) { _, value in
            lockedDeviceID = nil
            inspectionDestination = nil
            if value == .ar {
                fullScreen3D = false
                clearAssemblyPorts()
            }
            guard value != .ar || canUseAR else {
                mode = .room
                return
            }
            preview3DPlacement = nil
            equipmentPlacement = nil
            trackingMessage = nil
            if value == .room {
                cancelPowerOutlet()
                directPowerOutlets.removeAll()
                powerOutletConfirmation = nil
                let releasesTierCamera = currentLayout?.facility != nil
                if activeAssembly != nil { tracedLinkID = nil }
                arFocus = .all
                activeAssembly = nil
                selectedAssemblyItem = nil
                assemblyPlacement = nil
                assemblyCableRequest = nil
                assemblyEdit = nil
                assemblyCableConfirmation = nil
                waypointEdit = nil
                assemblyRackID = nil
                clearAssemblyPorts()
                pendingTierConfiguration = nil
                capture.pauseAR(); previewSession?.pause()
                if releasesTierCamera { previewSession = nil }
            }
        }
        .onChange(of: tierPhysicalOcclusion) { _, _ in updateTierCamera() }
        .onChange(of: arScale) { _, _ in
            if activeAssembly == nil {
                cancelPowerOutlet()
                directPowerOutlets.removeAll()
                powerOutletConfirmation = nil
            }
            updateTierCamera()
        }
        .task(id: assemblyPortDestination) {
            if let destination = assemblyPortDestination { await connectAssemblyCable(to: destination) }
        }
        .task(id: negotiatingLink) {
            guard let link = negotiatingLink else { return }
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            if negotiatingLink == link { negotiatingLink = nil }
        }
        .onChange(of: walkthrough.ready) { _, ready in
            if !ready { waypointEdit = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if mode == .ar {
                    walkthrough.pose = nil
                    walkthrough.target = nil
                    walkthrough.phase = .interrupted
                }
                capture.cancel()
                capture.pauseAR()
                previewSession?.pause()
            } else if phase == .active {
                if capture.room == nil && previewProject == nil && activeAssembly == nil {
                    Task { await capture.restoreLatest() }
                }
                if mode == .ar {
                    if previewProject == nil && activeAssembly == nil { resumeRoomAR() }
                    else if pendingTierConfiguration == nil, let configuration = previewSession?.configuration {
                        previewSession?.run(configuration)
                    }
                }
            }
        }
        .sheet(item: $selection, onDismiss: {
            if rackForMonitors != nil { showAssemblyLocations() }
        }) { item in
            NavigationStack {
                PlacementInspector(placement: item, topology: currentTopology, locateTitle: locateTitle,
                                   onLocate: locateInScene, console: deviceConsole,
                                   onMonitors: item.kind == .rack && canUseAR ? {
                                       rackForMonitors = item.id
                                       selection = nil
                                   } : nil,
                                   rackTools: activeAssembly == nil && item.kind == .rack ? AnyView(roomRackTools(item)) : nil,
                                   moveDevice: rackDeviceMove,
                                   onAdjust: mode == .room ? {
                                       begin3DPlacement(item)
                                       selection = nil
                                   } : nil,
                                   poweredOff: $poweredOff, effectivePowerOff: effectivePoweredOff, devicePowerCut: powerCut(for:))
                    .toolbar { DismissButton() }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $hardwareSelection) { item in
            NavigationStack { HardwareDetail(item: item).toolbar { DismissButton() } }
        }
        .sheet(isPresented: $showARScales, onDismiss: applyARScale) {
            if let previewSpace {
                ARScalePicker(selection: arScale, space: previewSpace) { pendingARScale = $0 }
            }
        }
        .sheet(isPresented: $showARFocusPicker, onDismiss: applyARFocus) {
            if let project = previewProject { arFocusPicker(for: project) }
        }
        .sheet(item: $assemblySheet, onDismiss: finishAssemblySheet) { sheet in
            NavigationStack {
                switch sheet {
                case .locations: assemblyLocations
                case .catalog: equipmentCatalog(showDone: true)
                case .equipment: equipmentEditor
                case .network: assemblyNetwork
                case .rack: assemblyRackSheet
                case .rackMonitors: assemblyRackMonitors
                case .rackDevices: assemblyRackDevices
                case .port: assemblyPortSheet
                case .portSettings: assemblyPortSettings
                }
            }
        }
        .sheet(item: $deviceSelection, onDismiss: { opensDeviceCLI = false }) { device in
            if let baseTopology {
                LabDeviceSheet(device: device, base: baseTopology, poweredOff: effectivePoweredOff,
                               locateTitle: locateTitle, onLocate: locateInScene, opensTerminal: opensDeviceCLI,
                               moveDevice: rackDeviceMove(device), catalystInspection: catalystInspection,
                               liveBase: { self.baseTopology }, save: saveConsoleTopology,
                               powerCut: powerCut(for: device), pending: pendingSignalDevices)
            }
        }
        .sheet(item: $linkSelection) { link in
            if let topology = currentTopology {
                NavigationStack {
                    LinkInspector(link: link, topology: topology, locateTitle: locateTitle, onLocate: locateInScene,
                                  poweredOff: effectivePoweredOff, pending: pendingSignalDevices, negotiatingLink: negotiatingLink)
                        .toolbar { DismissButton() }
                }
            }
        }
        .sheet(item: $inspectedPort) { port in
            if let topology = currentTopology {
                NavigationStack {
                    PortInspector(port: port, topology: topology, poweredOff: effectivePoweredOff,
                                  pending: pendingSignalDevices, negotiatingLink: negotiatingLink,
                                  locateTitle: locateTitle, onLocate: locateInScene)
                        .toolbar { DismissButton() }
                }
            }
        }
        .sheet(item: $inspectedPDU) { inspection in
            if let layout = currentLayout, let topology = currentTopology {
                NavigationStack {
                    RackPDUInspector(rack: inspection.rack, layout: layout, topology: topology,
                                     assembly: powerInspectionAssembly, poweredOff: effectivePoweredOff,
                                     selectedCircuit: inspection.circuit, selectedOutlet: inspection.outlet)
                        .toolbar { DismissButton() }
                }
            }
        }
        .sheet(isPresented: $showHomeGuide) {
            NavigationStack { homeGuide.toolbar { DismissButton() } }
        }
        .sheet(isPresented: $showingViewerSearch) {
            viewerSearchSheet
        }
        .fullScreenCover(item: $travelMode) { travel in
            if let room = previewProject?.room ?? appliedTemplate?.room ?? capture.room, let layout = visible3DLayout {
                LabTravelView(mode: travel, room: room, layout: layout, topology: baseTopology,
                              showCables: $showCables, cableFilter: $cableFilter, poweredOff: effectivePoweredOff, showTraffic: trafficBinding,
                              liveBase: { self.baseTopology }, save: saveConsoleTopology)
            }
        }
        .sheet(isPresented: $showOptions, onDismiss: runOptionsAction) {
            NavigationStack { optionsList }
        }
        .sheet(isPresented: $showCollaborationSheet) {
            CollaborativeSessionView(session: peerSession) {
                if let topology = currentTopology {
                    peerSession.sendReliable(.syncTopology(topology, scale: arScale.factor))
                }
            }
        }
        .sheet(isPresented: $showPingDiagnostics) {
            if let topology = currentTopology {
                NavigationStack { pingDiagnostics(topology).toolbar { DismissButton() } }
            }
        }
        .sheet(isPresented: $showLabCatalog, onDismiss: {
            let action = afterCatalogDismissal
            afterCatalogDismissal = nil
            action?()
        }) {
            LabCatalogView(onOpen: openPublication)
        }
        .sheet(isPresented: $choose3DPlacement) {
            NavigationStack {
                List(visible3DLayout?.placements ?? []) { placement in
                    Button {
                        begin3DPlacement(placement)
                        choose3DPlacement = false
                    } label: {
                        Label(placement.title, systemImage: placement.kind == .rack ? "server.rack" : "desktopcomputer")
                    }
                }
                .navigationTitle("Organizar en 3D")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { DismissButton() }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, urls.isEmpty { return }
            let site = operations.siteStorageID
            // An explicit result type keeps the type checker fast on slower build machines.
            loadProject("Importando topología…", retryImport: true, build: { () throws -> (LabProject, LabImport.Entry) in
                guard let url = try result.get().first else { throw CocoaError(.fileNoSuchFile) }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 8 * 1024 * 1024 else { throw LabLayoutError.invalid("Archivo vacío o mayor de 8 MB.") }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let project = try LabImport.project(from: data)
                if project.editableID != nil { return try LabImport.createEditableCopy(of: project, site: site) }
                let source = try JSONDecoder().decode(LabTopology.self, from: data)
                let saved = try LabImport.save(source, site: site)
                return (project, LabImport.Entry(url: saved, name: project.topology.name, date: .now))
            }) { result in
                showInventory(result.0, entry: result.1)
            }
        }
        .alert(cameraAccessDenied ? "Nexus AR necesita acceso a la cámara" : "No se pudo completar la acción", isPresented: $showError) {
            if cameraAccessDenied {
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if retryImport {
                Button("Elegir otro archivo") { showImporter = true }
            } else if capture.isSupported {
                Button("Volver a escanear") { beginCapture() }
            }
            Button("Cerrar", role: .cancel) {}
        } message: { Text(errorMessage) }
        .onChange(of: showError) { _, presented in
            if !presented {
                retryImport = false
                cameraAccessDenied = false
            }
        }
        .environment(operations)
        .environment(savedLaboratories)
    }

    private func receivedLabBanner(_ entry: LabImport.Entry) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Label("Laboratorio recibido", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(savedLaboratories.name(entry)).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Button("Abrir") { openInventory(entry) }
                    .buttonStyle(.borderedProminent)
                Button {
                    acknowledgeMacReceipt(entry)
                } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar aviso")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: 480)
        .modifier(ViewerSurface(radius: 18, material: .thick))
        .onAppear { UIAccessibility.post(notification: .announcement, argument: "Laboratorio recibido: \(savedLaboratories.name(entry))") }
    }

    @concurrent private static func nextMacReceipt(excluding filenames: Set<String>) async throws -> LabImport.Entry? {
        try LabImport.received(excluding: filenames).first
    }

    private func acknowledgeMacReceipt(_ entry: LabImport.Entry) {
        let key = "acknowledgedMacLabs"
        var acknowledged = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if acknowledged.insert(entry.url.lastPathComponent).inserted {
            UserDefaults.standard.set(Array(acknowledged), forKey: key)
        }
        if macReceipt?.id == entry.id { macReceipt = nil }
    }

    private var optionsList: some View {
        List {
            Section("Sesión Colaborativa Multi-iPhone") {
                Button {
                    finishOptions { showCollaborationSheet = true }
                } label: {
                    Label(
                        peerSession.status.isConnected ? "Sesión colaborativa activa (\(peerSession.connectedPeerName ?? ""))" : "Conectar 2 iPhones (Sesión AR)",
                        systemImage: "person.2.wave.2"
                    )
                }
            }
            laboratoryOptions
            if workspaceProject != nil {
                Button("Editar laboratorio", systemImage: "plus.rectangle.on.rectangle") {
                    finishOptions { assemblySheet = .equipment }
                }
            }
            if let topology = currentTopology { networkOptions(topology) }
            templateOptions
            roomOptions
            fileOptions
            equipmentOptions
            if currentLayout != nil { viewerOptions }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Más opciones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { DismissButton() }
    }

    private var templateOptions: some View {
        Section("Plantillas de laboratorio") {
            Button(LabDemo.vlanName, systemImage: "point.3.connected.trianglepath.dotted") { finishOptions(openVLANDemo) }
            Button("HomeLab Proxmox", systemImage: "server.rack") { finishOptions(openHomeLab) }
            Button("Plantilla Tier IV", systemImage: "building.2") { finishOptions(openDataCenter) }
            if isHomeLab {
                NavigationLink { homeGuide } label: { Label("Guía de montaje", systemImage: "list.number") }
            }
            NavigationLink {
                DataCenterInfo(topology: currentLayout?.facility == nil ? nil : currentTopology)
            } label: {
                Label(currentLayout?.facility == nil ? "Criterios Tier IV" : "Infraestructura y pruebas", systemImage: "info.circle")
            }
        }
    }

    private var homeGuide: some View {
        HomeLabGuide { id in
            showCables = true
            tracedLinkID = id
            showHomeGuide = false
            showOptions = false
        }
    }

    private var equipmentOptions: some View {
        Section("Equipos") {
            NavigationLink { catalogList } label: {
                Label("Equipos disponibles", systemImage: "list.bullet.rectangle")
            }
            if let currentLayout, !currentLayout.placements.isEmpty {
                NavigationLink { sceneEquipmentList } label: {
                    Label("Elementos de la escena", systemImage: "cube")
                }
            }
        }
    }

    private func networkOptions(_ topology: LabTopology) -> some View {
        Section("Red y conexiones") {
            NavigationLink {
                pingDiagnostics(topology)
            } label: {
                Label("Diagnóstico de conectividad", systemImage: "point.3.connected.trianglepath.dotted")
            }
            NavigationLink {
                TopologyInspector(topology: topology, room: previewProject?.room ?? capture.room, layout: currentLayout,
                                  locateTitle: locateTitle, onLocate: locateInScene, console: deviceConsole,
                                  poweredOff: effectivePoweredOff, pending: pendingSignalDevices)
            } label: {
                Label("Ver equipos y conexiones", systemImage: "point.3.connected.trianglepath.dotted")
            }
            if let baseTopology, topology.operationsProfile != nil {
                NavigationLink {
                    LabMonitorInventory(base: baseTopology, poweredOff: poweredOff,
                                        locateTitle: locateTitle, onLocate: locateInScene)
                } label: {
                    Label("Monitores de servidores", systemImage: "display")
                }
            }
            Toggle("Mostrar cables", systemImage: "cable.connector", isOn: $showCables)
            if topology.devices.contains(where: { $0.visualModelID == RackMount.Equipment.fans.rawValue }) {
                Toggle("Flujo de aire simulado", systemImage: "fan", isOn: $showRackAirflow)
                if showRackAirflow {
                    Text("Azul para la entrada de aire. Naranja para la zona de salida.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if simulationEnabled {
                Toggle("Flujo simulado", systemImage: "waveform.path", isOn: $showTraffic)
            }
        }
    }

    private func pingDiagnostics(_ topology: LabTopology) -> some View {
        PingDiagnosticView(topology: topology, layout: visible3DLayout, poweredOff: effectivePoweredOff,
                           onShowInScene: showPingInScene)
    }

    @ViewBuilder
    private var viewerOptions: some View {
        Section("Vista y recorrido") {
            Button("Recorrido 3D", systemImage: "figure.walk") { finishOptions { openTravel(.walk) } }
            Button("Modo VR", systemImage: "eyeglasses") { finishOptions { openTravel(.vr) } }
            Button("Restablecer vista 3D", systemImage: "arrow.counterclockwise") { finishOptions { resetOrbit() } }
            if mode == .room {
                Toggle("Paredes exteriores completas", systemImage: "square.3.layers.3d", isOn: $fullRoomWalls)
                Button("Montajes AR", systemImage: "square.3.layers.3d") { finishOptions(showAssemblyLocations) }
            }
            if previewProject == nil, appliedTemplate != nil {
                Button("Configurar maqueta AR", systemImage: "ruler") {
                    finishOptions { if isHomeLab { openHomeLab() } else { openDataCenter() } }
                }
            }
        }
        if mode == .ar {
            Section("Realidad aumentada") {
                if placementAnchorName != nil {
                    Button("Recalibrar punto de referencia", systemImage: "move.3d") {
                        finishOptions { openPreviewAR(reposition: true) }
                    }
                }
                if capture.supportsMesh {
                    Toggle("Oclusión con espacio real", systemImage: "square.on.square.intersection.dashed",
                           isOn: isTierPreview ? $tierPhysicalOcclusion : $physicalOcclusion)
                }
                Toggle("Reconstruir paredes y suelo", systemImage: "square.3.layers.3d", isOn: $paintRoom)
            }
        }
    }

    private var laboratoryOptions: some View {
        Section("Laboratorios") {
            Button("Catálogo UNSM", systemImage: "qrcode.viewfinder") {
                finishOptions { mode = .room; showLabCatalog = true }
            }
            NavigationLink {
                LabInventoryLibrary { entry in finishOptions { openInventory(entry) } }
            } label: {
                Label("Laboratorios guardados", systemImage: "archivebox")
            }
            if let entry = activeSavedLab {
                Button(simulationEnabled ? "Pausar simulación" : "Activar simulación",
                       systemImage: simulationEnabled ? "pause.circle" : "play.circle") {
                    do { try savedLaboratories.change(entry) { $0.enabled.toggle() } }
                    catch {
                        let message = error.localizedDescription
                        finishOptions { errorMessage = message; showError = true }
                    }
                }
            }
        }
    }

    private var fileOptions: some View {
        Section("Archivos") {
            Button("Importar topología exportada", systemImage: "square.and.arrow.down") {
                finishOptions { showImporter = true }
            }
            if let url = capture.savedURL { ShareLink("Compartir archivo del escaneo", item: url) }
        }
    }

    private var roomOptions: some View {
        Section("Mi cuarto") {
            if capture.isSupported {
                Button("Escanear cuarto", systemImage: "camera") { finishOptions { beginCapture() } }
            }
            NavigationLink {
                Form { LabPlanSections(base: baseTopology) }
                    .navigationTitle("Sitios")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Sitios", systemImage: "building.2")
            }
            if capture.room != nil {
                if previewProject == nil && capture.hasSavedWorldMap {
                    Button("Volver a alinear el cuarto", systemImage: "location.circle") {
                        finishOptions { resumeRoomAR(realign: true) }
                    }
                }
                Button(isHomeLab ? "Ajustar HomeLab al escaneo" : "Aplicar plantilla al cuarto", systemImage: "square.dashed.inset.filled") {
                    finishOptions { applyTemplate(openAR: mode == .ar, home: isHomeLab) }
                }
                if previewProject != nil || appliedTemplate != nil {
                    Button("Volver a mi cuarto", systemImage: "house") {
                        finishOptions(returnToRoom)
                    }
                }
            }
        }
    }

    private func finishOptions(_ action: @escaping () -> Void) {
        afterOptionsDismissal = action
        showOptions = false
    }

    private func runOptionsAction() {
        let action = afterOptionsDismissal
        afterOptionsDismissal = nil
        action?()
    }

    private var catalogList: some View {
        List {
            ForEach(HardwareItem.Family.allCases, id: \.self) { family in
                if let items = HardwareCatalog.byFamily[family] {
                    Section(family.rawValue) {
                        ForEach(items) { item in
                            NavigationLink { HardwareDetail(item: item) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                    Text(item.category).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Equipos disponibles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sceneEquipmentList: some View {
        let placements = currentLayout?.placements ?? []
        let topology = currentTopology
        return List {
            ForEach([LabPlacement.Kind.rack, .workstation, .floor], id: \.self) { kind in
                let group = placements.filter { $0.kind == kind }
                let title = switch kind { case .rack: "Racks"; case .workstation: "Puestos de trabajo"; case .floor: "Equipos en el piso" }
                let symbol = switch kind { case .rack: "server.rack"; case .workstation: "desktopcomputer"; case .floor: "arrow.down.to.line" }
                if !group.isEmpty {
                    Section(title) {
                        ForEach(group) { placement in
                            NavigationLink {
                                PlacementInspector(placement: placement, topology: topology, locateTitle: locateTitle,
                                                   onLocate: locateInScene,
                                                   rackTools: kind == .rack && mode == .room ? AnyView(roomRackTools(placement)) : nil,
                                                   moveDevice: rackDeviceMove,
                                                   poweredOff: $poweredOff, effectivePowerOff: effectivePoweredOff, devicePowerCut: powerCut(for:))
                            } label: {
                                Label(placement.title, systemImage: symbol)
                            }
                        }
                    }
                }
            }
            if currentLayout?.facility != nil {
                Section("Infraestructura Tier IV") {
                    ForEach(HardwareCatalog.infrastructure) { item in
                        NavigationLink(item.name) { HardwareDetail(item: item) }
                    }
                }
            }
        }
        .navigationTitle("Elementos de la escena")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func beginCapture() {
        fullScreen3D = false
        templateOnNextScan = isHomeLab ? .home : currentLayout?.facility != nil ? .tier : nil
        selection = nil
        hardwareSelection = nil
        previewSession?.pause()
        Task { await capture.start() }
    }

    private var isHomeLab: Bool { (previewProject ?? appliedTemplate)?.isHomeLab == true }
    private var isTierPreview: Bool { currentLayout?.facility != nil && (previewProject != nil || activeAssembly != nil) }
    private var isTierMiniature: Bool { isTierPreview && activeAssembly == nil && arScale.rawValue >= LabARScale.tenth.rawValue }
    private var isManualHome: Bool { isHomeLab && previewProject != nil }
    private var hasScalablePreview: Bool {
        isManualHome || previewProject?.layout.facility != nil || previewProject?.layout.importedRoom == true
    }
    private var arScale: LabARScale {
        if usesCapturedARSession { return .fullSize }
        if arFocus != .all { return focusedARScale }
        if isManualHome { return homeARScale }
        if previewProject?.layout.facility != nil { return tierARScale }
        if previewProject?.layout.importedRoom == true { return importedARScale }
        return previewProject == nil ? .fullSize : .tenth
    }
    private var usesCapturedARSession: Bool {
        guard let captured = capture.arSession else { return false }
        return previewSession === captured
    }
    private var isHomeFloorPlacement: Bool { isManualHome && arScale == .fullSize }
    private var previewUsesFloor: Bool { arScale == .fullSize && arFocus == .all && activeAssembly == nil }

    private func arFootprint(in layout: LabLayout, topology: LabTopology?) -> LabPlacementFootprint? {
        guard mode == .ar else { return nil }
        if let assembly = activeAssembly {
            guard let assemblyPlacement else { return nil }
            switch assemblyPlacement {
            case .all:
                return .init(points: layout.floorPolygon.map { $0 - layout.floorCenter })
            case .origin, .waypoint:
                return .init(size: SIMD3(0.14, 0, 0.14))
            case .item(let item, _):
                guard let size = LabARAssembly.size(of: item, in: layout, topology: topology) else { return nil }
                let yaw = assembly.piece(item)?.yaw
                if case .support(let id) = item, layout.placements.contains(where: { $0.id == id && $0.kind == .rack }) {
                    return .init(rack: size, yaw: yaw)
                }
                var footprint = LabPlacementFootprint(size: size, yaw: yaw)
                if case .support(let id) = item {
                    footprint.requiresFloor = layout.placements.contains { $0.id == id && $0.kind == .floor }
                }
                return footprint
            }
        }
        guard previewProject != nil else { return nil }
        if let size = arFocus.size(in: layout, topology: topology) {
            if arScale == .fullSize, case .placement(let id) = arFocus,
               let rack = layout.placements.first(where: { $0.id == id && $0.kind == .rack }) {
                return .init(rack: size, yaw: rack.yaw)
            }
            let yaw: Float
            if case .fixture(let id) = arFocus, let facility = layout.facility,
               let fixture = facility.fixtures.first(where: { $0.id == id }) {
                yaw = facility.yaw + fixture.yaw
            } else {
                let placement = arFocus.placementID(in: topology)
                yaw = layout.placements.first { $0.id == placement }?.yaw ?? 0
            }
            let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
            let points = LabPlacementFootprint(size: size).points.map { point in
                let rotated = rotation.act(SIMD3(point.x, 0, point.y)) * arScale.factor
                return SIMD2(rotated.x, rotated.z)
            }
            return .init(points: points)
        }
        return .init(points: layout.floorPolygon.map { $0 * arScale.factor })
    }
    private var previewSpace: LabARSpace? {
        guard hasScalablePreview, let previewProject else { return nil }
        if let size = arFocus.size(in: previewProject.layout, topology: baseTopology) {
            return LabARSpace(size: SIMD3(Double(size.x), Double(size.y), Double(size.z)))
        }
        return LabARSpace(virtualRoom: previewProject.room, layout: previewProject.layout)
    }
    private var placementAnchorName: String? {
        if let activeAssembly { return activeAssembly.anchorName }
        guard arFocus == .all, let profile = previewProject?.topology.operationsProfile else { return nil }
        if profile == "home", arScale == .fullSize, operations.activeSite == "Principal" {
            return CaptureController.homePlacementName
        }
        return "NexusAR.\(operations.siteStorageID).\(profile).\(arScale.rawValue).v1"
    }
    private var previewMapExists: Bool {
        placementAnchorName.map { FileManager.default.fileExists(atPath: CaptureController.placementMapURL($0).path) } ?? false
    }
    private var canSelectARScale: Bool {
        hasScalablePreview && (mode == .room || (!restoringPlacement && !walkthrough.placementConfirmed))
    }
    private var baseTopology: LabTopology? { previewProject?.topology ?? appliedTemplate?.topology ?? roomTopology }
    private var currentTopology: LabTopology? {
        if let previewProject, previewProject.editableID != nil { return previewProject.topology }
        return baseTopology.map(operations.configured)
    }
    private var lastTopologySave: String? {
        let date = activeSavedLab?.date ?? baseTopology.flatMap(operations.lastSaved)
        return date.map { "Guardado \($0.formatted(date: .abbreviated, time: .shortened))" }
    }

    private func equipmentSummary(_ topology: LabTopology) -> String {
        let devices = topology.devices.count
        let routers = topology.devices.count { $0.modelID.hasPrefix("router-") }
        let ports = topology.devices.reduce(0) { $0 + $1.ports.count }
        return "\(devices) \(devices == 1 ? "equipo" : "equipos") · \(routers) \(routers == 1 ? "router" : "routers") · \(ports) \(ports == 1 ? "puerto" : "puertos")"
    }
    private var currentLayout: LabLayout? { previewProject?.layout ?? appliedTemplate?.layout ?? capture.layout }
    private var effectivePoweredOff: Set<String> {
        guard let baseTopology else { return poweredOff }
        let parked = currentLayout.map { baseTopology.parkedDeviceIDs(in: $0) } ?? []
        let faults = poweredOff.union(operations.faults(in: baseTopology))
        let supplyFailures = currentLayout.map { baseTopology.rackPowerFailures(in: $0, poweredOff: faults, assembly: activeAssembly) } ?? []
        return faults.union(parked).union(supplyFailures)
    }

    private func powerCut(for device: LabTopology.Device) -> Binding<Bool>? {
        guard LabRackPower.isConsumer(device.visualModelID) || device.visualModelID == LabRackPower.upsModel else { return nil }
        return Binding(get: { poweredOff.contains(device.id) }, set: { cut in
            if cut { poweredOff.insert(device.id) } else { poweredOff.remove(device.id) }
        })
    }

    private var powerInspectionAssembly: LabARAssembly? {
        if let activeAssembly { return activeAssembly }
        guard mode == .ar, let layout = currentLayout, !directPowerOutlets.isEmpty else { return nil }
        var assembly = LabARAssembly(roomLayout: layout)
        for (rack, outlet) in directPowerOutlets { assembly.setPowerOutlet(outlet, for: rack) }
        return assembly
    }

    private var pendingSignalDevices: Set<String> {
        guard let topology = currentTopology, let layout = currentLayout else { return [] }
        return topology.pendingSignalDevices(in: layout, assembly: activeAssembly)
    }

    // MARK: Voice assistant

    private func openAssistant() {
        deviceSelection = nil
        linkSelection = nil
        tracedLinkID = nil
        assistant.prepare(LabAssistantContext(
            topology: { currentTopology },
            poweredOff: { effectivePoweredOff },
            place: { device in currentLayout?.placements.first { $0.id == device.placementID }?.title },
            showPing: { showPingInScene($0, $1) },
            locate: { locateInScene(.init(deviceID: $0)) },
            setPower: { id, on in
                if on { poweredOff.remove(id) } else { poweredOff.insert(id) }
            },
            sendPacket: { sendFairPacket() },
            startChallenge: {
                assistant.close()
                assistantOpen = false
                if !fairMode { openFairMode() }
                startFairChallenge()
            }))
        assistantOpen = true
    }

    private func closeAssistant() {
        assistant.close()
        assistantOpen = false
    }

    // MARK: Fair mode

    private func openFairMode() {
        fairScores = LabFairLeaderboard.load()
        fairOutcome = nil
        fairMessage = nil
        deviceSelection = nil
        linkSelection = nil
        tracedLinkID = nil
        fairMode = true
        sendFairPacket()
    }

    private func closeFairMode() {
        if let fairChallenge { poweredOff.remove(fairChallenge.faultID) }
        fairChallenge = nil
        fairOutcome = nil
        fairMessage = nil
        fairMode = false
        pingSelection = nil
    }

    private func sendFairPacket() {
        guard let topology = currentTopology else { return }
        var generator = SystemRandomNumberGenerator()
        let routes = LabFairPlanner.routes(in: topology, poweredOff: effectivePoweredOff, using: &generator)
        guard let route = LabFairPlanner.showcase(routes, using: &generator) else {
            fairMessage = "No encontré dos equipos con una conexión activa para enviar un paquete."
            return
        }
        fairMessage = nil
        fairOutcome = nil
        packetHop = 0
        showPingInScene(route.source.id, route.destination.id)
    }

    private func startFairChallenge() {
        guard let topology = currentTopology else { return }
        if let previous = fairChallenge { poweredOff.remove(previous.faultID) }
        fairChallenge = nil
        var generator = SystemRandomNumberGenerator()
        guard let challenge = LabFairPlanner.challenge(in: topology, poweredOff: effectivePoweredOff, using: &generator) else {
            fairOutcome = nil
            fairMessage = "Este laboratorio no tiene una ruta con equipos intermedios para el reto. Prueba con la Plantilla Tier IV o el HomeLab."
            return
        }
        fairMessage = nil
        fairOutcome = nil
        deviceSelection = nil
        linkSelection = nil
        tracedLinkID = nil
        packetHop = 0
        poweredOff.insert(challenge.faultID)
        fairChallenge = challenge
        showPingInScene(challenge.source, challenge.destination)
    }

    private func answerFairChallenge(deviceIDs: [String] = [], placementID: String? = nil) {
        guard var challenge = fairChallenge else { return }
        if deviceIDs.contains(challenge.faultID) || placementID == challenge.faultPlacementID {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            finishFairChallenge(timedOut: false)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            challenge.misses += 1
            fairChallenge = challenge
        }
    }

    private func finishFairChallenge(timedOut: Bool) {
        guard let challenge = fairChallenge else { return }
        // Repair the device. The same ping stays selected, so the packet now reaches its destination.
        poweredOff.remove(challenge.faultID)
        fairChallenge = nil
        if timedOut {
            fairOutcome = .timeout(faultName: challenge.faultName)
            locateInScene(.init(deviceID: challenge.faultID))
        } else {
            fairOutcome = .found(seconds: Date.now.timeIntervalSince(challenge.started), faultName: challenge.faultName,
                                 misses: challenge.misses)
        }
    }

    private func saveFairScore(_ name: String) {
        guard case .found(let seconds, _, _) = fairOutcome else { return }
        fairScores = LabFairLeaderboard.record(.init(name: name, seconds: seconds, date: .now))
    }

    private func showPingInScene(_ source: String, _ destination: String) {
        guard let topology = currentTopology, let origin = topology.devices.first(where: { $0.id == source }),
              let target = topology.devices.first(where: { $0.id == destination }) else { return }
        let diagnosis = topology.diagnosePing(from: origin, to: target, poweredOff: effectivePoweredOff)
        pingSelection = .init(scope: layout3DScope, source: source, destination: destination)
        tracedLinkID = nil
        if mode == .room { cableFilter = nil }
        showCables = true
        if mode == .room || arFocus != .all {
            resetOrbit()
            if diagnosis.blockedLink == nil, diagnosis.path?.links.isEmpty != false, let device = diagnosis.blockedDevice {
                locateInScene(.init(deviceID: device.id))
            }
        }
        showOptions = false
        showPingDiagnostics = false
    }

    private func scenePing(in topology: LabTopology?) -> LabTopology.PingDiagnosis? {
        guard activeAssembly == nil, let topology, let pingSelection, pingSelection.scope == layout3DScope,
              let source = topology.devices.first(where: { $0.id == pingSelection.source }),
              let destination = topology.devices.first(where: { $0.id == pingSelection.destination }) else { return nil }
        return topology.diagnosePing(from: source, to: destination, poweredOff: effectivePoweredOff)
    }
    private var layout3DScope: String {
        let scan = appliedTemplate != nil ? capture.room?.roomID.uuidString : nil
        return "lab3DPositions.v1." + assemblyScope + (scan.map { "/" + $0 } ?? "")
    }

    private var visible3DLayout: LabLayout? {
        guard let layout = currentLayout else { return nil }
        return loaded3DScope == layout3DScope ? layout3DEdits.applying(to: layout) : layout
    }

    private func begin3DPlacement(_ placement: LabPlacement) {
        tracedLinkID = nil
        layout3DMessage = nil
        sync3DToAR = false
        syncARAssemblyID = nil
        do { syncARAssemblies = try assemblyStore.all().filter { $0.piece(.support(placement.id)) != nil } }
        catch {
            syncARAssemblies = []
            layout3DMessage = error.localizedDescription
        }
        preview3DPlacement = visible3DLayout?.placements.first(where: { $0.id == placement.id }) ?? placement
    }

    private func adjust3DPlacement(_ action: LabARAssembly.Adjustment, axes: SIMD2<Float>, seconds: Float) {
        guard mode == .room, scenePhase == .active, let original = preview3DPlacement, let layout = visible3DLayout,
              LabARAssembly.Adjustment.forARPlacement(original).contains(action) else { return }
        var pose = LabARAssembly.Piece(id: .support(original.id), position: original.position, yaw: original.yaw)
        pose.elevationBase = currentLayout?.placements.first { $0.id == original.id }?.position.y
        let forward = SIMD3(-sin(orbit3DHeading), 0, cos(orbit3DHeading))
        pose.adjust(action, axes: axes, forward: forward, seconds: seconds)
        let candidate = original.at(pose.position, yaw: pose.yaw)
        guard roomPlacementFits(candidate, in: layout) else {
            layout3DMessage = "Deja espacio entre los equipos y los límites del cuarto."
            return
        }
        layout3DMessage = nil
        preview3DPlacement = candidate
    }

    private func roomPlacementFits(_ placement: LabPlacement, in layout: LabLayout) -> Bool {
        LabARAssembly.roomPlacementFits(placement, in: layout, topology: currentTopology, allowingSeparation: true)
    }

    private func finish3DPlacement(_ save: Bool) {
        if save {
            guard let placement = preview3DPlacement, let layout = visible3DLayout,
                  loaded3DScope == layout3DScope, roomPlacementFits(placement, in: layout) else {
                layout3DMessage = "No hay espacio para guardar esa posición."
                return
            }
            do {
                var edits = layout3DEdits
                edits.set(placement)
                let data = try JSONEncoder().encode(edits)
                if sync3DToAR {
                    guard let id = syncARAssemblyID,
                          var target = try assemblyStore.all().first(where: { $0.id == id }),
                          let original = layout.placements.first(where: { $0.id == placement.id }) else {
                        throw LabLayoutError.invalid("Selecciona el montaje AR que quieres sincronizar.")
                    }
                    try target.apply3DChange(from: original, to: placement, in: layout, topology: currentTopology)
                    try assemblyStore.save(target)
                }
                UserDefaults.standard.set(data, forKey: layout3DScope)
                layout3DEdits = edits
            } catch {
                layout3DMessage = error.localizedDescription
                return
            }
        }
        preview3DPlacement = nil
        layout3DMessage = nil
    }

    @ViewBuilder private var sync3DControls: some View {
        Toggle("Sincronizar con AR", isOn: $sync3DToAR)
            .font(.subheadline)
            .disabled(syncARAssemblies.isEmpty)
            .onChange(of: sync3DToAR) { _, enabled in
                if enabled && syncARAssemblies.count == 1 { syncARAssemblyID = syncARAssemblies.first?.id }
            }
        if syncARAssemblies.isEmpty {
            Text("Coloca este equipo en un montaje AR para sincronizarlo.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        if sync3DToAR {
            Picker("Montaje AR", selection: $syncARAssemblyID) {
                Text("Elige un montaje").tag(nil as UUID?)
                ForEach(syncARAssemblies) { assembly in Text(assembly.name).tag(Optional(assembly.id)) }
            }
            .pickerStyle(.menu)
            .font(.subheadline)
        }
    }
    private var canUseAR: Bool {
        ARWorldTrackingConfiguration.isSupported &&
            (activeAssembly != nil || previewProject != nil || capture.arSession != nil || capture.hasSavedWorldMap)
    }

    private func resumeRoomAR(realign: Bool = false) {
        do {
            try capture.resumeAR(realign: realign)
            if mode != .ar || realign {
                walkthrough = ARWalkthrough()
                cameraRevision += 1
            } else {
                walkthrough.phase = .aligning
            }
            mode = .ar
        } catch {
            mode = .room
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func openTravel(_ travel: LabTravelMode) {
        mode = .room
        travelMode = travel
    }

    private var simulationEnabled: Bool {
        activeSavedLab.map { savedLaboratories.details($0).enabled } ?? true
    }

    private var trafficBinding: Binding<Bool> {
        Binding(get: { simulationEnabled && showTraffic }, set: { if simulationEnabled { showTraffic = $0 } })
    }

    private func returnToRoom() {
        previewSession?.pause()
        previewSession = nil
        previewProject = nil
        appliedTemplate = nil
        activeSavedLab = nil
        arFocus = .all
        mode = .room
        UserDefaults.standard.set("scan", forKey: "activeLaboratory")
    }

    private func restoreInventory(site: String?, filename: String) {
        let hidden = savedLaboratories.hiddenKeys
        loadProject("Abriendo laboratorio guardado…", build: {
            let entries = try site.map { try LabImport.history(site: $0) } ?? LabImport.received()
            let visible = entries.filter { !hidden.contains($0.libraryKey) }
            guard let entry = visible.first(where: { $0.url.lastPathComponent == filename })
                    ?? (site == nil ? nil : visible.first) else { return nil as (LabProject, LabImport.Entry)? }
            return (try LabImport.load(entry), entry)
        }) { stored in
            if let (project, entry) = stored, savedLaboratories.details(entry).inLibrary {
                showInventory(project, entry: entry)
            } else { returnToRoom() }
        }
    }

    private func openInventory(_ entry: LabImport.Entry) {
        guard savedLaboratories.details(entry).inLibrary else { return }
        loadProject("Abriendo inventario…", build: { try LabImport.load(entry) }) { project in
            guard savedLaboratories.details(entry).inLibrary else { return }
            showInventory(project, entry: entry)
        }
    }

    private func showInventory(_ project: LabProject, entry: LabImport.Entry) {
        if entry.receivedFromMac {
            openedMacLaboratory = entry.url.lastPathComponent
            acknowledgeMacReceipt(entry)
        } else { openedSiteLaboratory = entry.url.lastPathComponent }
        showPreview(project, key: entry.receivedFromMac ? "received" : "imported")
        activeSavedLab = entry
    }

    private func openPublication(_ opened: LabPublicationCache.Opened, makeCopy: Bool) {
        afterCatalogDismissal = {
            if makeCopy {
                let site = operations.siteStorageID
                loadProject("Guardando copia de práctica…", build: {
                    try LabImport.createEditableCopy(of: opened.project, site: site)
                }) { result in
                    showInventory(result.0, entry: result.1)
                }
            } else {
                showPreview(opened.project, key: "publication")
                locateInScene(.init(deviceID: opened.release.deviceID))
            }
        }
        showLabCatalog = false
    }

    private func openDataCenter() {
        loadProject("Abriendo Tier IV…", build: { try LabDemo.dataCenter() }) { project in
            showPreview(project, key: "demo")
        }
    }

    private func openHomeLab() {
        loadProject("Abriendo HomeLab…", build: { try LabDemo.homeLab() }) { project in
            showPreview(project, key: "home")
        }
    }

    private func openVLANDemo() {
        loadProject("Abriendo demo de VLAN…", build: LabDemo.vlanLab) { project in
            showPreview(project, key: LabDemo.vlanProfile)
        }
    }

    private func selectARScale(_ scale: LabARScale) {
        guard canSelectARScale, scale != arScale else { return }
        if mode == .room {
            previewSession?.pause()
            previewSession = nil
        }
        walkthrough.placementHint = nil
        if arFocus != .all { focusedARScale = scale }
        else if isManualHome { homeARScale = scale }
        else if previewProject?.layout.importedRoom == true { importedARScale = scale }
        else { tierARScale = scale }
    }

    private func applyARScale() {
        guard let scale = pendingARScale else { return }
        pendingARScale = nil
        selectARScale(scale)
    }

    private func arFocusPicker(for project: LabProject) -> TierARPicker {
        TierARPicker(project: project, selection: arFocus, available: canUseAR,
                     showsContextControl: mode == .ar && arFocus != .all,
                     showContext: $showARContext, onSelect: queueARFocus)
    }

    private func queueARFocus(_ target: LabARFocus) {
        pendingARFocus = target
        showARFocusPicker = false
    }

    private func applyARFocus() {
        guard let target = pendingARFocus else { return }
        pendingARFocus = nil
        let staysFocused = mode == .ar && arFocus != .all && target != .all
        if !staysFocused {
            openPreviewAR(reposition: target != .all, focus: target)
            return
        }
        arFocus = target
        lockedDeviceID = nil
        inspectionDestination = nil
        tracedLinkID = nil
    }

    private var assemblyScope: String {
        let project = activeSavedLab?.libraryKey ?? baseTopology?.operationsProfile
            ?? capture.room?.roomID.uuidString ?? "cuarto"
        return operations.siteStorageID + "/" + project
    }

    private var assemblyStore: LabARAssemblyStore { LabARAssemblyStore(scope: assemblyScope) }

    @ViewBuilder private var assemblyNetwork: some View {
        if let project = previewProject, project.editableID != nil, let assembly = activeAssembly {
            AssemblyNetworkEditor(project: project, assembly: assembly, selected: selectedAssemblyItem,
                                  connect: {
                                      startAssemblyConnection()
                                      openAssemblyPortPicker(afterDismissal: true)
                                  }, edit: editAssemblyNetwork)
                .toolbar { DismissButton() }
        } else {
            Form {
                Section("Copia editable") {
                    Text("Los equipos, enlaces y servicios editados se guardarán en una copia visible en Laboratorios.")
                    AssemblyCommitButton("Crear copia editable") { try createEditableAssembly(); return nil }
                }
            }
            .navigationTitle("Editar red")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { DismissButton() }
        }
    }

    private func createEditableAssembly() throws {
        guard let assembly = activeAssembly, let room = previewProject?.room ?? appliedTemplate?.room ?? capture.room,
              let layout = currentLayout, let topology = currentTopology else {
            throw LabLayoutError.invalid("Abre un laboratorio con topología antes de editar la red.")
        }
        let project = LabProject(room: room, layout: layout, topology: topology, isHomeLab: isHomeLab)
        try saveNewEditableCopy(project, assembly: assembly)
        if choosingAssemblyPorts || assemblyRackID != nil { assemblySheet = nil }
    }

    private func saveNewEditableCopy(_ project: LabProject, assembly: LabARAssembly?) throws {
        let previousLayout = loaded3DScope == layout3DScope ? try JSONEncoder().encode(layout3DEdits) : nil
        let previousStore = assemblyStore
        let previousAssemblies = try previousStore.all()
        let (copy, entry) = try LabImport.createEditableCopy(of: project, site: operations.siteStorageID)
        let store = LabARAssemblyStore(scope: operations.siteStorageID + "/" + entry.libraryKey)
        do {
            for existing in previousAssemblies.reversed() where existing.id != assembly?.id { try store.save(existing) }
            if let assembly { try store.save(assembly) }
            store.preferredID = assembly?.id ?? previousStore.preferredID
        }
        catch {
            try? FileManager.default.removeItem(at: entry.url)
            throw error
        }
        activeSavedLab = entry
        if mode == .ar && previewProject == nil && assembly == nil { previewSession = capture.arSession }
        previewProject = copy
        openedSiteLaboratory = entry.url.lastPathComponent
        UserDefaults.standard.set("imported", forKey: "activeLaboratory")
        if let previousLayout { UserDefaults.standard.set(previousLayout, forKey: layout3DScope) }
    }

    private func restoreSharedInventory() {
        guard var project = workspaceProject, project.layout.accessories == nil else { return }
        do {
            let assemblies = try assemblyStore.all()
            let pieces = assemblies.flatMap(\.pieces)
            guard pieces.contains(where: { piece in
                switch piece.id { case .extra, .monitor: true; default: false }
            }) else { return }
            let servers = Set(project.topology.devices.filter { $0.visualModelID.hasPrefix("server-") }.map(\.id))
            project.layout.accessories = []
            for piece in pieces where piece.monitorMount == nil {
                switch piece.id {
                case .extra: try project.registerAccessory(piece.id)
                case .monitor(let device, _, _):
                    if servers.contains(device) { try project.registerAccessory(piece.id) }
                default: break
                }
            }
            for rack in project.layout.placements where rack.kind == .rack {
                var monitors = project.layout.rackMonitors?[rack.id] ?? []
                for monitor in assemblies.flatMap({ $0.rackMonitors(on: rack.id) }) where servers.contains(monitor.device) {
                    if !monitors.contains(where: { $0.id == monitor.id }) { monitors.append(monitor) }
                }
                if !monitors.isEmpty { try project.mirrorRackMonitors(monitors, rackID: rack.id) }
            }
            try saveWorkspaceProject(project)
        } catch { showAssemblyError(error) }
    }

    private func saveConsoleTopology(_ topology: LabTopology) throws {
        guard let base = baseTopology else { throw LabLayoutError.invalid("El laboratorio está cerrado.") }
        if var project = previewProject, project.editableID != nil, activeSavedLab?.receivedFromMac == false {
            project.topology = topology
            try saveEditableAssembly(project)
        } else if base.operationsProfile != nil && base.editableProfileID == nil {
            try operations.save(topology, against: base)
        } else {
            guard let layout = currentLayout, let room = previewProject?.room ?? appliedTemplate?.room ?? capture.room else {
                throw LabLayoutError.invalid("Abre un laboratorio con topología antes de editar la red.")
            }
            let project = LabProject(room: room, layout: layout, topology: topology, isHomeLab: isHomeLab)
            try saveNewEditableCopy(project, assembly: activeAssembly)
        }
    }

    private func deviceConsole(_ device: LabTopology.Device) -> LabConsoleView? {
        baseTopology.map {
            LabConsoleView(base: $0, device: device, poweredOff: effectivePoweredOff,
                           liveBase: { self.baseTopology }, save: saveConsoleTopology)
        }
    }

    private var workspaceProject: LabProject? {
        guard let room = previewProject?.room ?? appliedTemplate?.room ?? capture.room,
              let layout = (mode == .room ? visible3DLayout : nil) ?? currentLayout else { return nil }
        let topology = currentTopology ?? .init(name: "Cuarto escaneado", devices: [], links: [], vlans: [], notes: [])
        return LabProject(room: room, layout: layout, topology: topology, isHomeLab: isHomeLab,
                          editableID: previewProject?.editableID)
    }

    @ViewBuilder private var equipmentEditor: some View {
        if let project = workspaceProject {
            LabWorkspaceEquipment(project: project, assembly: activeAssembly, edit: editWorkspaceEquipment,
                                  connect: connectWorkspacePorts) {
                equipmentCatalog(showDone: false)
            }
            .toolbar { DismissButton() }
        }
    }

    @ViewBuilder private func roomRackTools(_ item: LabPlacement) -> some View {
        if let project = workspaceProject,
           let rack = project.layout.placements.first(where: { $0.id == item.id }) {
            NavigationLink {
                AssemblyRackSlotForm(project: project, rack: rack, initialSlot: nil, edit: { action in
                    guard case .mount(let model, let name, let id, let slot) = action else { return nil }
                    return try editWorkspaceEquipment(.mount(model, name, rack: id, slot: slot))
                }, popOnCommit: true)
            } label: { Label("Montar equipo", systemImage: "plus.rectangle") }

            NavigationLink {
                LabRackEquipmentForm(project: project, assembly: nil, equipment: .fans, preferredRack: rack.id,
                                          popOnCommit: true) { name, id, slot in
                    try editWorkspaceEquipment(.mount(.fans, name, rack: id, slot: slot))
                }
            } label: { Label("Montar ventiladores", systemImage: "fan") }

            NavigationLink {
                let installation = LabARAssembly(roomLayout: project.layout)
                LabRackMonitorsEditor(rack: rack, assembly: installation, layout: project.layout, topology: project.topology,
                    initialSide: nil, save: { monitors in
                        guard var updated = workspaceProject else { throw LabLayoutError.invalid("El laboratorio está cerrado.") }
                        try updated.setRoomRackMonitors(monitors, rackID: rack.id)
                        try saveWorkspaceProject(updated)
                    }, monitors: roomRackMonitors(rack, in: project, installation: installation))
            } label: { Label(mode == .room ? "Monitores en 3D" : "Monitores", systemImage: "display") }
            let target = LabARAssembly.Item.support(rack.id)
            NavigationLink {
                RackPDUInspector(rack: target, layout: project.layout, topology: currentTopology ?? project.topology,
                                 assembly: powerInspectionAssembly, poweredOff: effectivePoweredOff)
            } label: { Label("Tomas y cargas de la PDU", systemImage: "list.bullet.rectangle") }
            rackPowerMenu(target, layout: project.layout, allowsOutlet: mode == .ar && arScale == .fullSize)
        }
    }

    private func rackPowerMenu(_ rack: LabARAssembly.Item, layout: LabLayout, allowsOutlet: Bool) -> some View {
        let canConfigure = layout.facility == nil || !rack.name.hasPrefix("rack-")
        let configuration = layout.pduConfiguration(for: rack.name)
        let outlet = activeAssembly?.powerOutlets?[rack] ?? directPowerOutlets[rack]
        return Menu {
            if activeAssembly != nil {
                Button("Ver tomas y cargas de la PDU", systemImage: "list.bullet.rectangle") {
                    inspectedPDU = .init(rack: rack)
                }
            }
            if canConfigure {
                ForEach(LabRackPower.Configuration.allCases, id: \.self) { option in
                    Button { configurePDU(option, for: rack) } label: {
                        if option == configuration { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            } else {
                Text("PDU A/B · Infraestructura Tier IV")
            }
            if allowsOutlet {
                Button(outlet == nil ? "Conectar a una toma AR" : "Cambiar toma AR", systemImage: "powerplug") {
                    beginPowerOutlet(for: rack)
                }
                .disabled(!walkthrough.ready)
                if outlet != nil {
                    Button("Desconectar toma AR", systemImage: "powerplug", role: .destructive) {
                        setPowerOutlet(nil, for: rack)
                    }
                }
            }
        } label: {
            Label("Energía", systemImage: "bolt")
        }
        .accessibilityIdentifier("lab.rack.power")
    }

    private func configurePDU(_ configuration: LabRackPower.Configuration, for rack: LabARAssembly.Item) {
        guard var project = workspaceProject, LabARAssembly.isPowerRack(rack, in: project.layout),
              project.layout.pduConfiguration(for: rack.name) != configuration else { return }
        if project.layout.rackPDUs == nil { project.layout.rackPDUs = [:] }
        project.layout.rackPDUs?[rack.name] = configuration
        do { try saveWorkspaceProject(project) }
        catch { showAssemblyError(error) }
    }

    private func beginPowerOutlet(for rack: LabARAssembly.Item) {
        powerOutletRack = rack
        powerOutletHint = nil
        powerOutletConfirmation = nil
        assemblyCableConfirmation = nil
        tracedLinkID = nil
        selection = nil
    }

    private func cancelPowerOutlet() {
        powerOutletRack = nil
        powerOutletHint = nil
    }

    private func hitPowerOutlet(_ rack: LabARAssembly.Item, _ outlet: LabRackPower.Outlet?) {
        guard powerOutletRack == rack, let outlet else {
            powerOutletHint = "Mueve el iPhone despacio para captar la pared y vuelve a tocar la toma."
            return
        }
        setPowerOutlet(outlet, for: rack)
    }

    private func setPowerOutlet(_ outlet: LabRackPower.Outlet?, for rack: LabARAssembly.Item) {
        guard let layout = currentLayout else { return }
        var assembly = activeAssembly ?? LabARAssembly(roomLayout: layout)
        guard assembly.piece(rack) != nil else { cancelPowerOutlet(); return }
        if activeAssembly == nil {
            for (item, saved) in directPowerOutlets { assembly.setPowerOutlet(saved, for: item) }
        }
        assembly.setPowerOutlet(outlet, for: rack)
        if outlet != nil, assembly.powerFeedPlan(in: layout, topology: currentTopology).reviewRacks.contains(rack) {
            powerOutletHint = "No hay recorrido libre hasta esa toma. Elige otra o deja espacio detrás del rack."
            return
        }
        if activeAssembly != nil {
            if outlet != nil { assembly.showsCables = true }
            do { try persistAssembly(assembly) }
            catch { showAssemblyError(error); return }
        } else {
            directPowerOutlets[rack] = outlet
            if outlet != nil { showCables = true }
        }
        cancelPowerOutlet()
        powerOutletConfirmation = outlet == nil ? nil : "Toma AR conectada"
    }

    private func roomRackMonitors(_ rack: LabPlacement, in project: LabProject,
                                  installation: LabARAssembly) -> [LabARAssembly.RackMonitor] {
        if let saved = project.layout.rackMonitors?[rack.id] { return saved }
        guard project.topology.operationsProfile != nil else { return [] }
        var preview = installation
        for device in project.topology.devices where device.placementID == rack.id && device.hasDashboard {
            for side in [RackMount.Side.right, .left] {
                guard let row = preview.freeMonitorRows(on: rack, side: side, in: project.layout,
                                                        topology: project.topology).first else { continue }
                let monitor = LabARAssembly.RackMonitor(id: UUID(), device: device.id, panel: .services, side: side, row: row)
                preview.set(monitor.piece(on: rack))
                break
            }
        }
        return preview.rackMonitors(on: rack.id)
    }

    private func rackDeviceMove(_ device: LabTopology.Device) -> AnyView? {
        guard let project = workspaceProject,
              let equipment = project.topology.devices.first(where: { $0.id == device.id }),
              let support = project.layout.placements.first(where: { $0.id == equipment.placementID }),
              support.kind == .rack || support.kind == .floor || equipment.parkedOnDesk == true else { return nil }
        let hasDesk = project.layout.placements.contains { desk in
            (activeAssembly.map { $0.piece(.support(desk.id)) != nil } ?? true)
                && project.deskOffset(for: equipment.visualSize, on: desk, excluding: equipment.id) != nil
        }
        return AnyView(LabRackDeviceMoveForm(project: project, device: equipment, assembly: activeAssembly, move: { rack, slot in
            guard let current = workspaceProject else { throw LabLayoutError.invalid("El laboratorio está cerrado.") }
            let assembly = activeAssembly
            let scope = assemblyScope
            let viewMode = mode
            let moved = try await current.relocatingRackDevice(device.id, to: rack, slot: slot, assembly: assembly)
            guard assembly == activeAssembly, scope == assemblyScope, viewMode == mode,
                  workspaceProject?.topology == current.topology,
                  workspaceProject?.layout == current.layout else {
                throw LabLayoutError.invalid("El laboratorio cambió. Vuelve a elegir la posición.")
            }
            var updated = assembly
            updated?.remove(.device(device.id))
            updated?.syncInventory(in: moved.layout, topology: moved.topology, placeMissing: false)
            try saveWorkspaceProject(moved, assembly: updated)
        }, onFloor: support.kind == .floor, onDesk: equipment.parkedOnDesk == true,
            putOnFloor: support.kind != .floor ? { try beginEquipmentPlacement(device.id, surface: .floor) } : nil,
            putOnDesk: hasDesk ? { try beginEquipmentPlacement(device.id, surface: .desk) } : nil,
            delete: { try removeRackDevice(device.id) }))
    }

    private func beginEquipmentPlacement(_ id: String, surface: LabEquipmentSurface) throws {
        guard let original = workspaceProject, let device = original.topology.devices.first(where: { $0.id == id }) else {
            throw LabLayoutError.invalid("El equipo ya no está disponible.")
        }
        guard mode == .room || walkthrough.ready else {
            throw LabLayoutError.invalid("Espera a que AR recupere el seguimiento.")
        }
        clearAssemblyPorts()
        assemblyRackID = nil
        assemblySheet = nil
        showOptions = false
        tracedLinkID = nil
        assemblyCableConfirmation = nil
        equipmentPlacement = .init(device: device, original: original, surface: surface)
        selection = nil
        deviceSelection = nil
    }

    private func chooseEquipmentTarget(_ target: LabEquipmentTarget?) {
        guard var draft = equipmentPlacement else { return }
        do {
            guard let target else {
                throw LabLayoutError.invalid(draft.surface == .floor ? "Toca una parte visible del piso." : "Toca la superficie de una mesa.")
            }
            var project = draft.original
            var assembly = activeAssembly
            let device = draft.device
            guard let origin = project.layout.placements.first(where: { $0.id == device.placementID }) else {
                throw LabLayoutError.invalid("El equipo cambió de posición.")
            }
            assembly?.remove(.device(device.id))
            if origin.kind == .floor { assembly?.remove(.support(origin.id)) }
            let outline: LabPlacement
            switch target {
            case .floor(let point):
                let position: SIMD3<Float>
                let yaw: Float
                if let activeAssembly {
                    let reference = [origin] + project.layout.placements.filter { $0.id != origin.id }
                    guard let support = reference.first(where: { activeAssembly.piece(.support($0.id)) != nil }),
                          let pose = activeAssembly.piece(.support(support.id)) else {
                        throw LabLayoutError.invalid("Coloca un rack o una mesa para tener una referencia.")
                    }
                    let rotation = simd_quatf(angle: support.yaw, axis: SIMD3(0, 1, 0))
                    position = support.position + rotation.act(pose.rotation.inverse.act(point - pose.position))
                    yaw = origin.yaw + pose.yaw - support.yaw
                } else {
                    position = point
                    yaw = origin.yaw
                }
                let floor = try project.putRackDeviceOnFloor(device.id, at: position, yaw: origin.yaw)
                if assembly != nil { assembly?.set(.init(id: .support(floor.id), position: point, yaw: yaw)) }
                outline = floor.at(point, yaw: yaw)
            case .desk(let deskID, let point):
                guard let desk = project.layout.placements.first(where: { $0.id == deskID }) else {
                    throw LabLayoutError.invalid("La mesa ya no está disponible.")
                }
                try project.putRackDeviceOnDesk(device.id, deskID: deskID, at: point)
                let pose = assembly?.piece(.support(deskID)) ?? .init(id: .support(deskID), position: desk.position, yaw: desk.yaw)
                outline = .init(id: device.id, kind: .floor, title: device.name,
                                position: pose.world(SIMD3(point.x, 0.75, point.y)), yaw: pose.yaw, size: device.visualSize)
            }
            if let assembly, let previous = activeAssembly,
               assembly.conflicts(with: previous, in: project.layout, topology: project.topology,
                                  previousTopology: draft.original.topology, previousLayout: draft.original.layout) {
                throw LabLayoutError.invalid(LabARAssembly.collisionHint)
            }
            draft.choice = .init(project: project, assembly: assembly, outline: outline)
            draft.hint = nil
        } catch {
            draft.choice = nil
            draft.hint = error.localizedDescription
        }
        equipmentPlacement = draft
    }

    private func confirmEquipmentPlacement() {
        guard let draft = equipmentPlacement, let choice = draft.choice else { return }
        guard let current = workspaceProject, current.room.roomID == draft.original.room.roomID,
              current.layout == draft.original.layout, current.topology == draft.original.topology else {
            equipmentPlacement = nil
            showAssemblyError(LabLayoutError.invalid("El laboratorio cambió. Vuelve a elegir el equipo."))
            return
        }
        do {
            try saveWorkspaceProject(choice.project, assembly: choice.assembly)
            selectedAssemblyItem = mode == .ar ? .device(draft.device.id) : nil
            equipmentPlacement = nil
        } catch { equipmentPlacement?.hint = error.localizedDescription }
    }

    private func removeRackDevice(_ id: String) throws {
        guard var project = workspaceProject else { throw LabLayoutError.invalid("El laboratorio está cerrado.") }
        try project.deleteRackDevice(id)
        var assembly = activeAssembly
        assembly?.syncInventory(in: project.layout, topology: project.topology, placeMissing: false)
        try saveWorkspaceProject(project, assembly: assembly)
        if selectedAssemblyItem == .device(id) { selectedAssemblyItem = nil }
        if deviceSelection?.id == id { deviceSelection = nil }
        if !project.topology.links.contains(where: { $0.id == tracedLinkID }) { tracedLinkID = nil }
    }

    private func saveWorkspaceProject(_ edited: LabProject, assembly updatedAssembly: LabARAssembly? = nil) throws {
        var project = edited
        if mode == .room, let original = currentLayout {
            // Spatial edits in 3D stay in the existing pose store, separate from the floor-level layout.
            project.layout.placements = edited.layout.placements.map { placement in
                guard let saved = original.placements.first(where: { $0.id == placement.id }) else { return placement }
                return placement.at(saved.position, yaw: saved.yaw)
            }
        }
        if project.editableID != nil && activeSavedLab?.receivedFromMac == false {
            try saveEditableAssembly(project)
            if let updatedAssembly { try assemblyStore.save(updatedAssembly) }
        } else {
            try saveNewEditableCopy(project, assembly: updatedAssembly ?? activeAssembly)
        }
        if let updatedAssembly { activeAssembly = updatedAssembly }
    }

    private func editWorkspaceEquipment(_ action: LabEquipmentEdit) throws -> String? {
        guard let original = workspaceProject else { throw LabLayoutError.invalid("Abre un laboratorio para editarlo.") }
        var project = original
        var support: String?
        var device: String?
        switch action {
        case let .rack(height, name):
            support = try project.addRack(height, name: name).id
            project = try project.completingRackCabling()
        case let .mount(model, name, rack, slot):
            let mounted = try project.mount(model, name: name, rackID: rack, slot: slot)
            (support, device) = (mounted.placementID, mounted.id)
        case let .equipment(equipment, name, desk, mode, accessPoint):
            let added = try project.addDeskEquipment(equipment, name: name, deskID: desk)
            if added.supportsWiFi { try project.topology.configureClient(added.id, mode: mode, accessPoint: accessPoint) }
            (support, device) = (added.placementID, added.id)
        case let .desk(name, width, depth):
            support = try project.addDesk(width: width, depth: depth, name: name).id
        case let .resizeDesk(id, width, depth):
            try project.resizeDesk(id, width: width, depth: depth)
        case let .connection(id, mode, accessPoint):
            try project.topology.configureClient(id, mode: mode, accessPoint: accessPoint)
        case let .routing(id, level):
            try project.setCableLevel(id, to: level, assembly: activeAssembly)
        }
        if let assembly = activeAssembly,
           assembly.conflicts(with: assembly, in: project.layout, topology: project.topology,
                              previousTopology: original.topology, previousLayout: original.layout) {
            throw LabLayoutError.invalid(LabARAssembly.collisionHint)
        }
        try saveWorkspaceProject(project)
        if let assembly = activeAssembly, let support {
            if assembly.piece(.support(support)) == nil {
                assemblyPlacement = .item(.support(support), .floor)
                assemblySheet = nil
            } else if let device {
                selectedAssemblyItem = .device(device)
            }
        }
        return nil
    }

    private func connectWorkspacePorts(_ route: AssemblyPortRoute, to destination: LabTopology.Port) async throws -> String {
        guard let project = workspaceProject else { throw LabLayoutError.invalid("Abre un laboratorio para conectarlo.") }
        let scope = assemblyScope
        let viewMode = mode
        let assembly = activeAssembly
        let vlans = route.vlanIDs(in: project.topology)
        let result: (project: LabProject, linkID: String)
        if let assembly {
            result = try await project.connectingARPorts(route.origin, to: destination, vlans: vlans, level: route.level, in: assembly)
        } else {
            result = try await project.connectingRoomPorts(route.origin, to: destination, vlans: vlans, level: route.level)
        }
        try Task.checkCancellation()
        guard scope == assemblyScope, viewMode == mode, assembly == activeAssembly,
              workspaceProject?.topology == project.topology, workspaceProject?.layout.placements == project.layout.placements else {
            throw LabLayoutError.invalid("El laboratorio cambió. Vuelve a seleccionar los puertos.")
        }
        try saveWorkspaceProject(result.project)
        showCables = true
        tracedLinkID = result.linkID
        negotiatingLink = result.linkID
        return result.project.topology.links.first { $0.id == result.linkID }?.circuitID == nil
            ? "Cable conectado." : "Cable conectado por patch panel."
    }

    private func finishAssemblySheet() {
        assemblySearch = ""
        projectPartSearch = ""
        if let next = nextAssemblySheet {
            nextAssemblySheet = nil
            assemblySheet = next
        } else {
            openPendingAssembly()
        }
    }

    private var selectedRack: LabPlacement? {
        guard let item = selectedAssemblyItem, let assembly = activeAssembly else { return nil }
        let id: String?
        switch item {
        case .support(let rack): id = rack
        case .device(let device) where assembly.piece(item) == nil:
            id = currentTopology?.devices.first { $0.id == device }?.placementID
        default: id = nil
        }
        guard let id, assembly.piece(.support(id)) != nil else { return nil }
        return currentLayout?.placements.first { $0.id == id && $0.kind == .rack }
    }

    private var selectedPowerRack: LabARAssembly.Item? {
        if let selectedRack { return .support(selectedRack.id) }
        guard let item = selectedAssemblyItem, let layout = currentLayout,
              activeAssembly?.piece(item) != nil, LabARAssembly.isPowerRack(item, in: layout) else { return nil }
        return item
    }

    @ViewBuilder private var assemblyRackSheet: some View {
        if let project = previewProject, project.editableID != nil,
           let rack = project.layout.placements.first(where: { $0.id == assemblyRackID }) {
            let slot = if case .unit(let value) = assemblyRackTarget { value } else { nil as Int? }
            AssemblyRackSlotForm(project: project, rack: rack, initialSlot: slot, edit: editAssemblyNetwork)
                .toolbar { DismissButton() }
        }
    }

    @ViewBuilder private var assemblyRackMonitors: some View {
        if let rack = selectedRack, let assembly = activeAssembly, let layout = currentLayout, let topology = currentTopology {
            let side = if case .side(let value) = assemblyRackTarget { value } else { nil as RackMount.Side? }
            LabRackMonitorsEditor(rack: rack, assembly: assembly, layout: layout, topology: topology, initialSide: side,
                save: { try updateAssemblyMonitors($0, rack: rack) }, monitors: assembly.rackMonitors(on: rack.id))
                .toolbar { DismissButton() }
        }
    }

    @ViewBuilder private var assemblyRackDevices: some View {
        if let rack = selectedRack, let topology = currentTopology {
            PlacementInspector(placement: rack, topology: topology, locateTitle: locateTitle,
                               onLocate: { destination in
                                   assemblySheet = nil
                                   locateInScene(destination)
                               }, console: deviceConsole, moveDevice: rackDeviceMove, poweredOff: $poweredOff)
                .toolbar { DismissButton() }
        }
    }

    private func openRackTarget(_ rack: String, target: RackMount.Target?) {
        guard rack == assemblyRackID else { return }
        assemblyRackTarget = target
        if case .side = target { assemblySheet = .rackMonitors }
        else { assemblySheet = previewProject?.editableID != nil ? .rack : .network }
    }

    private func updateAssemblyMonitors(_ monitors: [LabARAssembly.RackMonitor], rack: LabPlacement) throws {
        guard let previous = activeAssembly, var project = workspaceProject,
              previous.piece(.support(rack.id)) != nil else {
            throw LabLayoutError.invalid("Selecciona un rack colocado.")
        }
        var assembly = previous
        let old = previous.rackMonitors(on: rack.id)
        for monitor in old { assembly.remove(monitor.item) }
        for monitor in monitors { assembly.set(monitor.piece(on: rack)) }
        guard !assembly.conflicts(with: previous, in: project.layout, topology: project.topology) else {
            throw LabLayoutError.invalid(LabARAssembly.collisionHint)
        }
        let ids = Set(old.map { $0.item.name })
        project.layout.accessories?.removeAll { ids.contains($0.id.name) }
        let updatedIDs = Set(monitors.map(\.id))
        let pending = (project.layout.rackMonitors?[rack.id] ?? []).filter {
            !ids.contains($0.item.name) && !updatedIDs.contains($0.id)
        }
        try project.mirrorRackMonitors(monitors + pending, rackID: rack.id)
        try saveWorkspaceProject(project, assembly: assembly)
    }

    @ViewBuilder private var assemblyPortSheet: some View {
        if let topology = currentTopology {
            AssemblyPhysicalPortPicker(topology: topology, options: sceneConnectionPorts, origin: assemblyPortRoute?.origin,
                                       preferredDevice: assemblyPortDevice, select: pickAssemblyPort)
                .toolbar { DismissButton() }
        }
    }

    private var sceneConnectionPorts: [LabTopology.Port] {
        guard let topology = currentTopology, let layout = currentLayout else { return [] }
        let origin = assemblyPortRoute?.origin
        let medium = origin.flatMap { topology.medium(at: $0) }
        if origin != nil && medium == nil { return [] }
        let parked = topology.parkedDeviceIDs(in: layout)
        return topology.devices.flatMap { device -> [LabTopology.Port] in
            guard !parked.contains(device.id), device.id != origin?.deviceID else { return [] }
            if let assembly = activeAssembly { return assembly.connectionPorts(on: device, in: topology, from: origin) }
            return topology.freePorts(on: device, matching: medium)
        }
    }

    @ViewBuilder private var assemblyPortSettings: some View {
        if let topology = currentTopology, let route = assemblyPortRoute {
            AssemblyPortRouteForm(topology: topology, route: Binding(
                get: { assemblyPortRoute ?? route }, set: { assemblyPortRoute = $0 }
            ))
            .toolbar { DismissButton() }
        }
    }

    private var assemblyPortPickingAvailable: Bool {
        (mode == .room ? (choosingAssemblyPorts || assemblyPortRoute != nil) : (walkthrough.ready && currentTopology != nil)) &&
            equipmentPlacement == nil && preview3DPlacement == nil && assemblyPlacement == nil && assemblyEdit == nil && waypointEdit == nil &&
            assemblyRackID == nil && assemblyCableRequest == nil && assemblyPortDestination == nil && assemblySheet == nil
    }

    private func startAssemblyConnection() {
        choosingAssemblyPorts = true
        tracedLinkID = nil
        assemblyCableConfirmation = nil
        walkthrough.placementHint = nil
    }

    private func openAssemblyPortPicker(device: String? = nil, afterDismissal: Bool = false) {
        guard assemblyPortDestination == nil else { return }
        if let device { assemblyPortDevice = device }
        else if case .device(let id) = selectedAssemblyItem { assemblyPortDevice = id }
        else { assemblyPortDevice = nil }
        if afterDismissal {
            nextAssemblySheet = .port
            assemblySheet = nil
        } else {
            assemblySheet = .port
        }
    }

    private func pickAssemblyPort(_ port: LabTopology.Port) throws {
        guard assemblyPortDestination == nil, port != assemblyPortRoute?.origin else { return }
        guard let topology = currentTopology, sceneConnectionPorts.contains(port) else {
            let message = assemblyPortRoute == nil
                ? "Elige un puerto libre y habilitado de un equipo colocado."
                : "Elige un puerto libre y compatible en otro equipo colocado."
            throw LabLayoutError.invalid(message)
        }
        if assemblyPortRoute == nil {
            startAssemblyConnection()
            assemblyPortRoute = .init(origin: port, vlan: topology.suggestedVLAN(at: port) ?? -2)
            UISelectionFeedbackGenerator().selectionChanged()
        } else {
            walkthrough.placementHint = nil
            assemblyPortDestination = port
        }
        assemblySheet = nil
    }

    private func connectAssemblyCable(to destination: LabTopology.Port) async {
        guard let route = assemblyPortRoute else {
            assemblyPortDestination = nil
            return
        }
        do {
            let status = try await connectWorkspacePorts(route, to: destination)
            guard assemblyPortDestination == destination else { return }
            let message = "\(status.trimmingCharacters(in: .punctuationCharacters)) · \(route.origin.name) → \(destination.name)"
            clearAssemblyPorts()
            cableFilter = nil
            assemblyCableConfirmation = message
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AccessibilityNotification.Announcement(message).post()
        } catch {
            guard !Task.isCancelled, assemblyPortDestination == destination else { return }
            assemblyPortDestination = nil
            let message = error.localizedDescription
            walkthrough.placementHint = message
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private func handleAssemblyPort(_ port: LabTopology.Port) {
        guard assemblyPortPickingAvailable else { return }
        do { try pickAssemblyPort(port) }
        catch {
            if choosingAssemblyPorts {
                walkthrough.placementHint = error.localizedDescription
            } else {
                selectAssemblyPiece(.device(port.deviceID))
            }
        }
    }

    private func selectAssemblyPiece(_ item: LabARAssembly.Item) {
        guard assemblyEdit == nil, assemblyCableRequest == nil, assemblyPortDestination == nil else { return }
        if assemblyRackID != nil {
            guard case .device = item else { return }
            assemblyRackID = nil
        }
        if choosingAssemblyPorts {
            if case .device(let id) = item { openAssemblyPortPicker(device: id) }
        } else {
            assemblyCableConfirmation = nil
            selectedAssemblyItem = item
        }
    }

    private func clearAssemblyPorts() {
        choosingAssemblyPorts = false
        assemblyPortRoute = nil
        assemblyPortDestination = nil
        assemblyPortDevice = nil
        walkthrough.placementHint = nil
    }

    private var cableWaypointDragEnabled: Bool {
        previewProject?.editableID != nil && walkthrough.ready && tracedLinkID != nil &&
            !choosingAssemblyPorts && assemblyRackID == nil && assemblyEdit == nil && assemblyPlacement == nil &&
            assemblySheet == nil
    }

    @discardableResult
    private func handleWaypointGesture(_ phase: LabARAssembly.WaypointGesture) -> SIMD2<Float>? {
        switch phase {
        case .began(let index):
            guard cableWaypointDragEnabled, let id = tracedLinkID, let points = activeAssembly?.waypoints?[id],
                  points.indices.contains(index) else { return nil }
            waypointEdit = WaypointEdit(link: id, index: index, value: points[index])
            walkthrough.placementHint = nil
        case .moved(let point):
            guard let assembly = activeAssembly, waypointEdit != nil else { return nil }
            let snapped = assembly.snappedWaypoint(point)
            if waypointEdit?.value != snapped { waypointEdit?.value = snapped }
        case .finished, .cancelled:
            guard let edit = waypointEdit, var assembly = activeAssembly, var points = assembly.waypoints?[edit.link],
                  points.indices.contains(edit.index) else { waypointEdit = nil; return nil }
            waypointEdit = nil
            let original = points[edit.index]
            if case .cancelled = phase { return original }
            guard original != edit.value, let project = previewProject else { return original }
            points[edit.index] = edit.value
            assembly.setWaypoints(points, for: edit.link)
            do {
                try assembly.validateCableRoute(edit.link, in: project)
                try assemblyStore.save(assembly)
                activeAssembly = assembly
                walkthrough.placementHint = nil
                return edit.value
            } catch {
                walkthrough.placementHint = error.localizedDescription
                return original
            }
        }
        return nil
    }

    private func saveEditableAssembly(_ project: LabProject) throws {
        guard let entry = activeSavedLab else { throw LabLayoutError.invalid("Falta la copia editable del laboratorio.") }
        try LabImport.saveEditable(project, to: entry)
        previewProject = project
        activeSavedLab = .init(url: entry.url, name: entry.name, date: .now)
    }

    private func editAssemblyNetwork(_ action: AssemblyNetworkAction) throws -> String? {
        guard var project = previewProject, project.editableID != nil, var assembly = activeAssembly else {
            throw LabLayoutError.invalid("Abre la copia editable para cambiar la red.")
        }
        let failed = effectivePoweredOff
        switch action {
        case .rack(let height, let name):
            let rack = try project.addRack(height, name: name)
            project = try project.completingRackCabling()
            try saveEditableAssembly(project)
            assemblyPlacement = .item(.support(rack.id), .floor)
            assemblySheet = nil
        case .mount(let equipment, let name, let rackID, let slot):
            let previousTopology = project.topology
            let device = try project.mount(equipment, name: name, rackID: rackID, slot: slot)
            guard !assembly.conflicts(with: assembly, in: project.layout, topology: project.topology,
                                      previousTopology: previousTopology) else {
                throw LabLayoutError.invalid(LabARAssembly.collisionHint)
            }
            try saveEditableAssembly(project)
            if assembly.piece(.support(rackID)) == nil {
                assemblyPlacement = .item(.support(rackID), .floor)
                assemblySheet = nil
            } else {
                if assemblyRackID == rackID { assemblySheet = nil }
                else { selectedAssemblyItem = .device(device.id) }
            }
        case let .configure(id, name, address, vlan, services):
            try project.topology.configureServer(id, name: name, address: address, vlan: vlan, services: services)
            try saveEditableAssembly(project)
        case .disconnect(let id):
            project.topology.disconnect(id)
            try saveEditableAssembly(project)
            if !project.topology.links.contains(where: { $0.id == tracedLinkID }) { tracedLinkID = nil }
        case .cableLevel(let id, let level):
            try project.setCableLevel(id, to: level, assembly: assembly)
            try saveEditableAssembly(project)
        case .trace(let id):
            try assembly.validateCableRoute(id, in: project, allowReview: true)
            tracedLinkID = id
            walkthrough.placementHint = nil
            assemblySheet = nil
        case .placeWaypoint(let id, let index):
            try assembly.validateCableRoute(id, in: project, allowReview: true)
            assemblyPlacement = .waypoint(id, index)
            tracedLinkID = id
            assemblySheet = nil
        case .removeWaypoint(let id, let index):
            var points = assembly.waypoints?[id] ?? []
            guard points.indices.contains(index) else { return nil }
            points.remove(at: index)
            assembly.setWaypoints(points, for: id)
            try assembly.validateCableRoute(id, in: project)
            try assemblyStore.save(assembly)
            activeAssembly = assembly
        case .monitor(let device, let panel):
            assemblyPlacement = .item(.monitor(device: device, panel: panel, id: UUID()), .floor)
            assemblySheet = nil
        case .dhcp(let id, let vlan):
            let lease = try project.topology.requestDHCP(for: id, vlan: vlan, poweredOff: failed)
            try saveEditableAssembly(project)
            return lease
        case .dns(let client, let name):
            guard let device = project.topology.devices.first(where: { $0.id == client }) else { return nil }
            guard device.ipv4 != nil else { return "DNS · El cliente necesita una IPv4." }
            return project.topology.resolveSimulatedDNS(name, from: device, poweredOff: failed)
        case .http(let client, let server):
            guard let source = project.topology.devices.first(where: { $0.id == client }),
                  let target = project.topology.devices.first(where: { $0.id == server }) else { return nil }
            guard source.ipv4 != nil else { return "HTTP · El cliente necesita una IPv4." }
            return project.topology.testNetwork(from: source, to: target, tcp: 80, poweredOff: failed)
        }
        return nil
    }

    private func showAssemblyLocations() {
        assemblyList = []
        assemblyName = ""
        assemblyNameError = nil
        assemblySheet = .locations
    }

    private var assemblyLocations: some View {
        List {
            if !ARWorldTrackingConfiguration.isSupported {
                Label("Usa un iPhone compatible para abrir el montaje en AR.", systemImage: "iphone")
            }
            if !assemblyList.isEmpty {
                Section("Ubicaciones guardadas") {
                    ForEach(assemblyList) { assembly in
                        HStack {
                            Button {
                                assemblyToOpen = assembly
                                assemblySheet = nil
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(assembly.name, systemImage: "mappin.circle")
                                    let saved = FileManager.default.fileExists(atPath: CaptureController.placementMapURL(assembly.anchorName).path)
                                    Text(saved ? "\(assembly.pieces.count) piezas · Ubicación guardada"
                                         : "\(assembly.pieces.count) piezas · Ubicación pendiente")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .disabled(!ARWorldTrackingConfiguration.isSupported)
                            Menu {
                                Button("Renombrar", systemImage: "pencil") {
                                    assemblyToRename = assembly
                                    renamedAssemblyName = assembly.name
                                    showAssemblyRename = true
                                }
                                Button("Eliminar", systemImage: "trash", role: .destructive) {
                                    assemblyToDelete = assembly
                                    showAssemblyDeletion = true
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Opciones de \(assembly.name)")
                        }
                    }
                }
            }
            if let assemblyNameError {
                Label(assemblyNameError, systemImage: "exclamationmark.circle")
            }
            Section("Nueva ubicación") {
                TextField("Nombre, por ejemplo Sala A", text: $assemblyName)
                    .submitLabel(.done)
                    .onSubmit(createAssembly)
                    .onChange(of: assemblyName) { _, _ in assemblyNameError = nil }
                Button("Crear montaje", systemImage: "plus", action: createAssembly)
                    .disabled(assemblyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Montajes AR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { DismissButton() }
        .alert("Renombrar ubicación", isPresented: $showAssemblyRename, presenting: assemblyToRename) { assembly in
            TextField("Nombre", text: $renamedAssemblyName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") {
                do {
                    let renamed = try assemblyStore.rename(assembly.id, to: renamedAssemblyName)
                    if activeAssembly?.id == renamed.id { activeAssembly?.name = renamed.name }
                    assemblyList = try assemblyStore.all()
                    assemblyNameError = nil
                } catch { assemblyNameError = error.localizedDescription }
            }
            .disabled(renamedAssemblyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Eliminar ubicación", isPresented: $showAssemblyDeletion, presenting: assemblyToDelete) { assembly in
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                do {
                    try assemblyStore.delete(assembly.id) { CaptureController.placementMapURL($0.anchorName) }
                    if activeAssembly?.id == assembly.id { mode = .room }
                    assemblyList = try assemblyStore.all()
                    assemblyNameError = nil
                } catch { assemblyNameError = error.localizedDescription }
            }
        } message: { assembly in
            Text("Se eliminará el montaje de RA «\(assembly.name)» de este laboratorio.")
        }
        .task(id: assemblyScope) {
            do { assemblyList = try assemblyStore.all() }
            catch { assemblyNameError = error.localizedDescription }
        }
    }

    private func createAssembly() {
        do {
            let assembly = try assemblyStore.save(LabARAssembly(id: UUID(), name: assemblyName))
            assemblyList = try assemblyStore.all()
            assemblyName = ""
            if ARWorldTrackingConfiguration.isSupported {
                assemblyToOpen = assembly
                assemblySheet = nil
            }
        } catch { assemblyNameError = error.localizedDescription }
    }

    private func openPendingAssembly() {
        let requestedRack = rackForMonitors.map(LabARAssembly.Item.support)
        rackForMonitors = nil
        guard let requested = assemblyToOpen else { return }
        assemblyToOpen = nil
        guard ARWorldTrackingConfiguration.isSupported, !requestingPreviewCamera else { return }
        let scope = assemblyScope
        requestingPreviewCamera = true
        Task {
            defer { requestingPreviewCamera = false }
            guard await authorizePreviewCamera() else { return }
            guard scope == assemblyScope else { return }
            if mode == .room { restoreSharedInventory() }
            var assembly = requested
            if let project = workspaceProject {
                assembly.syncInventory(in: project.layout, topology: project.topology)
            }
            do {
                if requested != assembly { try assemblyStore.save(assembly) }
                assemblyStore.preferredID = assembly.id
            } catch { showAssemblyError(error); return }
            arFocus = .all
            activeAssembly = assembly
            selectedAssemblyItem = requestedRack.flatMap { assembly.piece($0)?.id }
            assemblyCableRequest = nil
            assemblyEdit = nil
            assemblyPlacement = !assembly.pieces.isEmpty && !previewMapExists ? .origin : nil
            if let requestedRack, assembly.pieces.isEmpty { assemblyPlacement = .item(requestedRack, .floor) }
            startPreviewSession(reposition: false)
        }
    }

    private func equipmentCatalog(showDone: Bool) -> some View {
        let query = assemblySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = HardwareCatalog.byGroup.mapValues { items in
            items.filter { $0.matchesCatalogSearch(query) }
        }
        let extras: [(model: String, title: String, icon: String, group: HardwareItem.Group)] = [
            ("test-desk", "Escritorio de pruebas", "table.furniture", .racks),
            ("battery-bank", "Banco de baterías", "battery.100percent", .power)
        ].filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.group.matches(query) }

        return List {
            if activeAssembly != nil && query.isEmpty {
                Section {
                    NavigationLink {
                        assemblyProjectParts
                    } label: {
                        Label("Piezas del proyecto", systemImage: "square.stack.3d.up")
                    }
                }
            }
            ForEach(HardwareItem.Group.allCases, id: \.self) { group in
                let items = models[group] ?? []
                let extraItems = extras.filter { $0.group == group }
                if !items.isEmpty || !extraItems.isEmpty {
                    Section(group.rawValue) {
                        ForEach(items) { item in
                            NavigationLink {
                                catalogPlacementOptions(model: item.id, title: item.name, icon: group.symbol, detail: item.category)
                            } label: {
                                catalogLabel(item.name, icon: group.symbol, detail: item.category)
                            }
                        }
                        ForEach(extraItems, id: \.model) { extra in
                            NavigationLink {
                                catalogPlacementOptions(model: extra.model, title: extra.title, icon: extra.icon)
                            } label: {
                                catalogLabel(extra.title, icon: extra.icon)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if models.values.allSatisfy(\.isEmpty) && extras.isEmpty {
                ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass",
                                       description: Text("Busca por tipo o modelo de equipo."))
            }
        }
        .navigationTitle("Catálogo de equipos")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $assemblySearch, prompt: "Buscar por tipo o modelo")
        .toolbar { if showDone { DismissButton() } }
    }

    private func catalogPlacementOptions(model: String, title: String, icon: String, detail: String? = nil) -> some View {
        let preferredSupport = if case .support(let id) = selectedAssemblyItem { id } else { selectedAssemblyDevice?.placementID }
        let rackEquipment = RackMount.Equipment(rawValue: model)
        let deskEquipment = LabDeskEquipment(rawValue: model)
        return List {
            Section {
                catalogLabel(title, icon: icon, detail: detail)
                    .font(.headline)
            }
            if let project = workspaceProject,
               rackEquipment != nil || deskEquipment != nil || model == "rack-r42612" || model == "test-desk" {
                Section {
                    if let equipment = rackEquipment {
                        NavigationLink {
                            LabRackEquipmentForm(project: project, assembly: activeAssembly, equipment: equipment,
                                                 preferredRack: preferredSupport, addRack: { action in
                                guard case .rack(let height, let name) = action else { return nil }
                                return try editWorkspaceEquipment(.rack(height, name))
                            }) { name, rack, slot in
                                try commitCatalogEquipment(.mount(equipment, name, rack: rack, slot: slot))
                            }
                        } label: {
                            Label("Montar en rack", systemImage: "server.rack")
                        }
                    }
                    if let equipment = deskEquipment {
                        NavigationLink {
                            LabDeskEquipmentForm(project: project, assembly: activeAssembly, preferredSupport: preferredSupport,
                                                 equipment: equipment, edit: commitCatalogEquipment)
                        } label: {
                            Label("Colocar en mesa", systemImage: "table.furniture")
                        }
                    }
                    if model == "rack-r42612" {
                        NavigationLink {
                            AssemblyRackForm(height: .full) { action in
                                guard case .rack(let height, let name) = action else { return nil }
                                return try commitCatalogEquipment(.rack(height, name))
                            }
                        } label: {
                            Label("Crear rack para equipos", systemImage: "server.rack")
                        }
                    }
                    if model == "test-desk" {
                        NavigationLink {
                            LabDeskDimensionsForm(desk: nil, edit: editWorkspaceEquipment)
                        } label: {
                            Label("Crear mesa para equipos", systemImage: "table.furniture")
                        }
                    }
                }
            }
            if rackEquipment != .fans {
                Section {
                    AssemblyCommitButton("Añadir como modelo 3D", systemImage: "cube") {
                        let item = LabARAssembly.Item.extra(model: model, id: UUID())
                        if activeAssembly != nil {
                            assemblyPlacement = .item(item, .floor)
                        } else {
                            guard var project = workspaceProject else { throw LabLayoutError.invalid("Abre un laboratorio para añadir el modelo.") }
                            try project.registerAccessory(item)
                            try saveWorkspaceProject(project)
                        }
                        assemblySheet = nil
                        return nil
                    }
                } footer: {
                    Text("Añade un accesorio visual a la escena.")
                }
            }
        }
        .navigationTitle("Añadir equipo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func commitCatalogEquipment(_ action: LabEquipmentEdit) throws -> String? {
        let message = try editWorkspaceEquipment(action)
        assemblySheet = nil
        return message
    }

    private var assemblyProjectParts: some View {
        let query = projectPartSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ name: String) -> Bool {
            query.isEmpty || name.localizedStandardContains(query)
        }

        let layout = currentLayout
        let placed = (activeAssembly?.pieces ?? []).filter { matches(assemblyItemName($0.id)) }
        let supports = (layout?.placements ?? []).filter { matches($0.title) }
        let devices = (currentTopology?.devices ?? []).filter {
            matches($0.name) || HardwareCatalog.reference($0.modelID)?.matchesCatalogSearch(query) == true
        }
        let fixtures = (layout?.facility?.fixtures ?? []).filter { matches($0.name) }
        let accessories = (layout?.accessories ?? []).filter {
            activeAssembly?.piece($0.id) == nil && matches(assemblyItemName($0.id))
        }
        let monitors = (layout?.rackMonitors ?? [:]).values.flatMap { $0 }.filter {
            activeAssembly?.piece($0.item) == nil && matches(assemblyItemName($0.item))
        }

        return List {
            if !placed.isEmpty {
                Section("Piezas colocadas") {
                    ForEach(placed) { piece in
                        assemblyPart(piece.id, title: assemblyItemName(piece.id), icon: "cube")
                    }
                }
            }
            if !supports.isEmpty {
                Section("Racks y puestos del proyecto") {
                    ForEach(supports) { support in
                        assemblyPart(.support(support.id), title: support.title,
                                     icon: support.kind == .rack ? "server.rack" : "desktopcomputer")
                    }
                }
            }
            if !devices.isEmpty {
                Section("Equipos del proyecto") {
                    ForEach(devices) { device in
                        let hardware = HardwareCatalog.reference(device.modelID)
                        assemblyPart(.device(device.id), title: device.name, icon: hardware?.group.symbol ?? "cube")
                    }
                }
            }
            if !fixtures.isEmpty {
                Section("Infraestructura Tier IV") {
                    ForEach(fixtures) { item in
                        assemblyPart(.infrastructure(item.id), title: item.name, icon: item.kind.symbol)
                    }
                }
            }
            if !accessories.isEmpty {
                Section("Accesorios por colocar") {
                    ForEach(accessories) { part in
                        assemblyPart(part.id, title: assemblyItemName(part.id), icon: "cube")
                    }
                }
            }
            if !monitors.isEmpty {
                Section("Monitores por colocar") {
                    ForEach(monitors) { monitor in
                        assemblyPart(monitor.item, title: assemblyItemName(monitor.item), icon: "display")
                    }
                }
            }
        }
        .overlay {
            if placed.isEmpty && supports.isEmpty && devices.isEmpty && fixtures.isEmpty && accessories.isEmpty && monitors.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Sin piezas", systemImage: "cube",
                                           description: Text("Añade un equipo desde el catálogo."))
                } else {
                    ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass",
                                           description: Text("Busca por nombre o modelo."))
                }
            }
        }
        .navigationTitle("Piezas del proyecto")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $projectPartSearch, prompt: "Buscar pieza")
    }

    private func catalogLabel(_ title: String, icon: String, detail: String? = nil) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint).accessibilityHidden(true)
        }
    }

    private func assemblyPart(_ item: LabARAssembly.Item, title: String, icon: String) -> some View {
        let placed = activeAssembly?.adjustmentPiece(item, topology: currentTopology) != nil
        return Button {
            guard activeAssembly != nil else { return }
            if placed { selectedAssemblyItem = item }
            else { assemblyCableRequest = .item(item) }
            assemblySheet = nil
        } label: {
            HStack {
                catalogLabel(title, icon: icon)
                Spacer()
                if placed {
                    Image(systemName: "checkmark").accessibilityLabel("Colocado")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func assemblyItemName(_ item: LabARAssembly.Item) -> String {
        switch item {
        case .support(let id): return currentLayout?.placements.first { $0.id == id }?.title ?? "Soporte"
        case .device(let id): return currentTopology?.devices.first { $0.id == id }?.name ?? "Equipo"
        case .infrastructure(let id):
            return currentLayout?.facility?.fixtures.first { $0.id == id }?.name ?? "Infraestructura"
        case .monitor(let id, let panel, _):
            let name = currentTopology?.devices.first { $0.id == id }?.name ?? "Servidor"
            return "Pantalla de \(name) · \(panel.rawValue)"
        case .extra(let model, _):
            if model == "battery-bank" { return "Banco de baterías" }
            if model == "test-desk" { return "Escritorio de pruebas" }
            return HardwareCatalog.reference(model)?.name ?? "Equipo"
        }
    }

    private var selectedAssemblyDevice: LabTopology.Device? {
        switch selectedAssemblyItem {
        case .device(let id), .monitor(let id, _, _): currentTopology?.devices.first { $0.id == id }
        default: nil
        }
    }

    private var selectedAssemblyDeviceSupport: LabPlacement? {
        guard let equipment = selectedAssemblyDevice else { return nil }
        return currentLayout?.placements.first { $0.id == equipment.placementID }
    }

    private func assemblyControls(_ assembly: LabARAssembly) -> AssemblyControls {
        let selectedDevice = selectedAssemblyDevice
        let rackSelected = if case .support = selectedAssemblyItem { selectedRack != nil } else { false }
        let recovery: AssemblyControls.Action?
        if restoringPlacement && !walkthrough.ready {
            recovery = .relocalize
        } else if !walkthrough.placementConfirmed && !assembly.pieces.isEmpty && !restoringPlacement {
            recovery = .setOrigin
        } else { recovery = nil }
        return AssemblyControls(
            projectName: activeSavedLab.map(savedLaboratories.name) ?? currentTopology?.name ?? "Cuarto escaneado",
            summary: currentTopology.map(equipmentSummary),
            saved: lastTopologySave,
            status: assemblyStatus,
            cableReviews: (assembly.showsCables ?? true) ? walkthrough.assemblyCableReviews : 0,
            instruction: assemblyPlacement.map(assemblyInstruction),
            hint: walkthrough.placementHint,
            rackFit: walkthrough.rackFit,
            onPlace: assemblyPlacement != nil && walkthrough.placementAvailable ? { walkthrough.confirmPreview?() } : nil,
            cableConfirmation: powerOutletConfirmation ?? assemblyCableConfirmation,
            powerRouteNeedsReview: selectedPowerRack.map { walkthrough.powerRouteReviews.contains($0) } ?? false,
            ports: assemblyPortControls(),
            direct: assemblyDirectControls(),
            editor: assemblyEdit.map { edit in
                AssemblyAdjustmentControls(
                    name: assemblyItemName(edit.piece.id), available: walkthrough.ready && scenePhase == .active,
                    onStep: stepAssemblyEdit, onFinish: finishAssemblyEdit, adjustments: edit.adjustments, initialMode: edit.initialMode
                )
            },
            routing: assemblyCableRequest.map { request in
                AssemblyCableControls(
                    title: assemblyCableTitle(request), onSelect: { applyAssemblyCableLevel($0, request: request) },
                    onCancel: { assemblyCableRequest = nil }
                )
            },
            tools: .init(
                selectedName: selectedAssemblyItem.map(assemblyItemName),
                isPlaced: selectedAssemblyItem.flatMap(assembly.piece) != nil,
                cableLevel: selectedAssemblyItem.map { assemblyLevel(for: $0, in: assembly) },
                canInspect: selectedDevice != nil,
                canOpenCLI: selectedDevice.map { !$0.modelID.hasPrefix("patch-") && !$0.isFanTray } ?? false,
                canEditNetwork: currentTopology != nil,
                canEditRack: selectedRack != nil,
                rackSelected: rackSelected,
                canAdjust: selectedAssemblyItem.flatMap(assembly.piece)?.monitorMount == nil,
                managesRackDevice: selectedAssemblyDeviceSupport?.kind == .rack,
                hasTrace: tracedLinkID != nil,
                available: walkthrough.phase == .placing || walkthrough.ready,
                showsCables: assembly.showsCables ?? true,
                recovery: recovery,
                powerMenu: selectedPowerRack.flatMap { rack in
                    currentLayout.map { AnyView(rackPowerMenu(rack, layout: $0, allowsOutlet: true)) }
                },
                onAction: handleAssemblyAction
            ))
    }

    private func assemblyDirectControls() -> AssemblyDirectControls? {
        if let rack = assemblyRackID, let placement = currentLayout?.placements.first(where: { $0.id == rack }) {
            return AssemblyDirectControls(title: placement.title, instruction: "Toca una unidad libre, un equipo o un costado del rack.",
                first: "Unidades", second: "Monitores", exit: "Listo",
                onFirst: { openRackTarget(rack, target: nil) },
                onSecond: { openRackTarget(rack, target: .side(.left)) },
                onExit: { assemblyRackID = nil; walkthrough.placementHint = nil },
                onLift: LabARAssembly.Adjustment.forARPlacement(placement).contains(.lift) ? {
                    assemblyRackID = nil
                    beginAssemblyAdjustment(.support(rack), initialMode: .lift)
                } : nil)
        }
        return nil
    }

    private func assemblyPortControls() -> AssemblyPortControls? {
        guard choosingAssemblyPorts else { return nil }
        let origin = assemblyPortRoute?.origin
        let medium = origin.flatMap { currentTopology?.medium(at: $0) }
        return AssemblyPortControls(
            origin: origin.map(assemblyPortTitle), destination: assemblyPortDestination.map(assemblyPortTitle),
            medium: medium?.title, hint: walkthrough.placementHint, tracking: mode == .room || walkthrough.ready,
            onPick: { openAssemblyPortPicker() },
            onSettings: { assemblySheet = .portSettings },
            onCancel: clearAssemblyPorts
        )
    }

    private func assemblyPortTitle(_ port: LabTopology.Port) -> String {
        "\(assemblyItemName(.device(port.deviceID))) · \(port.name)"
    }

    private func assemblyLevel(for item: LabARAssembly.Item, in assembly: LabARAssembly) -> LabARAssembly.CableLevel {
        if case .device(let id) = item, assembly.piece(item) == nil,
           let device = currentTopology?.devices.first(where: { $0.id == id }) {
            return assembly.level(for: item, on: .support(device.placementID))
        }
        return assembly.level(for: item)
    }

    private func assemblyCableTitle(_ request: AssemblyCableRequest) -> String {
        switch request {
        case .item(let item), .change(let item): "Cableado de \(assemblyItemName(item))"
        case .all: "Cableado de las piezas nuevas"
        }
    }

    private func applyAssemblyCableLevel(_ level: LabARAssembly.CableLevel, request: AssemblyCableRequest) {
        assemblyCableRequest = nil
        switch request {
        case .item(let item): assemblyPlacement = .item(item, level)
        case .all: assemblyPlacement = .all(level)
        case .change(let item):
            guard var assembly = activeAssembly else { return }
            assembly.setLevel(level, for: item)
            saveAssembly(assembly)
        }
    }

    private func handleAssemblyAction(_ action: AssemblyControls.Action) {
        assemblyCableConfirmation = nil
        powerOutletConfirmation = nil
        switch action {
        case .add:
            assemblySheet = .catalog
        case .network: assemblySheet = .network
        case .ports: startAssemblyConnection()
        case .rack:
            guard let rack = selectedRack else { return }
            assemblyRackID = rack.id
            selectedAssemblyItem = .support(rack.id)
            tracedLinkID = nil
            walkthrough.placementHint = nil
        case .rackDevices:
            assemblySheet = .rackDevices
        case .rackMonitors:
            assemblyRackTarget = nil
            assemblySheet = .rackMonitors
        case .clearTrace:
            waypointEdit = nil
            tracedLinkID = nil
            walkthrough.placementHint = nil
        case .placeAll: assemblyCableRequest = .all
        case .adjust:
            if let support = selectedAssemblyDeviceSupport, support.kind == .rack, let device = selectedAssemblyDevice {
                deviceSelection = device
            } else if let support = selectedAssemblyDeviceSupport, support.kind == .floor {
                beginAssemblyAdjustment(.support(support.id), initialMode: .move)
            } else if let item = selectedAssemblyItem {
                beginAssemblyAdjustment(item, initialMode: .move)
            }
        case .changeCableLevel:
            assemblyCableRequest = selectedAssemblyItem.map(AssemblyCableRequest.change)
        case .showCables(let shown):
            guard var assembly = activeAssembly else { return }
            assembly.showsCables = shown
            saveAssembly(assembly)
        case .inspect, .cli:
            guard let device = selectedAssemblyDevice else { return }
            if case .cli = action { opensDeviceCLI = true }
            deviceSelection = device
        case .remove:
            guard var assembly = activeAssembly, let item = selectedAssemblyItem else { return }
            assembly.unplace(item)
            do {
                if var project = workspaceProject {
                    let shared = project.layout.accessories?.contains(where: { $0.id.name == item.name }) == true
                        || project.layout.rackMonitors?.values.contains(where: { $0.contains { $0.item.name == item.name } }) == true
                    if shared {
                        project.layout.accessories?.removeAll { $0.id.name == item.name }
                        for rack in Array(project.layout.rackMonitors?.keys ?? [:].keys) {
                            project.layout.rackMonitors?[rack]?.removeAll { $0.item.name == item.name }
                        }
                        try saveWorkspaceProject(project, assembly: assembly)
                    } else { try persistAssembly(assembly) }
                } else { try persistAssembly(assembly) }
            } catch { showAssemblyError(error); return }
            selectedAssemblyItem = nil
        case .relocalize: startPreviewSession(reposition: false)
        case .setOrigin:
            if restoringPlacement { startPreviewSession(reposition: true) }
            assemblyPlacement = .origin
        case .cancel:
            if case .waypoint = assemblyPlacement { tracedLinkID = nil }
            assemblyPlacement = nil
            walkthrough.placementHint = nil
        }
    }

    private func beginAssemblyAdjustment(_ item: LabARAssembly.Item, initialMode: LabARAssembly.Adjustment) {
        guard let piece = activeAssembly?.adjustmentPiece(item, topology: currentTopology), piece.monitorMount == nil else { return }
        let support = if case .support(let id) = item { currentLayout?.placements.first { $0.id == id } } else { nil as LabPlacement? }
        assemblyEdit = .init(original: piece, piece: piece,
                             adjustments: LabARAssembly.Adjustment.forARPlacement(support), initialMode: initialMode)
    }

    private var assemblyStatus: String {
        if assemblyEdit != nil, walkthrough.ready { return "Ajusta la pieza y toca Listo para guardar." }
        if cableWaypointDragEnabled, let id = tracedLinkID, activeAssembly?.waypoints?[id]?.isEmpty == false {
            return "Arrastra un punto resaltado para ajustar el recorrido."
        }
        return switch walkthrough.phase {
        case .preparing, .starting: "Preparando cámara…"
        case .aligning: "Apunta a las mismas paredes o superficies. Muévete despacio hasta recuperar la ubicación."
        case .placing: "Elige qué colocar · tamaño real"
        case .ready: placementSavedInSession ? "Ubicación reconocida · cambios guardados" : "Mapeando la ubicación. Mueve el iPhone despacio."
        case .limited(let detail), .failed(let detail): detail
        case .interrupted: "Cámara interrumpida"
        }
    }

    private func assemblyInstruction(_ request: AssemblyPlacement) -> String {
        switch request {
        case .waypoint(_, let index):
            return "Apunta al suelo para ubicar el punto \(index + 1)."
        case .origin: return "Apunta al suelo para fijar el centro del montaje."
        case .all: return "Apunta al suelo para previsualizar el montaje."
        case .item(let item, _):
            if case .support(let id) = item, currentLayout?.placements.contains(where: { $0.id == id && $0.kind != .workstation }) == true {
                return "Apunta al piso para colocar \(assemblyItemName(item))."
            }
            return "Apunta a una superficie horizontal para colocar \(assemblyItemName(item))."
        }
    }

    private func placeAssembly(_ position: SIMD3<Float>, yaw: Float) {
        guard var assembly = activeAssembly, let request = assemblyPlacement, let layout = currentLayout else { return }
        guard canPlaceAssembly(at: position, yaw: yaw) else {
            walkthrough.placementHint = LabARAssembly.collisionHint
            return
        }
        switch request {
        case .waypoint(let id, let index):
            guard let project = previewProject else { return }
            var points = assembly.waypoints?[id] ?? []
            guard (0...points.count).contains(index), index < 4 else { return }
            let point = assembly.snappedWaypoint(position)
            if index == points.count { points.append(point) }
            else { points[index] = point }
            assembly.setWaypoints(points, for: id)
            do { try assembly.validateCableRoute(id, in: project) }
            catch { walkthrough.placementHint = error.localizedDescription; return }
        case .origin, .all, .item:
            assembly = proposedAssemblyPlacement(assembly, request: request, at: position, yaw: yaw, in: layout)
            if case .origin = request { assembly.clearPowerOutlets() }
            if case .all = request { assembly.syncInventory(in: layout, topology: currentTopology, at: position, yaw: yaw) }
            if case .item(.support, _) = request {
                assembly.syncInventory(in: layout, topology: currentTopology, placeMissing: false)
            }
        }
        do {
            if case .item(let item, _) = request, var project = workspaceProject {
                switch item {
                case .extra, .monitor:
                    let known = project.layout.accessories?.contains(where: { $0.id == item }) == true
                        || project.layout.rackMonitors?.values.contains(where: { $0.contains { $0.item == item } }) == true
                    if !known {
                        try project.registerAccessory(item)
                        try saveWorkspaceProject(project, assembly: assembly)
                    } else { try persistAssembly(assembly) }
                default: try persistAssembly(assembly)
                }
            } else { try persistAssembly(assembly) }
        } catch { walkthrough.placementHint = error.localizedDescription; return }
        if case .item(let item, _) = request { selectedAssemblyItem = item }
        assemblyPlacement = nil
    }

    private func proposedAssemblyPlacement(_ original: LabARAssembly, request: AssemblyPlacement,
                                           at position: SIMD3<Float>, yaw: Float, in layout: LabLayout) -> LabARAssembly {
        var assembly = original
        switch request {
        case .origin, .waypoint: break
        case .all(let level):
            let existing = Set(assembly.pieces.map(\.id))
            assembly.placeAll(in: layout, at: position, yaw: yaw)
            for piece in assembly.pieces where !existing.contains(piece.id) {
                assembly.setLevel(level, for: piece.id)
            }
        case .item(let item, let level):
            assembly.set(.init(id: item, position: position, yaw: assembly.piece(item)?.yaw ?? yaw))
            assembly.setLevel(level, for: item)
        }
        return assembly
    }

    private func canPlaceAssembly(at position: SIMD3<Float>, yaw: Float) -> Bool {
        guard let assembly = activeAssembly, let request = assemblyPlacement, let layout = currentLayout else { return true }
        if case .waypoint = request { return true }
        if case .origin = request { return true }
        let candidate = proposedAssemblyPlacement(assembly, request: request, at: position, yaw: yaw, in: layout)
        return !candidate.conflicts(with: assembly, in: layout, topology: currentTopology)
    }

    private func stepAssemblyEdit(_ mode: LabARAssembly.Adjustment, _ axes: SIMD2<Float>, _ seconds: Float) {
        guard walkthrough.ready, scenePhase == .active, let edit = assemblyEdit, edit.adjustments.contains(mode),
              var previous = activeAssembly, let layout = currentLayout else { return }
        var piece = edit.piece
        piece.adjust(mode, axes: axes, forward: walkthrough.focusDirection, seconds: seconds)
        guard piece != edit.piece else { return }
        previous.set(edit.piece)
        var candidate = previous
        candidate.set(piece)
        guard !candidate.conflicts(with: previous, in: layout, topology: currentTopology, allowingSeparation: true) else {
            walkthrough.placementHint = LabARAssembly.collisionHint
            return
        }
        if walkthrough.placementHint == LabARAssembly.collisionHint { walkthrough.placementHint = nil }
        assemblyEdit?.piece = piece
    }

    private var displayedAssembly: LabARAssembly? {
        guard var assembly = activeAssembly else { return nil }
        if let edit = waypointEdit, var points = assembly.waypoints?[edit.link], points.indices.contains(edit.index) {
            points[edit.index] = edit.value
            assembly.setWaypoints(points, for: edit.link)
        }
        guard let edit = assemblyEdit, edit.piece != edit.original else { return assembly }
        if assembly.piece(edit.piece.id) == nil {
            let level = assemblyLevel(for: edit.piece.id, in: assembly)
            assembly.setLevel(level, for: edit.piece.id)
        }
        assembly.set(edit.piece)
        return assembly
    }

    private func finishAssemblyEdit(_ commit: Bool) {
        if commit, let edit = assemblyEdit, edit.piece != edit.original, let assembly = displayedAssembly,
           var original = activeAssembly, let layout = currentLayout {
            original.set(edit.original)
            guard !assembly.conflicts(with: original, in: layout, topology: currentTopology) else {
                walkthrough.placementHint = LabARAssembly.collisionHint
                return
            }
            saveAssembly(assembly)
        }
        if walkthrough.placementHint == LabARAssembly.collisionHint { walkthrough.placementHint = nil }
        assemblyEdit = nil
    }

    private func saveAssembly(_ assembly: LabARAssembly) {
        do { try persistAssembly(assembly) }
        catch { showAssemblyError(error) }
    }

    private func persistAssembly(_ assembly: LabARAssembly) throws {
        try assemblyStore.save(assembly)
        activeAssembly = assembly
    }

    private func showAssemblyError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func loadProject<Value: Sendable>(
        _ progress: LocalizedStringKey, retryImport: Bool = false,
        build: @escaping @Sendable () throws -> Value, open: @escaping (Value) -> Void
    ) {
        guard projectProgress == nil else { return }
        projectProgress = progress
        Task {
            defer { projectProgress = nil }
            do {
                open(try await Self.prepareProject(build))
            } catch {
                self.retryImport = retryImport
                errorMessage = retryImport
                    ? "Usa el archivo .nexus.json generado por el exportador de Packet Tracer en el Mac. \(error.localizedDescription)"
                    : error.localizedDescription
                showError = true
            }
        }
    }

    @concurrent private static func prepareProject<Value: Sendable>(_ build: @Sendable () throws -> Value) async rethrows -> Value {
        try build()
    }

    private func setupCollaborationHandlers() {
        peerSession.onMessageReceived = { message in
            switch message {
            case .requestInitialState:
                if peerSession.isHost, let topology = currentTopology {
                    peerSession.sendReliable(.syncTopology(topology, scale: arScale.factor))
                }
            case .syncTopology(let topology, _):
                if !peerSession.isHost {
                    self.roomTopology = topology
                    self.showCables = true
                    if mode != .ar && canUseAR {
                        openPreviewAR(reposition: false)
                    }
                }
            case .setDevicePower(let deviceID, let isOn):
                if isOn {
                    poweredOff.remove(deviceID)
                } else {
                    poweredOff.insert(deviceID)
                }
            default:
                break
            }
        }
    }

    private func showPreview(_ project: LabProject, key: String) {
        pingSelection = nil
        activeSavedLab = nil
        arFocus = .all
        previewProject = project
        sceneZoom = 0
        previewSession?.pause()
        previewSession = nil
        mode = .room
        capture.pauseAR()
        poweredOff.removeAll()
        trackingMessage = nil
        tracedLinkID = nil
        selection = nil
        walkthrough = ARWalkthrough()
        UserDefaults.standard.set(key, forKey: "activeLaboratory")
    }

    private func openPreviewAR(reposition: Bool = false, focus: LabARFocus? = nil) {
        guard canUseAR, !requestingPreviewCamera else { return }
        requestingPreviewCamera = true
        Task {
            defer { requestingPreviewCamera = false }
            guard await authorizePreviewCamera() else { return }
            if let focus { arFocus = focus }
            startPreviewSession(reposition: reposition)
        }
    }

    private func authorizePreviewCamera() async -> Bool {
        guard await CaptureController.requestCameraAccess() else {
            cameraAccessDenied = true
            errorMessage = "Activa Cámara en Ajustes para volver a abrir el visor AR."
            showError = true
            return false
        }
        return true
    }

    private func configureTierCamera(_ configuration: ARWorldTrackingConfiguration) {
        configuration.sceneReconstruction = capture.supportsMesh && tierPhysicalOcclusion ? .mesh : []
        configuration.planeDetection = isTierMiniature ? [.horizontal] : [.horizontal, .vertical]
        let camera = configuration.videoFormat.captureDeviceType
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats.filter {
            $0.captureDeviceType == camera && $0.framesPerSecond == 30
        }
        let maximumWidth: CGFloat = isTierMiniature ? 1280 : 1920
        let preferred = formats.filter { $0.imageResolution.width <= maximumWidth }
            .max { $0.imageResolution.width < $1.imageResolution.width }
        if let format = preferred ?? formats.min(by: { $0.imageResolution.width < $1.imageResolution.width }) {
            configuration.videoFormat = format
        }
    }

    private func updateTierCamera() {
        guard mode == .ar, isTierPreview else { return }
        if let pendingTierConfiguration {
            configureTierCamera(pendingTierConfiguration)
            return
        }
        guard let previewSession, let configuration = previewSession.configuration as? ARWorldTrackingConfiguration else { return }
        configureTierCamera(configuration)
        configuration.initialWorldMap = nil
        previewSession.run(configuration)
    }

    private func startPreviewSession(reposition: Bool) {
        guard canUseAR, previewProject != nil || activeAssembly != nil else { return }
        let anchorName = placementAnchorName
        let trackingUsable = walkthrough.phase == .placing || walkthrough.ready
        restoringPlacement = false
        placementSavedInSession = false
        if reposition, trackingUsable, let session = previewSession, let tracked = session.configuration {
            if let anchorName {
                for anchor in session.currentFrame?.anchors ?? [] where anchor.name == anchorName {
                    session.remove(anchor: anchor)
                }
            }
            walkthrough = ARWalkthrough()
            cameraRevision += 1
            tracedLinkID = nil
            if mode != .ar { session.run(tracked) }
            mode = .ar
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if capture.supportsMesh { configuration.sceneReconstruction = .mesh }
        configuration.isCollaborationEnabled = true
        if isTierPreview { configureTierCamera(configuration) }
        if let anchorName, previewMapExists, !reposition {
            do {
                configuration.initialWorldMap = try CaptureController.loadPlacementMap(anchorName)
                restoringPlacement = true
                placementSavedInSession = true
            } catch {
                errorMessage = "El mapa guardado no pudo abrirse. Elige una nueva ubicación."
                showError = true
                if activeAssembly?.pieces.isEmpty == false { assemblyPlacement = .origin }
            }
        }
        walkthrough = ARWalkthrough()
        tracedLinkID = nil
        paintRoom = false
        capture.pauseAR()
        let session = previewSession ?? ARSession()
        if isTierPreview { pendingTierConfiguration = configuration }
        else { session.run(configuration, options: [.resetTracking, .removeExistingAnchors]) }
        previewSession = session
        cameraRevision += 1
        mode = .ar
    }

    private func savePlacement(session: ARSession, name: String) async {
        guard let frame = session.currentFrame, case .normal = frame.camera.trackingState,
              [.mapped, .extending].contains(frame.worldMappingStatus),
              frame.anchors.contains(where: { $0.name == name }) else { return }
        do {
            let map = try await session.currentWorldMap()
            try Task.checkCancellation()
            guard session === previewSession, placementAnchorName == name, !placementSavedInSession,
                  map.anchors.contains(where: { $0.name == name }) else { return }
            try CaptureController.writeWorldMap(map, to: CaptureController.placementMapURL(name))
            placementSavedInSession = true
        } catch {
            // The mapping task retries once tracking has more views of the room.
        }
    }

    private func applyTemplate(openAR: Bool, home: Bool = false) {
        guard let room = capture.room, let measured = capture.layout else { return }
        loadProject("Ajustando plantilla al cuarto…", build: {
            try home ? LabDemo.homeLab(in: (room, measured)) : LabDemo.dataCenter(in: (room, measured))
        }) { project in
            previewSession?.pause()
            previewSession = nil
            previewProject = nil
            activeSavedLab = nil
            arFocus = .all
            appliedTemplate = project
            mode = .room
            paintRoom = false
            tracedLinkID = nil
            selection = nil
            sceneZoom = 0
            poweredOff.removeAll()
            cameraRevision += 1
            UserDefaults.standard.set(home ? "scan-home" : "scan-tier", forKey: "activeLaboratory")
            if openAR && canUseAR { resumeRoomAR() }
        }
    }

    private var startScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "camera").font(.largeTitle.weight(.light)).foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Explora un laboratorio").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("Prueba una red en la demo, explora las plantillas o escanea tu cuarto para recorrerlo en realidad aumentada.")
                    .font(.body).foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    Button(action: openVLANDemo) {
                        Label("Abrir demo de VLAN y ping", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                    Button { showLabCatalog = true } label: {
                        Label("Catálogo UNSM", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                    Button(action: openHomeLab) {
                        Label("Abrir HomeLab Proxmox", systemImage: "server.rack")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                    if capture.isSupported {
                        Button { beginCapture() } label: {
                            Label("Escanear cuarto", systemImage: "camera")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(capture.isBusy)
                    }
                    Button(action: openDataCenter) {
                        Label("Abrir plantilla Tier IV", systemImage: "building.2")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }
                if !capture.isSupported {
                    Text("El escaneo del cuarto requiere LiDAR.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("El escaneo se guarda en este dispositivo.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func scanner(view: RoomCaptureView) -> some View {
        VStack(spacing: 0) {
            CapturePreview(view: view, onStarted: { capture.previewStarted() })
                .overlay {
                    if capture.phase == .processing {
                        ProgressView("Creando tu laboratorio…")
                            .padding(24).background(.regularMaterial, in: .rect(cornerRadius: 16))
                    }
                }
            VStack(spacing: 12) {
                if let status = capture.cameraStatusString {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Recorre paredes, puertas y suelo lentamente.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Cancelar", role: .cancel) { capture.cancel() }
                        .frame(minHeight: 44)
                    Spacer(minLength: 12)
                    Button("Terminar y generar") { capture.finish() }
                        .buttonStyle(.borderedProminent).frame(minHeight: 44)
                        .disabled(capture.phase != .capturing)
                }
            }.padding().background(.bar)
        }
    }

    private func workspace(room: RoomStructure, layout: LabLayout, topology: LabTopology?) -> AnyView {
        let layout = mode == .room ? visible3DLayout ?? layout : layout
        let placementPreview = mode == .room ? preview3DPlacement : nil
        let footprint = arFootprint(in: layout, topology: topology)
        let session = previewProject == nil && activeAssembly == nil ? capture.arSession : previewSession
        let ping = scenePing(in: topology)
        let packetJourney = ping.flatMap { diagnosis in topology.flatMap { LabPacketJourney(diagnosis: diagnosis, topology: $0) } }
        let identity = LaboratorySceneID(room: room.roomID, mode: mode,
                                         session: mode == .ar ? session.map(ObjectIdentifier.init) : nil,
                                         roomRevision: mode == .room ? cameraRevision + sceneReload : 0)
        // The navigation stack embeds this viewer in three branches. Erase its nested overlay type at that boundary.
        return AnyView(VStack(spacing: 0) {
            if !fullScreen3D && activeAssembly == nil { workspaceHeader(layout: layout, topology: topology) }
            LabSceneView(
                room: room, layout: layout, arSession: session, mode: mode,
                paintRoom: mode == .room || paintRoom, fullRoomWalls: fullRoomWalls,
                poweredOff: effectivePoweredOff,
                selection: $selection, trackingMessage: $trackingMessage,
                onSelectHardware: { hardwareSelection = HardwareCatalog.reference($0) },
                topology: topology, showCables: activeAssembly.map { tracedLinkID != nil || ($0.showsCables ?? true) } ?? showCables,
                visibleCableIDs: mode == .room ? cableFilter.flatMap { topology?.visibleCableIDs(for: $0) } : nil,
                selectedLinkID: linkSelection?.id ?? tracedLinkID,
                pingLinks: Set(ping?.path?.links.map(\.id) ?? []),
                // During the fair challenge the red segment would reveal the answer; the packet is the only hint.
                pingBlockedLink: fairChallenge == nil ? ping?.blockedLink?.id : nil,
                packetJourney: packetJourney,
                onPacketHop: fairMode ? { (hop: Int) in packetHop = hop } : nil,
                packetConcealsFailure: fairChallenge != nil,
                onSelectDevice: { id in
                    if fairChallenge != nil { answerFairChallenge(deviceIDs: [id]) }
                    else { deviceSelection = topology?.devices.first { $0.id == id } }
                },
                onSelectLink: { id in
                    if fairChallenge != nil {
                        if let link = topology?.links.first(where: { $0.id == id }) {
                            answerFairChallenge(deviceIDs: [link.fromDeviceID, link.toDeviceID])
                        }
                    } else { inspect(.link(id), topology: topology, layout: layout) }
                },
                onInspectPort: { port in
                    if fairChallenge != nil { answerFairChallenge(deviceIDs: [port.deviceID]) }
                    else { inspectedPort = port }
                },
                onInspectPDU: { inspectedPDU = .init(rack: $0, circuit: $1, outlet: $2) },
                sceneScale: mode == .ar && activeAssembly == nil ? arScale.factor : 1,
                arPlacementRequired: (previewProject != nil || activeAssembly != nil) && mode == .ar && !usesCapturedARSession,
                placementRevision: cameraRevision, zoomStep: sceneZoom,
                orbitReset: orbitReset,
                focusDeviceID: deviceSelection?.id,
                inspectionDestination: inspectionDestination, inspectionRevision: inspectionRevision,
                catalystDetail: catalystInspection.detail.flatMap { $0.deviceID == inspectedCatalystID ? $0 : nil },
                walkthrough: mode == .ar ? walkthrough : nil,
                isForeground: scenePhase == .active && travelMode == nil,
                worldPlacementName: mode == .ar ? placementAnchorName : nil,
                restoresWorldPlacement: restoringPlacement,
                arFootprint: footprint, arPlacementOnFloor: previewUsesFloor || footprint?.rack != nil || footprint?.requiresFloor == true,
                lockedDeviceID: lockedDeviceID, showTraffic: simulationEnabled && showTraffic && ping == nil,
                showRackAirflow: showRackAirflow, negotiatingLink: negotiatingLink,
                physicalOcclusion: isTierPreview ? tierPhysicalOcclusion : physicalOcclusion,
                monitorConfigurations: baseTopology.map(operations.monitors) ?? [:],
                arFocus: arFocus, showARContext: showARContext, assembly: displayedAssembly,
                selectedAssemblyItem: selectedAssemblyItem, assemblyPlacementRequested: assemblyPlacement != nil,
                assemblyEditID: waypointEdit?.id ?? assemblyEdit?.id,
                assemblyRackID: assemblyRackID,
                assemblyWaypointsEditable: cableWaypointDragEnabled,
                assemblyPortsEnabled: assemblyPortPickingAvailable,
                assemblyPortSource: assemblyPortRoute?.origin,
                assemblyPortDestination: assemblyPortDestination,
                selectableScenePorts: choosingAssemblyPorts ? sceneConnectionPorts : nil,
                equipmentSurface: equipmentPlacement?.surface,
                equipmentPreview: equipmentPlacement?.choice?.outline,
                powerOutletRack: powerOutletRack,
                directPowerOutlets: directPowerOutlets,
                placementPreview: placementPreview,
                onOrbitHeading: mode == .room ? { orbit3DHeading = $0 } : nil,
                onCableReviews: mode == .room ? { cableReviews3D = $0 } : nil,
                onAssemblySelect: selectAssemblyPiece,
                onAssemblyCanPlace: canPlaceAssembly,
                onAssemblyPosition: placeAssembly,
                onAssemblyRackTarget: { openRackTarget($0, target: $1) },
                onAssemblyWaypoint: handleWaypointGesture,
                onAssemblyPort: handleAssemblyPort,
                onPowerOutlet: hitPowerOutlet,
                onEquipmentTarget: chooseEquipmentTarget,
                peerSession: peerSession)
                .id(identity)
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                .ignoresSafeArea(.container, edges: fullScreen3D ? .all : [])
                .onChange(of: selection) {
                    // In the challenge, touching the rack or desk that holds the failed device also counts.
                    guard fairChallenge != nil, let placement = selection else { return }
                    selection = nil
                    answerFairChallenge(placementID: placement.id)
                }
                .onChange(of: mode) {
                    if fairMode { closeFairMode() }
                    if assistantOpen { closeAssistant() }
                }
                .onChange(of: layout3DScope) {
                    if fairMode { closeFairMode() }
                    if assistantOpen { closeAssistant() }
                }
                .overlay {
                    if mode == .room, let trackingMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(trackingMessage, systemImage: "exclamationmark.circle").font(.callout)
                            Button("Reintentar vista 3D", systemImage: "arrow.clockwise") {
                                self.trackingMessage = nil
                                sceneReload += 1
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12).modifier(ViewerSurface(radius: 14)).padding(12)
                    }
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 6) {
                        if peerSession.status.isConnected {
                            HStack(spacing: 8) {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Text(peerSession.isHost ? "Anfitrión • Conectado a \(peerSession.connectedPeerName ?? "")" : "Invitado • Conectado a \(peerSession.connectedPeerName ?? "")")
                                    .font(.caption2.weight(.semibold))
                                if peerSession.isPresentationOnly && !peerSession.isHost {
                                    Text("(Solo lectura)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .modifier(ViewerSurface(radius: 12))
                            .onTapGesture { showCollaborationSheet = true }
                        }
                        if let alert = peerSession.lastActionAlert {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundStyle(.orange)
                                Text(alert)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .modifier(ViewerSurface(radius: 14))
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .task(id: alert) {
                                try? await Task.sleep(for: .seconds(3.5))
                                if peerSession.lastActionAlert == alert {
                                    peerSession.lastActionAlert = nil
                                }
                            }
                        }
                        if let assemblyCableConfirmation, mode == .ar {
                            ViewThatFits(in: .horizontal) {
                                Label(assemblyCableConfirmation, systemImage: "checkmark.circle.fill")
                                    .fixedSize(horizontal: true, vertical: false)
                                Label("Cable conectado", systemImage: "checkmark.circle.fill")
                            }
                            .accessibilityLabel(assemblyCableConfirmation)
                            .font(.caption.weight(.semibold)).padding(8).modifier(ViewerSurface(radius: 12))
                        }
                    }
                    .padding(8)
                }
                .overlay(alignment: .top) {
                    if mode == .room {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                if !fullScreen3D && placementPreview == nil {
                                    if let assemblyCableConfirmation {
                                        ViewThatFits(in: .horizontal) {
                                            Label(assemblyCableConfirmation, systemImage: "checkmark.circle.fill")
                                                .fixedSize(horizontal: true, vertical: false)
                                            Label("Cable conectado", systemImage: "checkmark.circle.fill")
                                        }
                                        .accessibilityLabel(assemblyCableConfirmation)
                                        .font(.caption.weight(.semibold)).padding(8).modifier(ViewerSurface(radius: 12))
                                    } else if let ping, !fairMode {
                                        ScenePingStatus(diagnosis: ping) { pingSelection = nil }
                                    } else if !simulationEnabled {
                                        Label("Simulación en pausa", systemImage: "pause.circle")
                                            .font(.caption).padding(10).modifier(ViewerSurface(radius: 14))
                                    } else if showTraffic && showCables && topology?.links.isEmpty == false {
                                        LabTrafficLegend().allowsHitTesting(false)
                                    }
                                    if showCables && cableReviews3D > 0 {
                                        Label("Revisar cableado (\(cableReviews3D))", systemImage: "exclamationmark.triangle")
                                            .font(.caption).padding(8).modifier(ViewerSurface(radius: 12))
                                    }
                                }
                                if placementPreview == nil, let status = catalystViewerStatus {
                                    status.font(.caption).padding(8).modifier(ViewerSurface(radius: 12))
                                }
                            }
                            Spacer(minLength: 0)
                            if fullScreen3D && placementPreview == nil && equipmentPlacement == nil && !choosingAssemblyPorts {
                                if let topology { cableControl(topology, layout: layout) }
                                if canSearchViewer { viewerSearchButton.modifier(ViewerSurface(radius: 24)) }
                            }
                            if placementPreview == nil && equipmentPlacement == nil && !choosingAssemblyPorts,
                               topology?.devices.isEmpty == false { connectInSceneButton }
                            if !fullScreen3D && canSelectARScale {
                                ARScaleButton(scale: arScale) { showARScales = true }
                                    .layoutPriority(1)
                            }
                            if placementPreview != nil { cameraGestureControl }
                            fullScreenControl
                        }
                        .padding(12)
                    }
                }
                .overlay(alignment: .bottom) {
                    if mode == .room, let placement = preview3DPlacement {
                        VStack(alignment: .leading, spacing: 4) {
                            if let layout3DMessage {
                                Text(layout3DMessage).font(.caption).foregroundStyle(.secondary)
                            } else if showCables && cableReviews3D > 0 {
                                Label("Revisar cableado (\(cableReviews3D))", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            AssemblyAdjustmentControls(name: placement.title, available: scenePhase == .active,
                                                       onStep: adjust3DPlacement, onFinish: finish3DPlacement,
                                                       commitTitle: "Guardar", adjustments: LabARAssembly.Adjustment.forARPlacement(placement))
                            sync3DControls
                        }
                        .padding(12)
                        .frame(maxWidth: 344, alignment: .leading)
                        .modifier(ViewerSurface(radius: 18, material: .thick))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: verticalSizeClass == .compact ? .leading : .center)
                    } else if mode == .room && assistantOpen && equipmentPlacement == nil && !choosingAssemblyPorts {
                        LabAssistantPanel(model: assistant, onClose: { assistantOpen = false })
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: verticalSizeClass == .compact ? .leading : .center)
                    } else if mode == .room && fairMode && equipmentPlacement == nil && !choosingAssemblyPorts {
                        FairModePanel(
                            journey: packetJourney, reached: packetHop, challenge: fairChallenge, outcome: fairOutcome,
                            scores: fairScores, message: fairMessage,
                            onSendPacket: sendFairPacket, onStartChallenge: startFairChallenge,
                            onGiveUp: { finishFairChallenge(timedOut: true) },
                            onTimeout: {
                                if let fairChallenge, fairChallenge.remaining(at: .now) <= 0.1 { finishFairChallenge(timedOut: true) }
                            },
                            onSaveScore: saveFairScore,
                            onDismissOutcome: { fairOutcome = nil },
                            onClose: closeFairMode,
                            onAssistant: openAssistant)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: verticalSizeClass == .compact ? .leading : .center)
                    } else if mode == .room && !fullScreen3D && equipmentPlacement == nil && !choosingAssemblyPorts {
                        HStack {
                            Button { assemblySheet = .equipment } label: {
                                Label("Editar laboratorio", systemImage: "plus.rectangle.on.rectangle")
                                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                            }.buttonStyle(ViewerPressStyle()).modifier(ViewerSurface(radius: 24))
                            if let topology { cableControl(topology, layout: layout) }
                            Button { openTravel(.walk) } label: {
                                Label("Recorrido 3D", systemImage: "figure.walk")
                                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                            }.buttonStyle(ViewerPressStyle()).modifier(ViewerSurface(radius: 24))
                            if topology?.links.isEmpty == false {
                                Button(action: openFairMode) {
                                    Label("Modo feria", systemImage: "sparkles")
                                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                                }.buttonStyle(ViewerPressStyle()).modifier(ViewerSurface(radius: 24))
                            }
                            if topology?.devices.isEmpty == false {
                                Button(action: openAssistant) {
                                    Label("Hablar con Nexus", systemImage: "waveform")
                                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                                }.buttonStyle(ViewerPressStyle()).modifier(ViewerSurface(radius: 24))
                            }
                            if !layout.placements.isEmpty {
                                Button { choose3DPlacement = true } label: {
                                    Label("Organizar en 3D", systemImage: "move.3d")
                                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                                }.buttonStyle(ViewerPressStyle()).modifier(ViewerSurface(radius: 24))
                            }
                            Spacer(minLength: 8)
                            orbitControls
                        }
                        .padding(16)
                    }
                }
                .overlay {
                    if mode == .ar && activeAssembly == nil {
                        AimingReticle(walkthrough: walkthrough).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .overlay {
                    if let equipmentPlacement {
                        EquipmentPlacementControls(name: equipmentPlacement.device.name, surface: equipmentPlacement.surface,
                            ready: mode == .room || walkthrough.ready, selected: equipmentPlacement.choice != nil,
                            hint: equipmentPlacement.hint, confirm: confirmEquipmentPlacement, cancel: { self.equipmentPlacement = nil })
                    } else if let ports = assemblyPortControls() {
                        ports.padding(12).modifier(ViewerSurface(radius: 18, material: .thick)).padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    } else if mode == .ar, let rack = powerOutletRack {
                        ARPowerOutletControls(name: assemblyItemName(rack), ready: walkthrough.ready,
                                              hint: powerOutletHint, cancel: cancelPowerOutlet)
                    } else if mode == .ar, let assembly = activeAssembly {
                        assemblyControls(assembly)
                    } else if mode == .ar {
                        WalkthroughHUD(
                            walkthrough: walkthrough, layout: layout, topology: topology,
                            worldMapped: previewProject == nil || isHomeFloorPlacement,
                            manualHome: isHomeFloorPlacement,
                            usesFloor: previewUsesFloor || footprint?.rack != nil,
                            mapSaved: previewProject != nil ? placementSavedInSession : capture.hasSavedWorldMap,
                            scale: arScale, space: previewSpace,
                            onSelectScale: canSelectARScale ? { showARScales = true } : nil,
                            traceID: showCables ? tracedLinkID : nil, showVirtualWalls: paintRoom,
                            focusTargets: LabFocusTarget.inventory(topology, in: layout).filter { target in
                                arFocus == .all || showARContext
                                    || topology?.devices.first(where: { $0.id == target.id }).map(arFocus.includes) == true
                            },
                            lockedDeviceID: $lockedDeviceID, showTraffic: trafficBinding, showCables: showCables,
                            onInspect: { inspect($0, topology: topology, layout: layout) },
                            onDismissTrace: { tracedLinkID = nil }, onDetails: { linkSelection = $0 },
                            ping: ping, onDismissPing: { pingSelection = nil },
                            onRealign: (previewProject != nil ? previewMapExists : capture.hasSavedWorldMap) ? {
                                if previewProject != nil { openPreviewAR(reposition: false) }
                                else { resumeRoomAR(realign: true) }
                            } : nil,
                            onReposition: previewProject != nil ? { openPreviewAR(reposition: true) } : nil,
                            catalystStatus: catalystViewerStatus,
                            powerOutletConfirmation: powerOutletConfirmation,
                            powerRouteNeedsReview: !walkthrough.powerRouteReviews.isEmpty)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: powerOutletRack != nil)
                .sensoryFeedback(.success, trigger: powerOutletConfirmation) { _, current in current != nil }
                .overlay {
                    if mode == .ar, let id = inspectionDestination?.deviceID,
                       let device = topology?.devices.first(where: { $0.id == id }) {
                        ARSearchMarker(walkthrough: walkthrough, name: device.name)
                            .allowsHitTesting(false)
                    }
                }
                .task(id: mode == .ar && pendingTierConfiguration != nil && scenePhase == .active ? cameraRevision : nil) {
                    runPendingTierCamera()
                }
                .task(id: mode == .ar && previewProject == nil && activeAssembly == nil && scenePhase == .active ? room.roomID : nil) {
                    guard mode == .ar, previewProject == nil, activeAssembly == nil, scenePhase == .active else { return }
                    while !Task.isCancelled && !capture.hasSavedWorldMap {
                        await capture.saveWorldMapIfReady()
                        if capture.hasSavedWorldMap { break }
                        do { try await Task.sleep(for: .seconds(2)) } catch { break }
                    }
                }
                .task(id: shouldSavePlacement(hasFacility: layout.facility != nil) ? cameraRevision : nil) {
                    guard let name = placementAnchorName, walkthrough.placementConfirmed, mode == .ar,
                          scenePhase == .active, let session = previewSession else { return }
                    if isTierMiniature {
                        // Let the renderer finish uploading the scene before serializing a spatial map.
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    }
                    while !Task.isCancelled && !placementSavedInSession {
                        await savePlacement(session: session, name: name)
                        if placementSavedInSession { break }
                        do { try await Task.sleep(for: .seconds(2)) } catch { break }
                    }
                }
            if mode == .room && !fullScreen3D && (verticalSizeClass != .compact || layout.placements.isEmpty) {
                workspaceFooter(layout: layout)
            }
        })
    }

    private func runPendingTierCamera() {
        guard mode == .ar, scenePhase == .active, let configuration = pendingTierConfiguration,
              let session = previewSession else { return }
        pendingTierConfiguration = nil
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func shouldSavePlacement(hasFacility: Bool) -> Bool {
        placementAnchorName != nil && walkthrough.placementConfirmed && mode == .ar && scenePhase == .active
            && (!hasFacility || activeAssembly != nil || !walkthrough.renderedLinks.isEmpty)
    }

    private func workspaceHeader(layout: LabLayout, topology: LabTopology?) -> some View {
        let racks = layout.placements.filter { $0.kind == .rack }.count
        let desks = layout.placements.filter { $0.kind == .workstation }.count
        let rackLabel = "\(racks) \(racks == 1 ? "rack" : "racks")"
        let deskLabel = "\(desks) \(desks == 1 ? "puesto" : "puestos")"
        let focusedName: String?
        switch arFocus {
        case .device(let id): focusedName = topology?.devices.first { $0.id == id }?.name
        case .placement(let id): focusedName = layout.placements.first { $0.id == id }?.title
        case .fixture(let id): focusedName = layout.facility?.fixtures.first { $0.id == id }?.name
        case .all: focusedName = nil
        }
        let title = focusedName ?? activeSavedLab.map(savedLaboratories.name)
            ?? (isHomeLab ? LabDemo.homeName : layout.facility != nil ? "Plantilla Tier IV"
                : previewProject == nil ? "Cuarto escaneado" : topology?.name ?? "Laboratorio virtual")
        let area = "\(layout.area.formatted(.number.precision(.fractionLength(0...1)))) m²"
        let summary = topology.map(equipmentSummary) ?? "\(area) · \(rackLabel) · \(deskLabel)"
        let saved = topology == nil ? nil : lastTopologySave
        return Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 12) {
                    workspaceContext(title, summary: summary, saved: saved)
                    Spacer(minLength: 0)
                    if mode == .room && layout.facility != nil && previewProject != nil && capture.isSupported {
                        Button(action: openTemplateWalk) {
                            Label("Recorrer mi cuarto en AR", systemImage: "figure.walk.motion")
                                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.bordered)
                    }
                    if isHomeLab { homeActions }
                    workspacePicker
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        workspaceContext(title, summary: summary, saved: saved).fixedSize()
                        Spacer(minLength: 0)
                        workspacePicker
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        workspaceContext(title, summary: summary, saved: saved)
                        workspacePicker
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, verticalSizeClass == .compact ? 4 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
    }

    private func workspaceContext(_ title: String, summary: String, saved: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(summary).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            if let saved {
                Text(saved).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("lab.workspace.saved")
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var workspacePicker: some View {
        if !canUseAR {
            if !dynamicTypeSize.isAccessibilitySize {
                Label("3D", systemImage: "cube").font(.subheadline.weight(.medium))
            }
        } else if verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize {
            viewPicker.pickerStyle(.menu)
        } else {
            viewPicker.pickerStyle(.segmented).frame(minWidth: 134, idealWidth: 165, maxWidth: 220)
        }
    }

    private var fullScreenControl: some View {
        Button { fullScreen3D.toggle() } label: {
            Label(fullScreen3D ? "Salir de pantalla completa" : "Pantalla completa",
                  systemImage: fullScreen3D ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(ViewerPressStyle())
        .modifier(ViewerSurface(radius: 24))
        .accessibilityActions {
            if fullScreen3D {
                Button("Acercar equipos") { zoomOrbit(by: 1) }
                Button("Alejar equipos") { zoomOrbit(by: -1) }
                Button("Restablecer encuadre", action: resetOrbit)
            }
        }
    }

    private func zoomOrbit(by step: Int) {
        sceneZoom = min(12, max(-8, sceneZoom + step))
    }

    private var orbitControls: some View {
        HStack(spacing: 0) {
            Button { zoomOrbit(by: -1) } label: {
                Label("Alejar equipos", systemImage: "minus").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }.disabled(sceneZoom <= -8)
            Divider().frame(height: 18)
            Button { zoomOrbit(by: 1) } label: {
                Label("Acercar equipos", systemImage: "plus").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }.disabled(sceneZoom >= 12)
            Divider().frame(height: 18)
            Button(action: resetOrbit) {
                Label("Restablecer encuadre", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .buttonStyle(ViewerPressStyle())
        .modifier(ViewerSurface(radius: 24))
    }

    private var cameraGestureControl: some View {
        Button { showCameraGestures = true } label: {
            Label("Gestos de cámara", systemImage: "hand.draw")
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
        }
        .buttonStyle(ViewerPressStyle())
        .modifier(ViewerSurface(radius: 24))
        .popover(isPresented: $showCameraGestures) {
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Gestos de cámara").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("1 dedo · Orbitar")
                    Text("2 dedos · Desplazar, pellizcar o girar")
                    Text("3 dedos · Órbita precisa")
                    Text("4 dedos · Restablecer encuadre")
                    orbitControls
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
                .padding(16)
                .frame(idealWidth: 280)
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func cableControl(_ topology: LabTopology, layout: LabLayout) -> some View {
        LabCableFilterMenu(topology: topology, layout: layout, filter: $cableFilter, showsCables: $showCables) {
            tracedLinkID = nil
            pingSelection = nil
        }
    }

    private var connectInSceneButton: some View {
        Button(action: startAssemblyConnection) {
            Label("Conectar puertos", systemImage: "cable.connector")
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
        }
        .buttonStyle(ViewerPressStyle())
        .modifier(ViewerSurface(radius: 24))
        .accessibilityIdentifier("lab.scene.connect")
    }

    private func resetOrbit() {
        inspectionDestination = nil
        lockedDeviceID = nil
        tracedLinkID = nil
        mode = .room
        sceneZoom = 0
        orbitReset += 1
    }

    private func openTemplateWalk() {
        if capture.room == nil || (capture.arSession == nil && !capture.hasSavedWorldMap) { beginCapture() }
        else { applyTemplate(openAR: true) }
    }

    private var homeActions: some View {
        Menu {
            if canUseAR && previewProject != nil {
                Button(isHomeFloorPlacement ? (previewMapExists ? "Volver a la ubicación guardada" : "Elegir punto en el piso")
                       : "Colocar maqueta AR",
                       systemImage: "location.circle") { openPreviewAR() }
            }
            if capture.isSupported {
                Button("Escanear un cuarto", systemImage: "camera") { beginCapture() }
                if capture.room != nil {
                    Button("Usar el cuarto escaneado", systemImage: "square.dashed.inset.filled") { applyTemplate(openAR: canUseAR, home: true) }
                }
            }
            Button("Guía de montaje", systemImage: "list.number") { showHomeGuide = true }
        } label: {
            Group {
                if verticalSizeClass == .compact {
                    Label("Montar HomeLab", systemImage: "wrench.and.screwdriver").labelStyle(.iconOnly)
                } else {
                    Label("Montar HomeLab", systemImage: "wrench.and.screwdriver").labelStyle(.titleAndIcon)
                }
            }.frame(minWidth: 44, minHeight: 36)
        }.buttonStyle(.bordered)
    }

    private func workspaceFooter(layout: LabLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if baseTopology?.operationsProfile == LabDemo.vlanProfile {
                Button { showPingDiagnostics = true } label: {
                    Label("Probar ping", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
            } else if isHomeLab {
                HStack { homeActions; Spacer(minLength: 0) }
            } else if layout.facility != nil && previewProject != nil && capture.isSupported {
                Button(action: openTemplateWalk) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk.motion").accessibilityHidden(true)
                        Text("Recorrer mi cuarto en AR").lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else if layout.facility != nil && previewProject != nil {
                Label("Para recorrer la plantilla se requiere un iPhone con LiDAR.", systemImage: "iphone")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if !canUseAR && previewProject == nil && capture.isSupported {
                Text("Escanea el cuarto para recorrerlo en AR.").font(.footnote).foregroundStyle(.secondary)
            }
            if (!dynamicTypeSize.isAccessibilitySize || layout.placements.isEmpty), let warning = layout.warnings.first {
                Label(warning, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(Color(uiColor: .systemBackground))
    }

    private var locateTitle: String { mode == .ar ? "Marcar en AR" : "Ver en 3D" }

    private var inspectedCatalystID: String? {
        if let deviceSelection {
            return !opensDeviceCLI && deviceSelection.visualModelID == Catalyst2960Asset.modelID ? deviceSelection.id : nil
        }
        guard let destination = inspectionDestination, destination.linkID == nil, destination.port == nil,
              currentTopology?.devices.contains(where: {
                  $0.id == destination.deviceID && $0.visualModelID == Catalyst2960Asset.modelID
              }) == true else { return nil }
        return destination.deviceID
    }

    private var catalystInspectionRequest: CatalystInspectionRequest {
        CatalystInspectionRequest(deviceID: inspectedCatalystID, scope: layout3DScope, attempt: catalystInspection.attempt)
    }

    private var catalystViewerStatus: Catalyst2960Status? {
        guard deviceSelection == nil, let id = inspectedCatalystID,
              catalystInspection.phase(for: id) != .ready else { return nil }
        return Catalyst2960Status(inspection: catalystInspection, deviceID: id)
    }

    private var viewerSearchDevices: [LabTopology.Device] {
        guard let topology = currentTopology else { return [] }
        guard mode == .ar else { return topology.devices }
        guard walkthrough.ready, assemblyPlacement == nil, assemblyEdit == nil, !choosingAssemblyPorts,
              assemblyCableRequest == nil, waypointEdit == nil else { return [] }
        if let assembly = activeAssembly {
            let placed = Set(assembly.pieces.map(\.id))
            return topology.devices.filter { placed.contains(.device($0.id)) || placed.contains(.support($0.placementID)) }
        }
        return topology.devices.filter { arFocus == .all || showARContext || arFocus.includes($0) }
    }

    private var canSearchViewer: Bool { preview3DPlacement == nil && !viewerSearchDevices.isEmpty }

    private var viewerSearchButton: some View {
        Button("Buscar equipo o puerto", systemImage: "magnifyingglass") { showingViewerSearch = true }
            .labelStyle(.iconOnly)
            .frame(minWidth: fullScreen3D ? 44 : nil, minHeight: fullScreen3D ? 44 : nil)
    }

    @ViewBuilder private var viewerSearchSheet: some View {
        if let layout = currentLayout {
            let clear: (() -> Void)? = inspectionDestination == nil ? nil : { clearViewerTarget() }
            LabViewerSearch(devices: viewerSearchDevices, layout: layout, onSelect: selectViewerSearchResult, onClear: clear)
        }
    }

    private func selectViewerSearchResult(_ destination: LabInspectionDestination) {
        tracedLinkID = nil
        locateInScene(destination)
    }

    private func clearViewerTarget() {
        if let id = inspectionDestination?.deviceID, selectedAssemblyItem == .device(id) { selectedAssemblyItem = nil }
        inspectionDestination = nil
        lockedDeviceID = nil
        walkthrough.searchMarker = nil
    }

    private func locateInScene(_ destination: LabInspectionDestination) {
        if mode == .ar {
            walkthrough.searchMarker = nil
            if activeAssembly != nil { selectAssemblyPiece(.device(destination.deviceID)) }
        }
        inspectionDestination = destination
        inspectionRevision += 1
        lockedDeviceID = destination.deviceID
        selection = nil
        if let linkID = destination.linkID {
            showCables = true
            if mode == .room { cableFilter = nil }
            tracedLinkID = linkID
        }
        deviceSelection = nil
        linkSelection = nil
        inspectedPort = nil
        showOptions = false
    }

    private func inspect(_ target: LabSceneTarget, topology: LabTopology?, layout: LabLayout) {
        switch target {
        case .link(let id):
            if mode == .ar { tracedLinkID = id }
            else { tracedLinkID = nil; linkSelection = topology?.links.first { $0.id == id } }
        case .device(let id):
            deviceSelection = topology?.devices.first { $0.id == id }
        case .hardware(let id): hardwareSelection = HardwareCatalog.reference(id)
        case .placement(let id): selection = layout.placements.first { $0.id == id }
        }
    }

    private var viewPicker: some View {
        Picker("Vista", selection: Binding(
            get: { mode },
            set: { value in
                guard value != .ar || canUseAR else { return }
                if value == .ar {
                    paintRoom = false
                    tracedLinkID = nil
                    do {
                        let assemblies = try assemblyStore.all()
                        if let previous = assemblies.first(where: { $0.id == assemblyStore.preferredID })
                            ?? (assemblies.count == 1 ? assemblies.first : nil) {
                            assemblyToOpen = previous
                            openPendingAssembly()
                            return
                        }
                    } catch { showAssemblyError(error); return }
                    if previewProject == nil { resumeRoomAR(); return }
                    openPreviewAR()
                    return
                }
                mode = value
            })) {
            Text("3D").accessibilityLabel("Cuarto 3D").tag(LabViewMode.room)
            Text("AR \(arScale.title)")
                .accessibilityLabel("Realidad aumentada, escala \(arScale.title)")
                .tag(LabViewMode.ar).disabled(!canUseAR)
        }
    }
}

struct LabViewerSearch: View {
    let devices: [LabTopology.Device]
    let layout: LabLayout
    let onSelect: (LabInspectionDestination) -> Void
    var onClear: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let results = LabViewerSearchResult.find(query, devices: devices, in: layout)
        NavigationStack {
            List(results) { result in
                Button {
                    onSelect(result.destination)
                    dismiss()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name).foregroundStyle(.primary)
                            if !result.detail.isEmpty { Text(result.detail).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: result.destination.port == nil ? "scope" : "cable.connector")
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass",
                                           description: Text("Prueba con otro nombre, dirección IP o puerto."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nombre, IP o puerto")
            .navigationTitle("Buscar en el laboratorio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClear {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Quitar marca") { onClear(); dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { DismissButton() }
            }
        }
    }
}

struct LabCableFilterMenu: View {
    let topology: LabTopology
    let layout: LabLayout
    @Binding var filter: LabCableFilter?
    @Binding var showsCables: Bool
    let onChange: () -> Void

    var body: some View {
        let vlans = Set(topology.links.flatMap(\.vlanIDs)).sorted()
        let media = Set(topology.links.map(\.medium)).sorted { $0.title < $1.title }
        let racks = layout.placements.filter { $0.kind == .rack }
        Menu {
            option("Todos los cables", filter: nil)
            option("Ocultar cables", filter: nil, visible: false)
            if !vlans.isEmpty {
                Menu("Por VLAN", systemImage: "number") {
                    ForEach(vlans, id: \.self) { vlan in option("VLAN \(vlan)", filter: .vlan(vlan)) }
                }
            }
            if !media.isEmpty {
                Menu("Por tipo de cable", systemImage: "cable.connector") {
                    ForEach(media, id: \.self) { medium in option(medium.title, filter: .medium(medium)) }
                }
            }
            if !racks.isEmpty {
                Menu("Por rack", systemImage: "server.rack") {
                    ForEach(racks) { rack in option(rack.title, filter: .rack(rack.id)) }
                }
            }
        } label: {
            Label("Filtros de cableado", systemImage: !showsCables ? "eye.slash" : filter == nil
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .labelStyle(.iconOnly).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
        }
        .accessibilityValue(activeTitle(in: racks))
        .buttonStyle(ViewerPressStyle())
        .modifier(ViewerSurface(radius: 24))
    }

    private func activeTitle(in racks: [LabPlacement]) -> String {
        guard showsCables else { return "Cables ocultos" }
        switch filter {
        case nil: return "Todos los cables"
        case .medium(let medium): return medium.title
        case .vlan(let vlan): return "VLAN \(vlan)"
        case .rack(let id): return racks.first { $0.id == id }?.title ?? "Por rack"
        }
    }

    private func option(_ title: String, filter value: LabCableFilter?, visible: Bool = true) -> some View {
        Button {
            filter = value
            showsCables = visible
            onChange()
        } label: {
            if showsCables == visible && filter == value { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }
}

private struct ARSearchMarker: View {
    let walkthrough: ARWalkthrough
    let name: String

    var body: some View {
        GeometryReader { geometry in
            if let marker = walkthrough.searchMarker, walkthrough.ready {
                let halfWidth = geometry.size.width / 2
                let halfHeight = geometry.size.height / 2
                let edgeX = max(1, halfWidth - 27)
                let edgeY = max(1, halfHeight - min(80, halfHeight / 2))
                let dx = CGFloat(marker.offset.x) * halfWidth
                let dy = CGFloat(marker.offset.y) * halfHeight
                let distance = max(abs(dx) / edgeX, abs(dy) / edgeY)
                let inView = !marker.behind && abs(dx) <= halfWidth - 21 && abs(dy) <= halfHeight - 21
                let scale = inView ? 1 : max(distance, 0.001)
                Image(systemName: inView ? "scope" : "arrow.right")
                    .font(.system(size: 21, weight: .semibold))
                    .rotationEffect(inView ? .zero : .radians(atan2(dy, dx)))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .modifier(ViewerSurface(radius: 21, material: .thick))
                    .position(x: halfWidth + dx / scale, y: halfHeight + dy / scale)
                    .accessibilityLabel(name)
                    .accessibilityValue(inView ? "En pantalla" : marker.behind ? "Detrás de ti"
                        : abs(dx) > abs(dy) ? (dx > 0 ? "A la derecha" : "A la izquierda")
                        : (dy > 0 ? "Más abajo" : "Más arriba"))
            }
        }
    }
}

private extension LabRackClearance.Fit {
    var title: String {
        switch self {
        case .needsFloor: "Piso sin escanear por completo"
        case .blocked, .occupied: "El rack no cabe aquí"
        case .accessUnknown: "Huella libre · acceso sin verificar"
        case .accessLimited: "Huella libre · acceso reducido"
        case .clear: "Huella y acceso libres según el escaneo"
        }
    }

    var detail: String {
        switch self {
        case .needsFloor: "Mueve el iPhone para escanear todo el piso bajo la huella."
        case .blocked: "Una superficie detectada cruza el espacio del rack."
        case .occupied: LabARAssembly.collisionHint
        case .accessUnknown: "Escanea el piso delante y detrás para revisar el acceso."
        case .accessLimited: "Una superficie detectada invade el acceso delante o detrás."
        case .clear: "La línea punteada marca 60 cm de acceso delante y detrás."
        }
    }

    var symbol: String {
        switch self {
        case .needsFloor, .accessUnknown: "viewfinder"
        case .blocked, .occupied, .accessLimited: "exclamationmark.triangle"
        case .clear: "checkmark.circle"
        }
    }
}

private struct LaboratorySceneID: Hashable {
    let room: UUID
    let mode: LabViewMode
    let session: ObjectIdentifier?
    let roomRevision: Int
}

private extension TierFixture.Kind {
    var symbol: String {
        switch self {
        case .batteryBank: "battery.100percent"
        case .switchboard: "bolt"
        case .cooling: "fan"
        }
    }
}

private struct TierARPicker: View {
    private enum Category: String, CaseIterable {
        case racks = "Racks"
        case workstations = "Puestos de trabajo, PC y portátiles"
        case servers = "Servidores"
        case network = "Equipos de red"
        case power = "Energía"
        case cooling = "Refrigeración"
    }

    private struct Choice: Identifiable {
        let title: String
        let symbol: String
        let target: LabARFocus
        let category: Category
        var id: LabARFocus { target }
    }

    let project: LabProject
    let selection: LabARFocus
    let available: Bool
    let showsContextControl: Bool
    @Binding var showContext: Bool
    let onSelect: (LabARFocus) -> Void
    @State private var search = ""

    private var choices: [Choice] {
        let placements = project.layout.placements
        let desks = Set(placements.filter { $0.kind == .workstation }.map(\.id))
        let furniture = placements.map { entry in
            let rack = entry.kind == .rack
            return Choice(title: entry.title, symbol: rack ? "server.rack" : "display",
                          target: .placement(entry.id), category: rack ? .racks : .workstations)
        }
        let devices = project.topology.devices.map { device in
            let category: Category = desks.contains(device.placementID) ? .workstations
                : device.visualModelID.hasPrefix("server-") ? .servers : .network
            let symbol = switch category {
            case .workstations: device.visualModelID.hasPrefix("laptop-") ? "laptopcomputer" : "desktopcomputer"
            case .servers: "server"
            default: "network"
            }
            return Choice(title: device.name, symbol: symbol, target: .device(device.id), category: category)
        }
        let fixtures = (project.layout.facility?.fixtures ?? []).map { fixture in
            Choice(title: fixture.name, symbol: fixture.kind.symbol, target: .fixture(fixture.id),
                   category: fixture.kind == .cooling ? .cooling : .power)
        }
        return (furniture + devices + fixtures).filter { search.isEmpty || $0.title.localizedStandardContains(search) }
    }

    var body: some View {
        let entries = choices
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        Button("Colocar laboratorio completo", systemImage: "square.3.layers.3d") { onSelect(.all) }
                            .disabled(!available)
                        if #available(iOS 18, *), showsContextControl {
                            Toggle("Mostrar contexto atenuado", isOn: $showContext)
                        }
                    }
                    if !available {
                        Label("Para colocar equipos, abre Nexus AR en un iPhone compatible.", systemImage: "iphone")
                    }
                }
                ForEach(Category.allCases, id: \.self) { category in
                    let group = entries.filter { $0.category == category }
                    if !group.isEmpty {
                        Section(category.rawValue) {
                            ForEach(group) { choice in
                                Button { onSelect(choice.target) } label: {
                                    HStack {
                                        Label(choice.title, systemImage: choice.symbol)
                                        Spacer()
                                        if selection == choice.target {
                                            Image(systemName: "checkmark").accessibilityHidden(true)
                                        }
                                    }
                                }
                                .accessibilityAddTraits(selection == choice.target ? .isSelected : [])
                                .disabled(!available)
                            }
                        }
                    }
                }
                if entries.isEmpty { Label("Sin equipos que coincidan", systemImage: "magnifyingglass") }
            }
            .navigationTitle("Colocar en AR")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Buscar equipo")
            .toolbar { DismissButton() }
        }
    }
}

private struct ARScaleButton: View {
    let scale: LabARScale
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Escala \(scale.title)", systemImage: "ruler")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ViewerPressStyle())
        .modifier(ViewerSurface(radius: 12))
        .accessibilityLabel("Escala AR")
        .accessibilityValue(scale.title)
    }
}

private struct ARScalePicker: View {
    let selection: LabARScale
    let space: LabARSpace
    let onSelect: (LabARScale) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(LabARScale.allCases, id: \.self) { scale in
                        Button {
                            onSelect(scale)
                            dismiss()
                        } label: {
                            ARScaleOption(title: scale.title, dimensions: space.scaled(to: scale).summary,
                                          selected: scale == selection)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(scale == selection ? .isSelected : [])
                    }
                } header: {
                    Text("Espacio de referencia")
                } footer: {
                    Text("Ancho × fondo × alto y superficie de la sala virtual. Comprueba que el espacio esté libre antes de colocar el modelo.")
                }
            }
            .navigationTitle("Escala AR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { DismissButton() }
        }
    }
}

private struct ARScaleOption: View {
    let title: String
    let dimensions: String
    let selected: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = verticalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        HStack(spacing: 12) {
            layout {
                Text(title).font(.headline).foregroundStyle(.primary).fixedSize()
                Text(dimensions).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private extension LabARSpace {
    var summary: String {
        let length = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
        let area = floorArea.formatted(.number.precision(.fractionLength(0...4)))
        return "\(size.x.formatted(length)) × \(size.z.formatted(length)) × \(size.y.formatted(length)) m · \(area) m²"
    }
}

struct ViewerSurface: ViewModifier {
    let radius: CGFloat
    var material: Material = .regular
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background {
                if reduceTransparency || contrast == .increased {
                    shape.fill(Color(uiColor: .secondarySystemBackground))
                } else {
                    shape.fill(material)
                }
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(.primary.opacity(0.36)).allowsHitTesting(false)
                }
            }
    }
}

struct ViewerPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .opacity(enabled ? (configuration.isPressed ? 0.62 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AssemblyControls: View {
    enum Action {
        case add, network, ports, rack, rackDevices, rackMonitors, clearTrace, placeAll, adjust, changeCableLevel
        case showCables(Bool), inspect, cli, remove, relocalize, setOrigin, cancel
    }

    let projectName: String
    let summary: String?
    let saved: String?
    let status: String
    let cableReviews: Int
    let instruction: String?
    let hint: String?
    let rackFit: LabRackClearance.Fit?
    let onPlace: (() -> Void)?
    let cableConfirmation: String?
    let powerRouteNeedsReview: Bool
    let ports: AssemblyPortControls?
    let direct: AssemblyDirectControls?
    let editor: AssemblyAdjustmentControls?
    let routing: AssemblyCableControls?
    let tools: AssemblyTools
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ports == nil || verticalSizeClass != .compact {
                VStack(alignment: .leading, spacing: 3) {
                    Label(projectName, systemImage: "square.3.layers.3d").font(.subheadline.weight(.semibold))
                    if let summary { Text(summary).font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                    if let saved {
                        Text(saved).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("lab.assembly.saved")
                    }
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    if let cableConfirmation {
                        Label(cableConfirmation, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }
                    if powerRouteNeedsReview {
                        Label("Revisar recorrido de alimentación", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if cableReviews > 0 {
                        Label("Revisar espacio de cableado (\(cableReviews))", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if ports == nil, instruction == nil, let hint {
                        Label(hint, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .modifier(ViewerSurface(radius: 14, material: .thick))
                .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
            Group {
                if let ports {
                    ports
                } else if let editor {
                    editor.frame(maxWidth: 370)
                } else if let instruction {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(instruction).font(.subheadline.weight(.semibold))
                        if let rackFit {
                            Label(rackFit.title, systemImage: rackFit.symbol).font(.caption.weight(.semibold))
                            Text(rackFit.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { placementActions }
                            VStack(alignment: .leading) { placementActions }
                        }
                    }
                } else if let routing {
                    routing
                } else if let direct {
                    direct
                } else {
                    tools
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .modifier(ViewerSurface(radius: 18, material: .thick))
            .frame(maxWidth: .infinity, alignment: editor == nil ? .center : .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var placementActions: some View {
        Button("Confirmar ubicación") { onPlace?() }.frame(minHeight: 44).disabled(onPlace == nil)
        Button("Cancelar", role: .cancel) { tools.onAction(.cancel) }.frame(minHeight: 44)
    }
}

private struct ARPowerOutletControls: View {
    let name: String
    let ready: Bool
    let hint: String?
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .vertical) {
                    instructions.fixedSize(horizontal: false, vertical: true)
                    ScrollView { instructions }
                }
                .frame(maxHeight: min(180, max(60, geometry.size.height * 0.42)))
                Button("Cancelar", role: .cancel, action: cancel).frame(minHeight: 44)
            }
            .font(.subheadline)
            .frame(maxWidth: 400, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(ViewerSurface(radius: 18, material: .thick))
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: ready)
        .transition(.opacity)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Conectar toma AR", systemImage: "powerplug").font(.headline)
            if ready {
                Text("Toca el tomacorriente en la cámara para conectar \(name).")
            } else {
                ProgressView("Recuperando seguimiento…")
            }
            if let hint, ready {
                Label(hint, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
        }
    }
}

private struct AssemblyDirectControls: View {
    let title: String
    let instruction: String
    let first: String
    let second: String?
    let exit: String
    let onFirst: () -> Void
    let onSecond: () -> Void
    let onExit: () -> Void
    var onLift: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(spacing: 15))
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(instruction).font(.caption).foregroundStyle(.secondary)
            layout {
                Button(first, action: onFirst).frame(minHeight: 44)
                if let second { Button(second, action: onSecond).frame(minHeight: 44) }
                if let onLift { Button("Altura", action: onLift).frame(minHeight: 44) }
                Button(exit, action: onExit).frame(minHeight: 44)
            }
        }
    }
}

private struct AssemblyPortControls: View {
    let origin: String?
    let destination: String?
    let medium: String?
    let hint: String?
    let tracking: Bool
    let onPick: () -> Void
    let onSettings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let origin {
                Label("Origen · \(origin)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
            } else {
                Label("Conectar cable", systemImage: "cable.connector")
                    .font(.subheadline.weight(.semibold))
            }
            if let destination {
                Label("Destino · \(destination)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                ProgressView("Acomodando el cable…").font(.caption)
            } else if let hint {
                Label(hint, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(instruction).font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(alignment: .leading, spacing: 0) { actions }
            }
        }
    }

    private var instruction: String {
        if !tracking { return "Usa el selector mientras se recupera la ubicación." }
        guard origin != nil else { return "Toca un puerto libre para marcar el origen." }
        if let medium { return "Toca un puerto de destino compatible · \(medium)." }
        return "Toca un puerto de destino compatible."
    }

    @ViewBuilder private var actions: some View {
        if destination == nil {
            Button("Elegir puerto", systemImage: "list.bullet", action: onPick).frame(minHeight: 44)
            if origin != nil {
                Button("Canaleta y VLAN", systemImage: "slider.horizontal.3", action: onSettings)
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
        }
        Button("Cancelar", role: .cancel, action: onCancel).frame(minHeight: 44)
    }
}

private struct EquipmentPlacementControls: View {
    let name: String
    let surface: LabEquipmentSurface
    let ready: Bool
    let selected: Bool
    let hint: String?
    let confirm: () -> Void
    let cancel: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(name, systemImage: surface == .floor ? "arrow.down.to.line" : "table.furniture")
                .font(.subheadline.weight(.semibold))
            if !ready {
                ProgressView("Recuperando seguimiento…").font(.caption)
            } else if let hint {
                Label(hint, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(selected ? "Confirma para mover el equipo."
                     : surface == .floor ? "Toca un punto libre del piso." : "Toca un punto libre sobre una mesa.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { actions }
                VStack(alignment: .leading) { actions }
            }
        }
        .frame(maxWidth: verticalSizeClass == .compact ? 250 : 400, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .modifier(ViewerSurface(radius: 18, material: .thick))
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: verticalSizeClass == .compact ? .bottomLeading : .bottom)
    }

    @ViewBuilder private var actions: some View {
        Button("Confirmar ubicación", action: confirm).frame(minHeight: 44).disabled(!selected || !ready)
        Button("Cancelar", role: .cancel, action: cancel).frame(minHeight: 44)
    }
}

private struct AssemblyTools: View {
    let selectedName: String?
    let isPlaced: Bool
    let cableLevel: LabARAssembly.CableLevel?
    let canInspect: Bool
    let canOpenCLI: Bool
    let canEditNetwork: Bool
    let canEditRack: Bool
    let rackSelected: Bool
    let canAdjust: Bool
    let managesRackDevice: Bool
    let hasTrace: Bool
    let available: Bool
    let showsCables: Bool
    let recovery: AssemblyControls.Action?
    let powerMenu: AnyView?
    let onAction: (AssemblyControls.Action) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 6) {
            if let selectedName {
                Text(selectedName).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            if canOpenCLI {
                Button { onAction(.cli) } label: {
                    Label("Abrir CLI", systemImage: "terminal").frame(minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("lab.assembly.cli")
            } else if rackSelected {
                layout {
                    Button("Equipos y CLI", systemImage: "terminal") { onAction(.rackDevices) }
                        .frame(minHeight: 44)
                    Button("Monitores", systemImage: "display") { onAction(.rackMonitors) }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("lab.assembly.monitors")
                    powerMenu?.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
            layout {
                Button { onAction(.add) } label: { Label("Añadir", systemImage: "plus") }
                    .accessibilityLabel("Añadir equipo")
                    .frame(minHeight: 44)
                    .disabled(!available)
                if canEditRack {
                    Button("Rack", systemImage: "server.rack") { onAction(.rack) }
                        .accessibilityLabel("Editar rack")
                        .frame(minHeight: 44).disabled(!available)
                } else if canEditNetwork {
                    Button("Red", systemImage: "cable.connector") { onAction(.network) }
                        .accessibilityLabel("Editar red")
                        .frame(minHeight: 44).disabled(!available)
                }
                if selectedName == nil {
                    Button("Colocar todo", systemImage: "square.3.layers.3d") { onAction(.placeAll) }
                        .frame(minHeight: 44).disabled(!available)
                } else if canAdjust {
                    Button(managesRackDevice ? "Mover o retirar" : "Ajustar",
                           systemImage: managesRackDevice ? "arrow.up.arrow.down" : "gamecontroller") { onAction(.adjust) }
                        .frame(minHeight: 44).disabled(!available)
                }
                AssemblyOptionsMenu(tools: self)
            }
        }
    }
}

private struct AssemblyOptionsMenu: View {
    let tools: AssemblyTools

    var body: some View {
        Menu {
            if !tools.rackSelected { tools.powerMenu }
            if tools.canEditNetwork {
                Button("Conectar en AR", systemImage: "cable.connector") { tools.onAction(.ports) }
                    .disabled(!tools.available)
                if tools.canEditRack {
                    Button("Editar red", systemImage: "slider.horizontal.3") { tools.onAction(.network) }
                        .disabled(!tools.available)
                }
            }
            if tools.selectedName != nil {
                Button("Colocar todo", systemImage: "square.3.layers.3d") { tools.onAction(.placeAll) }
                    .disabled(!tools.available)
            }
            if let level = tools.cableLevel {
                Button(level == .floor ? "Cableado por piso…" : "Cableado por arriba…",
                       systemImage: level == .floor ? "arrow.down.to.line" : "arrow.up.to.line") {
                    tools.onAction(.changeCableLevel)
                }
                .disabled(!tools.available)
            }
            Toggle("Mostrar cables", isOn: Binding(get: { tools.showsCables }, set: { tools.onAction(.showCables($0)) }))
            if tools.hasTrace {
                Button("Quitar resaltado del cable", systemImage: "xmark") { tools.onAction(.clearTrace) }
            }
            if tools.canInspect {
                Button("Ficha del equipo", systemImage: "info.circle") { tools.onAction(.inspect) }
            }
            if tools.isPlaced {
                Button("Retirar del montaje", systemImage: "minus.circle", role: .destructive) { tools.onAction(.remove) }
            }
            if case .relocalize = tools.recovery {
                Button("Volver a buscar la ubicación", systemImage: "location.circle") { tools.onAction(.relocalize) }
                Button("Fijar nueva referencia", systemImage: "move.3d") { tools.onAction(.setOrigin) }
            } else if case .setOrigin = tools.recovery {
                Button("Fijar la referencia del montaje", systemImage: "location.circle") { tools.onAction(.setOrigin) }
            }
        } label: {
            Label("Opciones del montaje", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
    }
}

private struct AssemblyCableControls: View {
    let title: String
    let onSelect: (LabARAssembly.CableLevel) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(spacing: 16))
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("Elige una canaleta para las conexiones del proyecto.").font(.caption).foregroundStyle(.secondary)
            layout {
                Button("Por piso", systemImage: "arrow.down.to.line") { onSelect(.floor) }.frame(minHeight: 44)
                Button("Por arriba", systemImage: "arrow.up.to.line") { onSelect(.overhead) }.frame(minHeight: 44)
                Button("Cancelar", role: .cancel, action: onCancel).frame(minHeight: 44)
            }
        }
    }
}

private struct AssemblyAdjustmentControls: View {
    let name: String
    let available: Bool
    let onStep: (LabARAssembly.Adjustment, SIMD2<Float>, Float) -> Void
    let onFinish: (Bool) -> Void
    var commitTitle = "Listo"
    var adjustments: [LabARAssembly.Adjustment] = [.move, .turn]
    var initialMode = LabARAssembly.Adjustment.move
    @State private var mode = LabARAssembly.Adjustment.move
    @State private var displacement = SIMD2<Float>.zero
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var moving: Bool { available && LabWalkPose.joystickAxes(displacement) != .zero }
    private var activeMode: LabARAssembly.Adjustment { adjustments.contains(mode) ? mode : .turn }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            joystick
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(2)
                if adjustments.count > 1 {
                    Picker("Ajuste", selection: $mode) {
                        ForEach(adjustments, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                } else {
                    Label("Girar rack", systemImage: "rotate.right").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Cancelar", role: .cancel) { onFinish(false) }.frame(minHeight: 44)
                    Spacer(minLength: 4)
                    Button(commitTitle) { onFinish(true) }.fontWeight(.semibold).frame(minHeight: 44)
                }
            }
        }
        .onChange(of: mode) { displacement = .zero }
        .onAppear { mode = adjustments.contains(initialMode) ? initialMode : .turn }
        .onChange(of: available) { if !available { displacement = .zero } }
        .task(id: moving) {
            guard moving else { return }
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled && moving {
                let now = clock.now
                let elapsed = last.duration(to: now).components
                let seconds = Float(elapsed.seconds) + Float(elapsed.attoseconds) / 1e18
                onStep(activeMode, LabWalkPose.joystickAxes(displacement), min(0.033, max(1 / 120, seconds)))
                last = now
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }

    private var joystick: some View {
        LabDirectionalJoystick(displacement: $displacement, horizontalOnly: activeMode == .turn,
                               verticalOnly: activeMode == .lift) { next in
            let axes = LabWalkPose.joystickAxes(next)
            if available && !moving && axes != .zero {
                onStep(activeMode, axes, 1 / 60)
            }
        }
            .id(activeMode)
            .disabled(!available)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activeMode == .lift ? "Subir o bajar rack" : activeMode.title + " equipo")
            .accessibilityActions {
                if activeMode != .lift {
                    Button("Izquierda") { nudge(SIMD2(-1, 0)) }
                    Button("Derecha") { nudge(SIMD2(1, 0)) }
                }
                if activeMode == .move {
                    Button("Adelante") { nudge(SIMD2(0, 1)) }
                    Button("Atrás") { nudge(SIMD2(0, -1)) }
                }
                if activeMode == .lift {
                    Button("Subir") { nudge(SIMD2(0, 1)) }
                    Button("Bajar") { nudge(SIMD2(0, -1)) }
                }
            }
    }

    private func nudge(_ axes: SIMD2<Float>) {
        guard available else { return }
        onStep(activeMode, axes, activeMode == .turn ? 1 / 12 : 0.12)
    }

}

private struct ScenePingStatus: View {
    let diagnosis: LabTopology.PingDiagnosis
    let onDismiss: () -> Void

    var body: some View {
        let reached = diagnosis.issue == nil
        let title = reached ? "Ruta del ping" : "Ping interrumpido"
        let symbol = reached ? "point.topleft.down.to.point.bottomright.curvepath" : "exclamationmark.triangle"
        HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: symbol).fixedSize()
                Text(reached ? "Ping OK" : "Sin ping").fixedSize()
                Label(title, systemImage: symbol).labelStyle(.iconOnly)
            }
            .accessibilityLabel(title)
            Button("Quitar ruta de diagnóstico", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.leading, 10)
        .modifier(ViewerSurface(radius: 12))
    }
}

private struct WalkthroughHUD: View {
    let walkthrough: ARWalkthrough
    let layout: LabLayout
    let topology: LabTopology?
    let worldMapped: Bool
    let manualHome: Bool
    let usesFloor: Bool
    let mapSaved: Bool
    let scale: LabARScale
    let space: LabARSpace?
    let onSelectScale: (() -> Void)?
    let traceID: String?
    let showVirtualWalls: Bool
    let focusTargets: [LabFocusTarget]
    @Binding var lockedDeviceID: String?
    @Binding var showTraffic: Bool
    let showCables: Bool
    let onInspect: (LabSceneTarget) -> Void
    let onDismissTrace: () -> Void
    let onDetails: (LabTopology.Link) -> Void
    let ping: LabTopology.PingDiagnosis?
    let onDismissPing: () -> Void
    let onRealign: (() -> Void)?
    let onReposition: (() -> Void)?
    let catalystStatus: Catalyst2960Status?
    let powerOutletConfirmation: String?
    let powerRouteNeedsReview: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let onSelectScale, dynamicType.isAccessibilitySize && geometry.size.height >= 360 {
                    VStack(alignment: .leading, spacing: 8) {
                        ARScaleButton(scale: scale, action: onSelectScale)
                        status
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        status
                            .frame(maxWidth: dynamicType.isAccessibilitySize ? .none : 320, alignment: .leading)
                        Spacer(minLength: 0)
                        if let onSelectScale {
                            ARScaleButton(scale: scale, action: onSelectScale)
                        } else if worldMapped && walkthrough.ready && !dynamicType.isAccessibilitySize && geometry.size.width >= 320 {
                            let device = topology.flatMap { network in
                                network.links.first { $0.id == traceID }.flatMap { network.circuit(for: $0).last?.toDeviceID }
                            }
                            let placement = topology?.devices.first { $0.id == (device ?? lockedDeviceID) }?.placementID
                            WalkthroughMap(layout: layout, walkthrough: walkthrough, destinationID: placement)
                        }
                    }
                }
                Spacer(minLength: 0)
                if walkthrough.ready {
                    HStack(alignment: .bottom) {
                        if let ping {
                            ScenePingStatus(diagnosis: ping, onDismiss: onDismissPing)
                        } else if showTraffic && showCables && topology?.links.isEmpty == false &&
                            !dynamicType.isAccessibilitySize && geometry.size.width >= (lockedDeviceID == nil ? 330 : 430) {
                            LabTrafficLegend()
                        }
                        Spacer(minLength: 4)
                        if !focusTargets.isEmpty {
                            LabFocusControls(targets: focusTargets, choose: chooseTarget, lockedID: lockedDeviceID,
                                             onLock: { lockedDeviceID = $0; tracedFocus($0) }, showTraffic: $showTraffic,
                                             onOpenDevice: { onInspect(.device($0)) })
                        }
                    }.padding(.bottom, 6)
                    let cap = max(56, geometry.size.height * (geometry.size.height < 360 ? 0.44 : 0.38))
                    ViewThatFits(in: .vertical) {
                        inspection.fixedSize(horizontal: false, vertical: true)
                        ScrollView { inspection }
                    }
                    .frame(maxWidth: 460, maxHeight: cap)
                    .modifier(ViewerSurface(radius: 18, material: .thick))
                    .transition(.opacity)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: walkthrough.ready)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: walkthrough.tierCableStatus)
        }
        .sensoryFeedback(.selection, trigger: traceID) { _, current in current != nil }
    }

    private func tracedFocus(_ id: String?) {
        if id != nil { onDismissTrace() }
    }

    private func chooseTarget(_ method: LabFocusMode) -> LabFocusTarget? {
        if method == .aim, let id = walkthrough.deviceInSight,
           let target = focusTargets.first(where: { $0.id == id }) { return target }
        guard let origin = walkthrough.focusOrigin else { return nil }
        let range: Float = method == .aim ? max(8, 0.8 / scale.factor) : max(3, 0.35 / scale.factor)
        return LabFocusTarget.pick(method, from: origin, direction: walkthrough.focusDirection,
                                   in: focusTargets, maximumDistance: range)
    }

    private var inspection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let catalystStatus { catalystStatus.font(.caption) }
            if let powerOutletConfirmation {
                Label(powerOutletConfirmation, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            }
            if powerRouteNeedsReview {
                Label("Revisar recorrido de alimentación", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ARInspectionControls(
                walkthrough: walkthrough, layout: layout, topology: topology,
                traceID: traceID, showVirtualWalls: showVirtualWalls, lockedDeviceID: lockedDeviceID,
                onInspect: onInspect, onDismissTrace: onDismissTrace, onDetails: onDetails)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch walkthrough.phase {
            case .preparing:
                message("Preparando la sala", detail: nil, loading: true)
            case .starting:
                message("Iniciando cámara", detail: "Mueve el iPhone despacio.", loading: true)
            case .aligning:
                message("Recuperando el anclaje", detail: "Apunta a las paredes y esquinas que vio la cámara. Muévete despacio.",
                        loading: true, recovery: true)
            case .placing:
                if let fit = walkthrough.rackFit {
                    message(fit.title, detail: fit.detail, icon: fit.symbol)
                } else {
                    message(walkthrough.placementAvailable ? "Revisa la huella" : "Busca una superficie",
                            detail: walkthrough.placementHint ?? (walkthrough.placementAvailable
                                ? "Mueve el iPhone para ajustar la ubicación antes de confirmar."
                                : usesFloor ? "Apunta al piso despejado y mueve el iPhone despacio." : "Apunta a una superficie horizontal con textura."),
                            icon: walkthrough.placementAvailable ? "square.dashed" : "viewfinder")
                }
                if let space {
                    Text(space.scaled(to: scale).summary).font(.caption).foregroundStyle(.secondary)
                }
                Button("Confirmar ubicación", systemImage: "checkmark") { walkthrough.confirmPreview?() }
                    .frame(minHeight: 44).disabled(!walkthrough.placementAvailable)
            case .ready:
                let title = manualHome ? (mapSaved ? "Ubicación guardada" : "HomeLab anclado")
                                       : worldMapped ? "Anclado al cuarto" : scale == .fullSize ? "Modelo colocado" : "Maqueta colocada"
                if walkthrough.tierCableStatus == .loading {
                    message("Cargando maqueta · \(scale.title)", detail: nil, loading: true)
                } else {
                    let detail = walkthrough.tierCableStatus == .failed ? "El cableado no pudo cargarse."
                        : worldMapped && !mapSaved ? "Muévete despacio y apunta alrededor para guardar la ubicación." : nil
                    message("\(title) · \(scale.title)", detail: detail)
                }
            case .limited(let detail):
                message("Buscando posición", detail: detail, icon: "viewfinder", recovery: true)
            case .interrupted:
                message("Cámara interrumpida", detail: "Apunta de nuevo al cuarto.", icon: "video.slash", recovery: true)
            case .failed(let detail):
                message("AR interrumpida", detail: detail, icon: "exclamationmark.triangle", recovery: true)
            }
        }
        .padding(10)
        .modifier(ViewerSurface(radius: 12))
        .accessibilityElement(children: .contain)
    }

    private func message(_ title: String, detail: String?, icon: String = "viewfinder",
                         loading: Bool = false, recovery: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if loading { ProgressView().controlSize(.small).accessibilityHidden(true) }
                else { Image(systemName: icon).foregroundStyle(Color.accentColor).accessibilityHidden(true) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            if recovery {
                if let onRealign, let onReposition {
                    Menu("Recuperar AR", systemImage: "location.circle") {
                        Button("Volver a alinear", systemImage: "viewfinder", action: onRealign)
                        Button("Colocar de nuevo", systemImage: "move.3d", action: onReposition)
                    }.frame(minHeight: 44)
                } else if let onRealign {
                    Button("Volver a alinear", systemImage: "viewfinder", action: onRealign).frame(minHeight: 44)
                } else if let onReposition {
                    Button("Colocar de nuevo", systemImage: "move.3d", action: onReposition).frame(minHeight: 44)
                }
            }
        }
    }
}

private struct AimingReticle: View {
    let walkthrough: ARWalkthrough

    var body: some View {
        if walkthrough.phase == .placing {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(walkthrough.placementAvailable ? Color.cyan : Color.white)
                .shadow(color: .black, radius: 3)
        } else if walkthrough.ready {
            Image(systemName: "scope")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(walkthrough.target == nil ? Color.white : Color.yellow)
                .shadow(color: .black, radius: 3)
        }
    }
}

private struct WalkthroughMap: View {
    let layout: LabLayout
    let walkthrough: ARWalkthrough
    let destinationID: String?

    var body: some View {
        let pose = walkthrough.pose
        let inside = pose.map { LabGeometry.contains($0.position, polygon: layout.floorPolygon) } ?? false
        if let pose {
            VStack(alignment: .leading, spacing: 2) {
                Canvas { context, size in
                    let polygon = layout.floorPolygon
                    let lower = polygon.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
                    let upper = polygon.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
                    let extent = upper - lower
                    let scale = min(Float(size.width - 10) / extent.x, Float(size.height - 10) / extent.y)
                    let center = (lower + upper) / 2
                    func point(_ p: SIMD2<Float>) -> CGPoint {
                        CGPoint(x: size.width / 2 + CGFloat((p.x - center.x) * scale),
                                y: size.height / 2 + CGFloat((p.y - center.y) * scale))
                    }
                    func shape(_ vertices: [SIMD2<Float>]) -> Path {
                        Path { path in
                            guard let first = vertices.first else { return }
                            path.move(to: point(first))
                            for vertex in vertices.dropFirst() { path.addLine(to: point(vertex)) }
                            path.closeSubpath()
                        }
                    }
                    let floor = shape(polygon)
                    context.fill(floor, with: .color(.secondary.opacity(0.14)))
                    context.stroke(floor, with: .color(.secondary), lineWidth: 1)
                    for placement in layout.placements {
                        let c = SIMD2(placement.position.x, placement.position.z)
                        let right = SIMD2(cos(placement.yaw), -sin(placement.yaw)) * placement.size.x / 2
                        let back = SIMD2(sin(placement.yaw), cos(placement.yaw)) * placement.size.z / 2
                        let footprint = shape([c - right - back, c + right - back, c + right + back, c - right + back])
                        context.fill(footprint, with: .color(.secondary))
                        if destinationID == placement.id {
                            context.stroke(footprint, with: .color(.orange), lineWidth: 2)
                        }
                    }
                    if inside {
                        let p = point(pose.position)
                        let direction = pose.direction / max(simd_length(pose.direction), 0.001)
                        let dot = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                        let heading = Path { path in
                            path.move(to: p)
                            path.addLine(to: CGPoint(x: p.x + CGFloat(direction.x * 11), y: p.y + CGFloat(direction.y * 11)))
                        }
                        context.stroke(heading, with: .color(.cyan), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        context.fill(Path(ellipseIn: dot), with: .color(.cyan))
                    }
                }.frame(height: 72).accessibilityHidden(true)
                Label(inside ? "Tu posición" : "Fuera del cuarto", systemImage: "location.fill")
                    .font(.caption2.weight(.semibold))
            }
            .padding(8).frame(width: 116)
            .modifier(ViewerSurface(radius: 12))
            .allowsHitTesting(false)
        }
    }
}

private struct ARInspectionControls: View {
    let walkthrough: ARWalkthrough
    let layout: LabLayout
    let topology: LabTopology?
    let traceID: String?
    let showVirtualWalls: Bool
    let lockedDeviceID: String?
    let onInspect: (LabSceneTarget) -> Void
    let onDismissTrace: () -> Void
    let onDetails: (LabTopology.Link) -> Void

    var body: some View {
        let target: LabSceneTarget? = if case .link = walkthrough.target {
            walkthrough.target
        } else { lockedDeviceID.map { .device($0) } ?? walkthrough.target }
        VStack(alignment: .leading, spacing: 8) {
            if let topology, let link = topology.links.first(where: { $0.id == traceID }) {
                let circuit = topology.circuit(for: link)
                let first = circuit.first ?? link
                let last = circuit.last ?? link
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Ruta del cable", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.subheadline.bold())
                        Spacer()
                        Button(action: onDismissTrace) {
                            Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Quitar resaltado")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            endpoint("Origen", deviceID: first.fromDeviceID, port: first.fromPort).fixedSize()
                            endpoint("Destino", deviceID: last.toDeviceID, port: last.toPort).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            endpoint("Origen", deviceID: first.fromDeviceID, port: first.fromPort)
                            endpoint("Destino", deviceID: last.toDeviceID, port: last.toPort)
                        }
                    }
                    HStack {
                        Text(circuit.allSatisfy { walkthrough.renderedLinks.contains($0.id) }
                             ? "Sigue el cable resaltado en amarillo."
                             : "Consulta los extremos en la ficha. Este tramo no tiene una ruta 3D válida.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Ficha") { onDetails(link) }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                }
                Divider()
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { aimAction(target) }
                VStack(alignment: .leading, spacing: 6) { aimAction(target) }
            }
            if showVirtualWalls {
                Label("Paredes virtuales activas. Los objetos físicos siguen en el cuarto.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func aimAction(_ target: LabSceneTarget?) -> some View {
        Text(target.map { name($0) } ?? "Apunta a un cable, puerto o equipo.")
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let target {
            Button { onInspect(target) } label: {
                Text(actionName(target)).fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func actionName(_ target: LabSceneTarget) -> String {
        if case .link = target { return "¿Adónde va?" }
        return "Inspeccionar"
    }

    private func name(_ target: LabSceneTarget) -> String {
        switch target {
        case .link: return "Cable en la mira"
        case .device(let id): return topology?.devices.first { $0.id == id }?.name ?? id
        case .hardware(let id): return HardwareCatalog.reference(id)?.name ?? id
        case .placement(let id): return layout.placements.first { $0.id == id }?.title ?? id
        }
    }

    private func endpoint(_ title: String, deviceID: String, port: String) -> some View {
        let device = topology?.devices.first { $0.id == deviceID }
        let place = layout.placements.first { $0.id == device?.placementID }?.title
        return VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text("\(device?.name ?? deviceID) · \(device?.sourcePortNames?[port] ?? port)")
                .font(.subheadline.weight(.medium))
            if let place { Text(place).font(.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

private struct PlacementInspector: View {
    let placement: LabPlacement
    let topology: LabTopology?
    var locateTitle = "Ver en 3D"
    var onLocate: ((LabInspectionDestination) -> Void)? = nil
    var console: ((LabTopology.Device) -> LabConsoleView?)? = nil
    var onMonitors: (() -> Void)? = nil
    var rackTools: AnyView? = nil
    var moveDevice: ((LabTopology.Device) -> AnyView?)? = nil
    var onAdjust: (() -> Void)? = nil
    @Binding var poweredOff: Set<String>
    var effectivePowerOff: Set<String> = []
    var devicePowerCut: ((LabTopology.Device) -> Binding<Bool>?)? = nil
    @State private var destination: Destination? = nil

    private enum Destination: Hashable {
        case details(String), terminal(String)

        var deviceID: String {
            switch self { case .details(let id), .terminal(let id): id }
        }
    }

    private var referenceItems: [HardwareItem] {
        let ids = placement.kind == .rack
            ? ["rack-r42612", "switch-2960", "switch-3560", "router-1941", "router-2911", "firewall-asa5505", "server-c220m5"]
            : ["pc-optiplex7010", "laptop-latitude5420", "phone-7960"]
        return ids.compactMap(HardwareCatalog.item)
    }
    var body: some View {
        Form {
            if rackTools != nil || onMonitors != nil || onAdjust != nil {
                Section {
                    if let rackTools { rackTools }
                    if let onAdjust { Button("Ajustar en 3D", systemImage: "move.3d", action: onAdjust) }
                    if let onMonitors { Button("Monitores en RA", systemImage: "display", action: onMonitors) }
                }
            }
            Section {
                if placement.kind == .floor {
                    Label("En el piso · Red pendiente", systemImage: "cable.connector.slash")
                } else {
                    Toggle("Encendido", isOn: Binding(
                        get: { !poweredOff.contains(placement.id) },
                        set: { value in
                            if value { poweredOff.remove(placement.id) }
                            else { poweredOff.insert(placement.id) }
                        }))
                    Text("Controla indicadores y pantallas del equipo virtual.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let topology {
                let devices = topology.devices.filter { $0.placementID == placement.id }
                if !devices.isEmpty {
                    Section("Dispositivos instalados") {
                        ForEach(devices) { device in
                            HStack(spacing: 12) {
                                Button {
                                    destination = .details(device.id)
                                } label: {
                                    Text(device.name).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .buttonStyle(.borderless)
                                if console != nil && !device.modelID.hasPrefix("patch-") && !device.isFanTray {
                                    Button {
                                        destination = .terminal(device.id)
                                    } label: {
                                        Text("CLI").frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Abrir CLI de \(device.name)")
                                    .accessibilityIdentifier("lab.rack.cli.\(device.id)")
                                }
                            }
                        }
                    }
                }
            } else {
                Section("Modelos de referencia") {
                    ForEach(referenceItems) { item in
                        NavigationLink(item.name) { HardwareDetail(item: item) }
                    }
                }
            }
        }
        .navigationDestination(item: $destination) { target in
            if let topology, let device = topology.devices.first(where: { $0.id == target.deviceID }) {
                switch target {
                case .details:
                    DeviceInspector(device: device, topology: topology, locateTitle: locateTitle,
                                    onLocate: onLocate, poweredOff: effectivePowerOff.union(poweredOff),
                                    console: console?(device), powerCut: devicePowerCut?(device))
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if let move = moveDevice?(device) { LabRackMoveLink(destination: move) }
                        }
                case .terminal:
                    console?(device)
                }
            }
        }
        .navigationTitle(placement.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HardwareDetail: View {
    let item: HardwareItem
    var body: some View {
        Form {
            Section {
                Text(item.name).font(.title3.bold())
                Text(item.summary)
            }
            Section("Conexiones") { Text(item.ports) }
            if let size = item.size {
                Section("Dimensiones exteriores") {
                    LabeledContent("Ancho", value: meters(size.x))
                    LabeledContent("Alto", value: meters(size.y))
                    LabeledContent("Fondo", value: meters(size.z))
                }
            }
            Section("Referencia") {
                if let url = item.sourceURL {
                    Link(destination: url) {
                        Label(item.sourceTitle, systemImage: "arrow.up.right.square")
                    }
                } else {
                    Text(item.sourceTitle)
                }
                if let url = item.dimensionsSourceURL {
                    Link("Dimensiones del fabricante", destination: url)
                }
                if item.sourceURL != nil {
                    Text("Representación 3D educativa del exterior; consulta la ficha del fabricante para especificaciones y configuración.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(item.category)
        .navigationBarTitleDisplayMode(.inline)
    }
    private func meters(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(3))) + " m"
    }
}

struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Listo") { dismiss() } }
}
