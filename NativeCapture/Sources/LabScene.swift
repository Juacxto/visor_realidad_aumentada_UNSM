import ARKit
import Observation
import OSLog
import RealityKit
import SwiftUI
import simd

enum LabViewMode: String, CaseIterable, Identifiable {
    case room = "3D", ar = "AR"
    var id: String { rawValue }
}

enum LabSceneTarget: Equatable {
    case link(String), device(String), hardware(String), placement(String)
}

@Observable
final class ARWalkthrough {
    enum Phase: Equatable {
        case preparing, starting, aligning, placing, ready, limited(String), interrupted, failed(String)
    }

    struct Pose: Equatable {
        let position: SIMD2<Float>
        let direction: SIMD2<Float>
    }

    var phase: Phase = .preparing
    var ready: Bool { phase == .ready }
    var pose: Pose?
    var target: LabSceneTarget?
    var focusOrigin: SIMD3<Float>?
    var focusDirection = SIMD3<Float>(0, 0, -1)
    var deviceInSight: String?
    var renderedLinks = Set<String>()
    enum TierCableStatus { case idle, loading, failed }
    var tierCableStatus: TierCableStatus = .idle
    var placementConfirmed = false
    var placementAvailable = false
    @ObservationIgnored var confirmPreview: (() -> Void)?
    var placementHint: String?
    var rackFit: LabRackClearance.Fit?
    var assemblyCableReviews = 0
    var powerRouteReviews: Set<LabARAssembly.Item> = []
    var searchMarker: SearchMarker?

    struct SearchMarker: Equatable {
        let offset: SIMD2<Float>
        let behind: Bool
    }
}

struct LabSceneView: UIViewRepresentable {
    let room: RoomStructure
    let layout: LabLayout
    let arSession: ARSession?
    let mode: LabViewMode
    var paintRoom: Bool
    var fullRoomWalls = false
    var poweredOff: Set<String>
    @Binding var selection: LabPlacement?
    @Binding var trackingMessage: String?
    var onSelectHardware: (String) -> Void = { _ in }
    var topology: LabTopology? = nil
    var showCables: Bool = true
    var visibleCableIDs: Set<String>? = nil
    var selectedLinkID: String? = nil
    var pingLinks: Set<String> = []
    var pingBlockedLink: String? = nil
    var packetJourney: LabPacketJourney? = nil
    var onPacketHop: ((Int) -> Void)? = nil
    /// Hides the failed device's name on its floating label, used by the fair challenge.
    var packetConcealsFailure = false
    var onSelectDevice: (String) -> Void = { _ in }
    var onSelectLink: (String) -> Void = { _ in }
    var onInspectPort: ((LabTopology.Port) -> Void)? = nil
    var onInspectPDU: ((LabARAssembly.Item, Int, Int?) -> Void)? = nil
    var sceneScale: Float = 1
    var arPlacementRequired: Bool = false
    var placementRevision = 0
    var zoomStep: Int = 0
    var orbitReset: Int = 0
    var focusDeviceID: String? = nil
    var inspectionDestination: LabInspectionDestination? = nil
    var inspectionRevision: Int = 0
    var catalystDetail: Catalyst2960Detail? = nil
    var walkthrough: ARWalkthrough? = nil
    var isForeground = true
    var stereoEye: Float = 0
    var virtualPose: LabWalkPose? = nil
    var sceneReady: () -> Void = {}
    var worldPlacementName: String? = nil
    var restoresWorldPlacement = false
    var arFootprint: LabPlacementFootprint? = nil
    var arPlacementOnFloor = false
    var lockedDeviceID: String? = nil
    var showTraffic = true
    var showRackAirflow = false
    var negotiatingLink: String? = nil
    var topologyRevision = 0
    var physicalOcclusion = true
    var monitorConfigurations: [String: LabMonitorConfiguration] = [:]
    var arFocus: LabARFocus = .all
    var showARContext = false
    var assembly: LabARAssembly? = nil
    var selectedAssemblyItem: LabARAssembly.Item? = nil
    var assemblyPlacementRequested = false
    var assemblyEditID: UUID? = nil
    var assemblyRackID: String? = nil
    var assemblyWaypointsEditable = false
    var assemblyPortsEnabled = false
    var assemblyPortSource: LabTopology.Port? = nil
    var assemblyPortDestination: LabTopology.Port? = nil
    var selectableScenePorts: [LabTopology.Port]? = nil
    var equipmentSurface: LabEquipmentSurface? = nil
    var equipmentPreview: LabPlacement? = nil
    var powerOutletRack: LabARAssembly.Item? = nil
    var directPowerOutlets: [LabARAssembly.Item: LabRackPower.Outlet] = [:]
    var placementPreview: LabPlacement? = nil
    var onOrbitHeading: ((Float) -> Void)? = nil
    var onCableReviews: ((Int) -> Void)? = nil
    var onAssemblySelect: (LabARAssembly.Item) -> Void = { _ in }
    var onAssemblyCanPlace: (SIMD3<Float>, Float) -> Bool = { _, _ in true }
    var onAssemblyPosition: (SIMD3<Float>, Float) -> Void = { _, _ in }
    var onAssemblyRackTarget: (String, RackMount.Target) -> Void = { _, _ in }
    var onAssemblyWaypoint: (LabARAssembly.WaypointGesture) -> SIMD2<Float>? = { _ in nil }
    var onAssemblyPort: (LabTopology.Port) -> Void = { _ in }
    var onPowerOutlet: (LabARAssembly.Item, LabRackPower.Outlet?) -> Void = { _, _ in }
    var onEquipmentTarget: (LabEquipmentTarget?) -> Void = { _ in }
    var peerSession: NexusPeerSession? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var isTierAR: Bool { mode == .ar && layout.facility != nil }
    private var isTierMiniature: Bool { isTierAR && assembly == nil && sceneScale <= LabARScale.tenth.factor }
    private var usesCompactTierOverview: Bool { isTierMiniature && arFocus == .all }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ARView {
        let view = LabRenderView(frame: .zero, cameraMode: mode == .ar ? .ar : .nonAR,
                                 automaticallyConfigureSession: false)
        context.coordinator.view = view
        view.didLayout = { [weak coordinator = context.coordinator] size in coordinator?.layoutCamera(to: size) }
        if mode == .ar {
            context.coordinator.connectPlacementControls()
            view.environment.background = .cameraFeed()
            if usesCompactTierOverview { view.contentScaleFactor = 1 }
            if isTierAR {
                view.renderOptions.formUnion([.disableHDR, .disableMotionBlur, .disableDepthOfField,
                                              .disableCameraGrain, .disableGroundingShadows, .disableAREnvironmentLighting])
            }
            if let arSession {
                view.session = arSession
                arSession.delegateQueue = .main
                arSession.delegate = context.coordinator
                if physicalOcclusion, ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    view.environment.sceneUnderstanding.options.insert(.occlusion)
                }
            } else {
                context.coordinator.report("Falta la sesión AR. Vuelve al cuarto o abre su escaneo.")
            }
        } else {
            context.coordinator.updateBackground()
        }
        view.didAttach = { [weak coordinator = context.coordinator] in coordinator?.prepareScene() }
        if mode == .room && virtualPose == nil {
            context.coordinator.installOrbitGestures(in: view)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        context.coordinator.installWaypointGesture(in: view, tap: tap)
        context.coordinator.setupPeerSession(peerSession)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let topologyChanged = context.coordinator.parent.topologyRevision != topologyRevision
        let placementChanged = context.coordinator.parent.placementRevision != placementRevision
        context.coordinator.parent = self
        context.coordinator.setupPeerSession(peerSession)
        if isTierAR {
            let scale = usesCompactTierOverview ? 1 : view.traitCollection.displayScale
            if scale > 0, view.contentScaleFactor != scale { view.contentScaleFactor = scale }
        }
        if mode == .ar { context.coordinator.connectPlacementControls() }
        if mode == .ar && placementChanged { context.coordinator.resetPlacement() }
        if mode == .room { context.coordinator.updateBackground() }
        if mode == .ar, ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            let enabled = view.environment.sceneUnderstanding.options.contains(.occlusion)
            if physicalOcclusion != enabled {
                if physicalOcclusion { view.environment.sceneUnderstanding.options.insert(.occlusion) }
                else { view.environment.sceneUnderstanding.options.remove(.occlusion) }
            }
        }
        guard context.coordinator.canBuildScene else { return }
        if virtualPose != nil {
            if topologyChanged { context.coordinator.rebuildIfNeeded() }
            context.coordinator.updateWalkCamera()
            context.coordinator.updateState()
            return
        }
        if mode == .ar && !isForeground { context.coordinator.hideTrackedContent(); return }
        if context.coordinator.isTierSceneStaged && mode == .ar { return }
        context.coordinator.rebuildIfNeeded()
        context.coordinator.applyZoom()
        context.coordinator.updateState()
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        if view.session.delegate === coordinator { view.session.delegate = nil }
        view.scene.anchors.removeAll()
        coordinator.stopRendering()
        // CaptureController owns session lifetime. Changing view must not pause or reset it.
    }

    final class Coordinator: NSObject, ARSessionDelegate, UIGestureRecognizerDelegate {
        var parent: LabSceneView
        weak var view: ARView?
        private var lastRoomID: UUID?
        private var lastPlacements: [LabPlacement] = []
        private var lastRackMonitors: [String: [LabARAssembly.RackMonitor]]?
        private var lastRoomAccessories: [LabARAssembly.Piece]?
        private var lastRackPDUs: [String: LabRackPower.Configuration]?
        private var lastTopology: LabTopology?
        private var lastFacility: TierFacility?
        private var lastCompactTierOverview = false
        private var roomEntity: Entity?
        private var roomUsesWallCutaway = false
        private var rootAnchor: AnchorEntity?
        private var scaledContent: Entity?
        private var placementModels: [String: Entity] = [:]
        private var placementShells: [String: Entity] = [:]
        private var deviceModels: [String: Entity] = [:]
        private static let catalystLightName = "catalyst-light"
        private weak var catalystHost: Entity?
        private weak var catalystTemplate: Entity?
        private var catalystOverride: Entity?
        private var facilityModel: Entity?
        private var facilityFixtures: [String: Entity] = [:]
        private var assemblyAccessories: [LabARAssembly.Item: Entity] = [:]
        private var renderedAssembly: LabARAssembly?
        private var wiredAssembly: LabARAssembly?
        private var wiredAssemblyLinks: [LabTopology.Link]?
        private var wiredTraceID: String?
        private weak var waypointPan: UIPanGestureRecognizer?
        private var waypointHandles: [ModelEntity] = []
        private var waypointHandleRoot: Entity?
        private var waypointHandleLinkID: String?
        private var waypointGrip: WaypointGrip?
        private var rackGuide: Entity?
        private var guidedRackID: String?
        private var portIndicators: [Entity] = []
        private var openPortMarkers: [Entity] = []
        private var markedOpenPorts: [LabTopology.Port]?
        private var equipmentOutline: ModelEntity?
        private var equipmentOutlineSize: SIMD3<Float>?
        private var indicatedPorts: [LabTopology.Port] = []
        private var assemblyRoutingTask: Task<Void, Never>?
        private var focusOrigin = SIMD3<Float>.zero
        private var awaitingPlacement = false
        private var placedAnchorID: UUID?
        private weak var placementWalkthrough: ARWalkthrough?
        private var previewAnchor: AnchorEntity?
        private var previewFootprint: LabPlacementFootprint?
        private var previewTransform: simd_float4x4?
        private var previewBlocked = false
        private var previewRackFit: LabRackClearance.Fit?
        private var tracking = false
        private(set) var canBuildScene = false
        private var prepareTask: Task<Void, Never>?
        private var lastFrameTime = -Double.infinity
        private var lastPlacementFrameTime = -Double.infinity
        private var lastSearchFrameTime = -Double.infinity
        private var cablesEntity: Entity?
        private var roomCablingTask: Task<Void, Never>?
        private var tierCableTask: Task<Void, Never>?
        private var tierCablesLoaded = false
        private var tierTrace: ModelEntity?
        private var stagedTierRoom: UUID?
        var isTierSceneStaged: Bool { stagedTierRoom != nil }
        private var portLabelsEntity: Entity?
        private var lastSelectedLinkID: String?
        private var lastVisibleCableIDs: Set<String>?
        private var lastPingLinks: Set<String>?
        private var lastPingBlockedLink: String?
        private var pingPaths: [String: [SIMD3<Float>]] = [:]
        private var pingOverlay: Entity?
        private var lastPacketJourney: LabPacketJourney?
        private var packetEntity: Entity?
        private var packetCore: ModelEntity?
        private var packetHalo: ModelEntity?
        private var packetTask: Task<Void, Never>?
        private var lastPacketConceals = false
        private var packetTrail: [ModelEntity] = []
        private var packetTrailHistory: [SIMD3<Float>] = []
        private var packetLabels: [Entity] = []
        private var packetLabelMaterials: [String: UnlitMaterial] = [:]
        private var lastInspectedPort: LabInspectionDestination?
        private var lastInspectionRevision: Int?
        private var linkBodies: [String: ModelEntity] = [:]
        private var linkEntities: [String: Entity] = [:]
        private var cableGuides: Entity?
        private var tracedCables: [ModelEntity] = []
        private var deviceHighlights: [String: Entity] = [:]
        private var highlightedDevice: Entity?
        private var lastLockedDeviceID: String?
        private var lastWalkPose: LabWalkPose?
        private var lastWalkLock: String?
        private var cameraTurn: AnimationPlaybackController?

        private struct TrafficCircuit {
            let id: String
            let links: Set<String>
            let devices: Set<String>
            let terminals: [LabTopology.Port]
            let route: LabTrafficRoute
            let cableRadius: Float
        }

        private struct TrafficSettings: Equatable {
            let enabled: Bool
            let visibleLinks: Set<String>?
            let reducedMotion: Bool
            let poweredOff: Set<String>
            let links: [LabTopology.Link]
            let assembly: LabARAssembly?
            let showAirflow: Bool
            let negotiatingLink: String?
            let visible: Bool
            let trace: String?
            let focus: String?
            let monitors: [String: LabMonitorConfiguration]
            let samplesMonitors: Bool
        }

        private struct Dashboard {
            let device: LabTopology.Device
            let face: ModelEntity
            var panel: LabMonitorConfiguration.Panel?
            var owner: LabARAssembly.Item?
            var frame: DashboardFrame?
            var texture: TextureResource?
        }

        private struct WaypointGrip {
            let index: Int
            let linkID: String
            let height: Float
            let offset: SIMD3<Float>
            var point: SIMD3<Float>
        }

        private struct DashboardFrame: Equatable {
            let configuration: LabMonitorConfiguration
            let state: LabServerSample.State
            let values: [Double]
            let services: [String]
        }

        private var trafficCircuits: [TrafficCircuit] = []
        private var portLamps: [LabTopology.Port: ModelEntity] = [:]
        private var portLampMesh: MeshResource?
        private var pduHits: [ObjectIdentifier: (rack: LabARAssembly.Item, circuit: Int, heights: [Float])] = [:]
        private var pduLamps: [(rack: LabARAssembly.Item, upsID: String?, entity: ModelEntity)] = []
        private var fanTrays: [String: (rotors: [Entity], airflow: Entity)] = [:]
        private var trafficSettings: TrafficSettings?
        private var activeTraffic: [Int] = []
        private var pulsePairs: [[ModelEntity]] = []
        private var trafficTask: Task<Void, Never>?
        private var portHits: [ObjectIdentifier: LabScenePort] = [:]
        private var devicePowerParents: [String: String] = [:]
        private var indicators: [String: [ModelEntity]] = [:]
        private var screens: [String: [ModelEntity]] = [:]
        private var consoleScreens: [String: [Entity]] = [:]
        private var dashboards: [Dashboard] = []
        private var lastDashboardTick: TimeInterval?
        private lazy var dashboardRenderer: UIGraphicsImageRenderer = {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: LabMonitorMount.faceSize, format: format)
        }()
        private var highlights: [String: Entity] = [:]
        private var hardwareTemplates: [String: Entity] = [:]
        private var hardwareMeshScratch: [String: [LabSceneMesh]] = [:]
        private var labelMaterials: [String: UnlitMaterial] = [:]
        private var renderError: String?
        private var lastPoweredOff: Set<String>?
        private weak var selectedHardwareHighlight: Entity?
        private var camera: PerspectiveCamera?
        private var cameraTarget = SIMD3<Float>.zero
        private var defaultCameraTarget = SIMD3<Float>.zero
        private var cameraRadius: Float = 6
        private var cameraYaw: Float = .pi / 4
        private var notifiedOrbitHeading: Float?
        private var previewedPlacement: LabPlacement?
        private var roomRoutingTask: Task<Void, Never>?
        private var previewCableEntity: Entity?
        private var previewPowerEntity: Entity?
        private var failedRoomPreview: LabPlacement?
        private var committedCableReviews = 0
        private var cameraPitch: Float = 0.75
        private var orbitTouchCount = 0
        private var cameraBounds: [SIMD3<Float>] = []
        private var lastColorScheme: ColorScheme?
        private let orbitFieldOfView: Float = 55
        private var cameraMoved = false
        private var lastZoomStep = 0
        private var lastOrbitReset: Int
        private var lastFocusKey: String?
        private let materials = LabSceneMaterials()

        init(parent: LabSceneView) {
            self.parent = parent
            lastOrbitReset = parent.orbitReset
        }

        func updateBackground() {
            guard let view, lastColorScheme != parent.colorScheme else { return }
            lastColorScheme = parent.colorScheme
            let background: UIColor
            if parent.stereoEye != 0 { background = .black }
            else if parent.colorScheme == .dark { background = UIColor(red: 0.09, green: 0.12, blue: 0.16, alpha: 1) }
            else { background = UIColor(red: 0.91, green: 0.93, blue: 0.95, alpha: 1) }
            view.environment.background = .color(background)
        }

        func prepareScene() {
            guard prepareTask == nil, !canBuildScene, parent.mode == .room || parent.arSession != nil else { return }
            prepareTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                guard let self, let view, view.window != nil else {
                    self?.prepareTask = nil
                    return
                }
                canBuildScene = true
                prepareTask = nil
                rebuildIfNeeded()
            }
        }

        func stopRendering() {
            waypointGrip = nil
            prepareTask?.cancel()
            trafficTask?.cancel()
            packetTask?.cancel()
            tierCableTask?.cancel()
            roomCablingTask?.cancel()
            assemblyRoutingTask?.cancel()
            roomRoutingTask?.cancel()
            cameraTurn?.stop()
            view = nil
        }

        func resetPlacement() {
            awaitingPlacement = parent.arPlacementRequired
            placedAnchorID = nil
            hideTrackedContent()
        }

        func connectPlacementControls() {
            guard let walkthrough = parent.walkthrough, walkthrough !== placementWalkthrough else { return }
            placementWalkthrough = walkthrough
            walkthrough.confirmPreview = { [weak self] in self?.confirmARPreview() }
        }

        func installWaypointGesture(in view: ARView, tap: UITapGestureRecognizer) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(dragWaypoint(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)
            tap.require(toFail: pan)
            waypointPan = pan
        }

        func installOrbitGestures(in view: ARView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.maximumNumberOfTouches = 3
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            let twist = UIRotationGestureRecognizer(target: self, action: #selector(twist(_:)))
            let reset = UITapGestureRecognizer(target: self, action: #selector(resetWithFourFingers(_:)))
            reset.numberOfTouchesRequired = 4
            for recognizer in [pan, pinch, twist, reset] as [UIGestureRecognizer] {
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
            view.isAccessibilityElement = true
            view.accessibilityLabel = "Escena 3D"
            view.accessibilityCustomActions = [
                orbitAccessibilityAction("Girar vista a la izquierda", delta: SIMD2(0.18, 0)),
                orbitAccessibilityAction("Girar vista a la derecha", delta: SIMD2(-0.18, 0)),
                orbitAccessibilityAction("Elevar la vista", delta: SIMD2(0, 0.15)),
                orbitAccessibilityAction("Bajar la vista", delta: SIMD2(0, -0.15)),
                UIAccessibilityCustomAction(name: "Restablecer encuadre") { [weak self, weak view] _ in
                    guard let self, let view else { return false }
                    resetOrbit(to: view.bounds.size)
                    return true
                }
            ]
        }

        private func orbitAccessibilityAction(_ name: String, delta: SIMD2<Float>) -> UIAccessibilityCustomAction {
            UIAccessibilityCustomAction(name: name) { [weak self] _ in
                guard let self else { return false }
                rotateOrbit(by: delta)
                return true
            }
        }

        func rebuildIfNeeded() {
            if parent.isTierAR, lastRoomID == nil,
               parent.arPlacementRequired ? parent.walkthrough?.placementConfirmed != true : !tracking {
                if stagedTierRoom == nil, let view {
                    let anchor = AnchorEntity(world: .zero)
                    anchor.isEnabled = false
                    view.scene.addAnchor(anchor)
                    rootAnchor = anchor
                    stagedTierRoom = parent.room.roomID
                    awaitingPlacement = parent.arPlacementRequired
                }
                return
            }
            guard let view, lastCompactTierOverview != parent.usesCompactTierOverview
                    || lastRoomID != parent.room.roomID || lastPlacements != parent.layout.placements
                    || lastTopology != parent.topology || lastFacility != parent.layout.facility
                    || lastRackMonitors != parent.layout.rackMonitors || lastRoomAccessories != parent.layout.accessories
                    || lastRackPDUs != parent.layout.rackPDUs else { return }
            if parent.assembly != nil, lastRoomID == parent.room.roomID, lastPlacements == parent.layout.placements,
               lastRackMonitors == parent.layout.rackMonitors, lastRoomAccessories == parent.layout.accessories,
               lastFacility == parent.layout.facility, lastRackPDUs == parent.layout.rackPDUs,
               var previous = lastTopology, let topology = parent.topology {
                previous.links = topology.links
                if previous == topology {
                    // A cable edit replaces only the cable mesh. Keep the equipment and AR anchor in place.
                    lastTopology = topology
                    return
                }
            }
            let reframe = lastRoomID != parent.room.roomID || lastPlacements.map(\.id) != parent.layout.placements.map(\.id)
            let keepsPlacement = parent.mode == .ar && (lastRoomID == parent.room.roomID || stagedTierRoom == parent.room.roomID) &&
                rootAnchor != nil && parent.walkthrough?.placementConfirmed == true && !awaitingPlacement
            let previousTransform = keepsPlacement ? rootAnchor?.transform : nil
            let wasVisible = rootAnchor?.isEnabled == true
            defer { hardwareMeshScratch.removeAll() }
            do {
                if let topology = parent.topology {
                    guard topology.devices.count <= 96, topology.links.count <= 192 else {
                        throw LabLayoutError.invalid("La vista admite hasta 96 dispositivos y 192 conexiones.")
                    }
                    try topology.validate()
                }
                let anchor = AnchorEntity(world: .zero)
                let content = Entity()
                anchor.addChild(content)
                let cutaway = parent.mode == .room && parent.virtualPose == nil && !parent.fullRoomWalls
                let structure = parent.assembly == nil ? try makeRoom(cutaway: cutaway) : Entity()
                content.addChild(structure)
                indicators.removeAll(); screens.removeAll(); consoleScreens.removeAll(); dashboards.removeAll(); highlights.removeAll()
                deviceHighlights.removeAll()
                highlightedDevice = nil
                lastLockedDeviceID = nil
                lastWalkPose = nil
                trafficTask?.cancel(); trafficTask = nil
                activeTraffic.removeAll(); trafficCircuits.removeAll(); pulsePairs.removeAll(); trafficSettings = nil
                portLamps.removeAll(); fanTrays.removeAll(); pduHits.removeAll(); pduLamps.removeAll()
                roomCablingTask?.cancel(); roomCablingTask = nil
                tierCableTask?.cancel(); tierCableTask = nil
                tierCablesLoaded = false
                tierTrace = nil
                portHits.removeAll(); devicePowerParents.removeAll(); linkBodies.removeAll(); tracedCables.removeAll()
                linkEntities.removeAll(); cableGuides = nil; lastVisibleCableIDs = nil
                pingPaths.removeAll(); pingOverlay = nil
                packetTask?.cancel(); packetTask = nil
                packetEntity = nil; packetCore = nil; packetHalo = nil; lastPacketJourney = nil
                packetTrail.removeAll(); packetTrailHistory.removeAll(); packetLabels.removeAll()
                placementModels.removeAll(); placementShells.removeAll(); deviceModels.removeAll()
                previewedPlacement = nil
                failedRoomPreview = nil
                roomRoutingTask?.cancel(); roomRoutingTask = nil
                previewCableEntity?.removeFromParent(); previewCableEntity = nil
                previewPowerEntity?.removeFromParent(); previewPowerEntity = nil
                assemblyAccessories.removeAll()
                assemblyRoutingTask?.cancel()
                assemblyRoutingTask = nil
                renderedAssembly = nil
                wiredAssembly = nil
                wiredAssemblyLinks = nil
                wiredTraceID = nil
                waypointHandles.removeAll()
                waypointHandleRoot = nil
                waypointHandleLinkID = nil
                rackGuide = nil
                guidedRackID = nil
                portIndicators.removeAll()
                openPortMarkers.removeAll()
                markedOpenPorts = nil
                equipmentOutline = nil
                equipmentOutlineSize = nil
                indicatedPorts.removeAll()
                lastDashboardTick = nil
                guard parent.layout.placements.filter({ $0.kind == .rack }).count <= 12,
                      parent.layout.placements.filter({ $0.kind == .workstation }).count <= 24 else {
                    throw LabLayoutError.invalid("La vista admite hasta 12 racks y 24 puestos.")
                }
                electricalLeads.removeAll()
                powerFeeds = nil
                renderedPowerAssembly = nil
                for placement in parent.layout.placements {
                    let object = try autoreleasepool { try makePlacement(placement) }
                    content.addChild(object)
                    placementModels[placement.id] = object
                }
                electricalEntity = nil
                if parent.assembly == nil {
                    try updatePowerFeeds(directPowerAssembly(), in: content)
                }
                facilityModel = nil
                facilityFixtures.removeAll()
                if let facility = parent.layout.facility, parent.assembly == nil {
                    let model = try makeFacility(facility)
                    content.addChild(model)
                    facilityModel = model
                    for fixture in facility.fixtures {
                        let object = try makeTierFixture(fixture)
                        object.position = facility.world(fixture.position)
                        object.orientation = simd_quatf(angle: facility.yaw + fixture.yaw, axis: SIMD3(0, 1, 0))
                        content.addChild(object)
                        facilityFixtures[fixture.id] = object
                    }
                }
                if parent.assembly == nil {
                    for part in parent.layout.accessories ?? [] {
                        let object: Entity
                        switch part.id {
                        case .extra(let model, _):
                            object = try makeAssemblyAccessory(model, pduConfiguration: parent.layout.pduConfiguration(for: part.id.name),
                                                               rackOwner: part.id)
                            object.name = "hardware:" + model
                        case .monitor(let id, let panel, _):
                            guard let device = parent.topology?.devices.first(where: { $0.id == id }) else { continue }
                            object = makeAssemblyMonitor(device, panel: panel, owner: part.id, mount: nil)
                            object.name = "device:" + id
                        default: continue
                        }
                        object.position = part.position
                        object.orientation = part.rotation
                        content.addChild(object)
                    }
                }
                if let topology = parent.topology, parent.assembly == nil {
                    let cables = Entity()
                    cables.name = "Cableado del diseño"
                    content.addChild(cables)
                    cablesEntity = cables
                    if parent.mode == .ar && !parent.isTierAR {
                        let plan = try LabCablePlan.make(topology, room: parent.room, layout: parent.layout)
                        try installCables(plan, for: topology, in: cables)
                    }
                    let labels = Entity(); content.addChild(labels); portLabelsEntity = labels
                } else {
                    cablesEntity = nil; portLabelsEntity = nil
                    reportCableReviews(0)
                }
                let light = DirectionalLight()
                light.light.intensity = 1800
                light.look(at: SIMD3(0, -1, 0), from: SIMD3(2, 6, -3), relativeTo: nil)
                anchor.addChild(light)
                let fill = DirectionalLight()
                fill.light.intensity = 900
                fill.look(at: SIMD3(0, -1, 0), from: SIMD3(-3, 5, 4), relativeTo: nil)
                anchor.addChild(fill)
                if parent.mode == .room {
                    if reframe || camera == nil {
                        let polygon = parent.layout.floorPolygon
                        let lower = polygon.reduce(SIMD2<Float>(repeating: .infinity), simd_min)
                        let upper = polygon.reduce(SIMD2<Float>(repeating: -.infinity), simd_max)
                        let floor = parent.layout.floorHeight
                        let height = parent.layout.facility?.height ?? max(0.65, parent.layout.placements.map(\.size.y).max() ?? 0)
                        cameraTarget = SIMD3((lower.x + upper.x) / 2, floor + height * 0.38, (lower.y + upper.y) / 2)
                        defaultCameraTarget = cameraTarget
                        cameraBounds = polygon.flatMap { point in
                            [SIMD3(point.x, floor, point.y), SIMD3(point.x, floor + height, point.y)]
                        }
                        cameraMoved = false
                        (cameraYaw, cameraPitch) = initialOrbit
                    }
                    let camera = PerspectiveCamera()
                    camera.camera.fieldOfViewInDegrees = parent.virtualPose == nil ? orbitFieldOfView : 60
                    if #available(iOS 18, *) { camera.camera.fieldOfViewOrientation = .vertical }
                    camera.camera.near = 0.03
                    camera.camera.far = 250
                    self.camera = camera
                    if parent.virtualPose != nil { updateWalkCamera() }
                    anchor.addChild(camera)
                }
                view.scene.anchors.removeAll()
                previewAnchor = nil
                previewFootprint = nil
                previewTransform = nil
                scaledContent = content
                awaitingPlacement = parent.mode == .ar && parent.arPlacementRequired && !keepsPlacement
                if let previousTransform { anchor.transform = previousTransform }
                anchor.isEnabled = parent.mode == .room || (keepsPlacement && wasVisible)
                view.scene.addAnchor(anchor)
                rootAnchor = anchor
                if parent.mode == .room && parent.virtualPose == nil {
                    updateCamera()
                    fitCamera(to: view.bounds.size)
                }
                roomEntity = structure
                roomUsesWallCutaway = cutaway
                lastRoomID = parent.room.roomID
                stagedTierRoom = nil
                lastPlacements = parent.layout.placements
                lastRackMonitors = parent.layout.rackMonitors
                lastRoomAccessories = parent.layout.accessories
                lastRackPDUs = parent.layout.rackPDUs
                lastTopology = parent.topology
                lastFacility = parent.layout.facility
                lastCompactTierOverview = parent.usesCompactTierOverview
                lastSelectedLinkID = nil
                lastPingLinks = nil
                lastPingBlockedLink = nil
                lastInspectedPort = nil
                lastInspectionRevision = nil
                lastPoweredOff = nil
                renderError = nil
                if parent.mode == .room { report(nil) }
                updateState()
                if parent.mode == .room, let topology = parent.topology, let cablesEntity {
                    loadRoomCables(topology, in: cablesEntity)
                }
                if parent.virtualPose != nil {
                    Task { @MainActor [weak self] in self?.parent.sceneReady() }
                }
                if parent.mode == .ar {
                    parent.walkthrough?.renderedLinks = Set(linkBodies.keys)
                    let state = view.session.currentFrame?.camera.trackingState
                    if state == nil { suspend(.starting) }
                }
            } catch { renderError = error.localizedDescription; report(error.localizedDescription) }
        }

        private func makeRoom(cutaway: Bool) throws -> Entity {
            var batch = LabSceneMesh(), floor = LabSceneMesh()
            let surfaces = parent.room.surfaces
            let openings = surfaces.filter { [.window, .door, .opening].contains($0.kind) }
            let holesByWall = Dictionary(grouping: openings, by: \.parentID)
            for surface in surfaces {
                guard surface.curve == nil else { throw LabLayoutError.invalid("La vista todavía no admite superficies curvas. Corrige esa captura.") }
                let matrix = try LabGeometry.matrix(surface)
                if surface.kind == .floor {
                    let points = try surface.polygonCorners.map { corner -> SIMD3<Float> in
                        guard corner.count == 3, corner.allSatisfy(\.isFinite) else {
                            throw LabLayoutError.invalid("Esquina de suelo inválida.")
                        }
                        let point = matrix * SIMD4(corner[0], corner[1], corner[2], 1)
                        return SIMD3(point.x, point.y, point.z)
                    }
                    var indices = try LabGeometry.triangulate(points.map { SIMD2($0.x, $0.z) })
                    for i in stride(from: 0, to: indices.count, by: 3) {
                        let a = points[Int(indices[i])], b = points[Int(indices[i + 1])], c = points[Int(indices[i + 2])]
                        if simd_cross(b - a, c - a).y < 0 { indices.swapAt(i + 1, i + 2) }
                    }
                    floor.append(positions: points, normals: Array(repeating: SIMD3(0, 1, 0), count: points.count), indices: indices.map(UInt32.init))
                } else if surface.kind == .wall {
                    guard surface.polygonCorners.isEmpty, surface.dimensions[2] <= 0.005 else {
                        throw LabLayoutError.invalid("Muro no rectangular o no plano: la vista no cerrará ese contorno por aproximación.")
                    }
                    let holes = try (holesByWall[surface.id] ?? []).map { try holeRect($0, wall: surface) }
                    guard holes.count <= 32 else { throw LabLayoutError.invalid("Demasiadas aberturas en una pared.") }
                    let halfW = surface.dimensions[0] / 2, halfH = surface.dimensions[1] / 2
                    let cutHeight = parent.layout.floorHeight + 0.65
                    let localCut = matrix.columns.1.y > 0
                        ? (cutHeight - matrix.columns.3.y) / matrix.columns.1.y : halfH
                    let visibleTop = cutaway ? min(halfH, max(-halfH, localCut)) : halfH
                    if visibleTop <= -halfH { continue }
                    let xs = Array(Set([-halfW, halfW] + holes.flatMap { [Float($0.minX), Float($0.maxX)] })).sorted()
                    let ys = Array(Set([-halfH, visibleTop] + holes.flatMap { [Float($0.minY), Float($0.maxY)] }
                        .filter { $0 > -halfH && $0 < visibleTop })).sorted()
                    for x in 0..<(xs.count - 1) {
                        for y in 0..<(ys.count - 1) {
                            let width = xs[x + 1] - xs[x], height = ys[y + 1] - ys[y]
                            let center = SIMD3((xs[x] + xs[x + 1]) / 2, (ys[y] + ys[y + 1]) / 2, 0)
                            if width > 0.00001, height > 0.00001,
                               !holes.contains(where: { $0.contains(CGPoint(x: CGFloat(center.x), y: CGFloat(center.y))) }) {
                                // ponytail: 8 cm is visual thickness, never a measured building property.
                                batch.box(size: SIMD3(width, height, 0.08), center: center, matrix: matrix)
                            }
                        }
                    }
                }
            }
            for opening in openings {
                guard surfaces.contains(where: { $0.kind == .wall && $0.id == opening.parentID }) else {
                    throw LabLayoutError.invalid("Hay una abertura sin pared padre. No se representará como muro cerrado.")
                }
            }
            let entity = Entity()
            entity.name = "Paredes y suelo del cuarto"
            let tier = parent.layout.facility != nil
            if !batch.indices.isEmpty { entity.addChild(try batch.model(material: tier ? materials.facilityWall : materials.white)) }
            if !floor.indices.isEmpty { entity.addChild(try floor.model(material: tier ? materials.facilityFloor : materials.white)) }
            return entity
        }

        private func makeFacility(_ facility: TierFacility) throws -> Entity {
            let root = Entity()
            root.position = facility.origin
            root.orientation = simd_quatf(angle: facility.yaw, axis: SIMD3(0, 1, 0))
            var partitions = LabSceneMesh(), coldAisle = LabSceneMesh(), hotAisle = LabSceneMesh()
            let cutaway = parent.mode == .room && parent.virtualPose == nil
            let wallHeight = cutaway ? 0.47 : facility.height - 0.23
            func panel(_ x: Float, _ z: Float, _ width: Float, _ depth: Float) {
                partitions.box(size: SIMD3(width, wallHeight, depth), center: SIMD3(x, wallHeight / 2, z))
            }
            // Leave the 1.5 m operator opening and technical access at the ends of the two bay walls.
            panel(-0.55, 2.67, 9.6, 0.12)
            panel(6.18, 2.67, 0.86, 0.12)
            panel(5.17, -2.91, 0.12, 3.28)
            if cutaway {
                panel(-5.17, -2.91, 0.12, 3.28)
            } else {
                let penetration = TierFacility.conduitAZ
                let zLimits: [Float] = [-4.55, penetration - 0.065, penetration + 0.065, -1.27]
                for (start, end) in [(zLimits[0], zLimits[1]), (zLimits[2], zLimits[3])] {
                    panel(-5.17, (start + end) / 2, 0.12, end - start)
                }
                let lower = facility.conduitHeight - 0.065, upper = facility.conduitHeight + 0.065
                partitions.box(size: SIMD3(0.12, lower, 0.13), center: SIMD3(-5.17, lower / 2, penetration))
                if upper < wallHeight {
                    partitions.box(size: SIMD3(0.12, wallHeight - upper, 0.13),
                                   center: SIMD3(-5.17, (wallHeight + upper) / 2, penetration))
                }
            }
            root.addChild(try partitions.model(material: materials.facilityWall))
            coldAisle.box(size: SIMD3(9, 0.002, 1.52), center: SIMD3(0, 0.002, -0.57))
            for z: Float in [-3.46, 2.12] {
                hotAisle.box(size: SIMD3(9, 0.002, 0.82), center: SIMD3(0, 0.002, z))
            }
            root.addChild(try coldAisle.model(material: materials.coldAisle))
            root.addChild(try hotAisle.model(material: materials.hotAisle))
            var grilles = LabSceneMesh()
            var louvers = LabSceneMesh()
            for column in -2...2 {
                let x = Float(column) * 1.6
                grilles.box(size: SIMD3(0.51, 0.008, 0.44), center: SIMD3(x, 0.005, -0.57))
                for row in 0..<10 {
                    louvers.box(size: SIMD3(0.465, 0.003, 0.011), center: SIMD3(x, 0.011, -0.75 + Float(row) * 0.04))
                }
            }
            root.addChild(try grilles.model(material: materials.metal))
            root.addChild(try louvers.model(material: materials.dark))


            for (name, x, z) in [("PASILLO FRÍO", Float(0), Float(-0.59)), ("PASILLO CALIENTE", 0, -3.47),
                                 ("OPERACIÓN · VLAN 20", 0, 5.03)] {
                let sign = try label(name, width: 1.75, height: 0.17)
                sign.position = SIMD3(x, 0.006, z)
                sign.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
                root.addChild(sign)
            }
            let power = try makeElectricalRoutes(facility, placements: parent.layout.placements)
            root.addChild(power)
            electricalEntity = power
            if parent.mode == .room, parent.room.source.contains("sintética") {
                for side: Float in [-1, 1] {
                    let generator = try makeExteriorGenerator(side < 0 ? "A" : "B")
                    generator.position = SIMD3(side * 8.78, 0, -3.78)
                    root.addChild(generator)
                }
            }
            return root
        }

        private func makeExteriorGenerator(_ path: String) throws -> Entity {
            let entity = Entity()
            var pad = LabSceneMesh()
            pad.box(size: SIMD3(1.63, 0.06, 2.71), center: SIMD3(0, 0.03, 0))
            entity.addChild(try pad.model(material: materials.facilityFloor))
            var enclosure = LabSceneMesh(), details = LabSceneMesh(), ventilation = LabSceneMesh()
            enclosure.box(size: SIMD3(1.22, 1.36, 2.28), center: SIMD3(0, 0.85, 0))
            details.box(size: SIMD3(1.33, 0.14, 2.42), center: SIMD3(0, 0.09, 0))
            details.box(size: SIMD3(0.48, 0.89, 0.025), center: SIMD3(-0.24, 0.84, -1.153))
            details.box(size: SIMD3(0.065, 0.08, 0.018), center: SIMD3(-0.06, 0.84, -1.169))
            ventilation.tube(from: SIMD3(0.32, 1.50, 0.72), to: SIMD3(0.32, 1.81, 0.72), radius: 0.05)
            for fin in 0..<19 {
                ventilation.box(size: SIMD3(0.36, 0.018, 0.024),
                                center: SIMD3(0.32, 0.50 + Float(fin) * 0.037, -1.153))
            }
            entity.addChild(try enclosure.model(material: materials.graphite))
            entity.addChild(try details.model(material: materials.metal))
            entity.addChild(try ventilation.model(material: materials.dark))
            let plate = try label("GENERACIÓN " + path + " · EXTERIOR", width: 1.03, height: 0.11)
            plate.position = SIMD3(0, 1.37, -1.17)
            entity.addChild(plate)
            return entity
        }

        private func makeTierFixture(_ fixture: TierFixture) throws -> Entity {
            switch fixture.kind {
            case .cooling:
                return try makeAssemblyAccessory("cooling-inrow", circuit: fixture.circuit)
            case .batteryBank:
                let cabinet = try makeAssemblyAccessory("battery-bank", circuit: fixture.circuit)
                let size = fixture.kind.size
                let title = try label("UPS + BATERÍAS " + fixture.circuit, width: 0.51, height: 0.027)
                title.position = SIMD3(0, size.y - 0.026, -size.z / 2 - 0.003)
                cabinet.addChild(title)
                return cabinet
            case .switchboard:
                let object = Entity()
                let size = fixture.kind.size
                let center = SIMD3<Float>(0, size.y / 2, 0)
                var cabinet = LabSceneMesh(), breakers = LabSceneMesh()
                cabinet.box(size: size, center: center)
                for row in 0..<3 {
                    for column in 0..<4 {
                        breakers.box(size: SIMD3(0.032, 0.044, 0.012),
                            center: center + SIMD3((Float(column) - 1.5) * 0.047, 0.24 - Float(row) * 0.19, 0.122))
                    }
                }
                object.addChild(try cabinet.model(material: materials.panel))
                object.addChild(try breakers.model(material: materials.dark))
                let title = try label("TABLERO " + fixture.circuit + " · ENTRADA EXTERIOR", width: 0.45, height: 0.028)
                title.position = center + SIMD3(0, 0.58, 0.124)
                title.orientation = simd_quatf()
                object.addChild(title)
                object.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: center)]))
                return object
            }
        }

        private func makeFacilityEquipment(_ id: String, circuit: String) throws -> Entity {
            let size = HardwareCatalog.reference(id)!.size!
            let entity = Entity()
            entity.name = "hardware:" + id
            entity.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: size)]))
            var chassis = LabSceneMesh(), grate = LabSceneMesh(), status = LabSceneMesh()
            chassis.box(size: size, center: .zero)
            let cooling = id == "cooling-inrow", front = -size.z / 2 - 0.002
            let rows = cooling ? 43 : 4
            for row in 0..<rows {
                let y = (Float(row) / Float(rows - 1) - 0.5) * size.y * 0.77
                for face: Float in [-1, 1] {
                    grate.box(size: SIMD3(size.x * (cooling ? 0.77 : 0.57), cooling ? 0.012 : 0.004, 0.004),
                              center: SIMD3(cooling ? 0 : 0.045, y, face * (size.z / 2 + 0.002)))
                }
            }
            let screenY = cooling ? size.y * 0.43 : 0
            status.box(size: SIMD3(cooling ? 0.065 : 0.024, cooling ? 0.029 : 0.013, 0.004),
                       center: SIMD3(cooling ? 0 : -0.126, screenY, front - 0.002))
            if id == LabRackPower.upsModel {
                let sockets = [LabRackPower.upsSocket(at: .zero)] + (0..<2).map { LabRackPower.upsSocket(at: .zero, output: $0) }
                for socket in sockets { grate.box(size: SIMD3(0.025, 0.018, 0.005), center: socket - SIMD3(0, 0, 0.004)) }
            }
            entity.addChild(try chassis.model(material: materials.graphite))
            entity.addChild(try grate.model(material: materials.dark))
            entity.addChild(try status.model(material: circuit == "A" ? materials.powerA : materials.powerB))
            let name = cooling ? "INROW \(circuit)" : id == "ups-9px" ? "9PX · UPS \(circuit)" : "72 V · BATERÍA \(circuit)"
            let sign = try label(name, width: cooling ? 0.22 : 0.16, height: cooling ? 0.028 : 0.012)
            sign.position = SIMD3(cooling ? 0 : -0.10, cooling ? size.y * 0.47 : 0.027, front - 0.003)
            entity.addChild(sign)
            return entity
        }

        private var electricalEntity: Entity?
        private var electricalLeads: [String: Entity] = [:]
        private var powerFeeds: Entity?
        private var renderedPowerAssembly: LabARAssembly?
        private var externalUPSSources: [LabARAssembly.Item: LabRackPower.Endpoint] = [:]

        private func directPowerAssembly() -> LabARAssembly {
            var assembly = LabARAssembly(roomLayout: parent.layout)
            for (rack, outlet) in parent.directPowerOutlets { assembly.setPowerOutlet(outlet, for: rack) }
            return assembly
        }

        private func updatePowerFeeds(_ assembly: LabARAssembly, in content: Entity) throws {
            let plan = assembly.powerFeedPlan(in: parent.layout, topology: parent.topology)
            let root = Entity()
            var wires = [LabSceneMesh(), LabSceneMesh()]
            for lead in plan.leads { wires[lead.circuit].cable(lead.points, radius: 0.005) }
            for (index, wire) in wires.enumerated() where !wire.indices.isEmpty {
                root.addChild(try wire.model(material: index == 0 ? materials.powerA : materials.powerB))
            }
            for (_, outlet) in assembly.powerOutlets ?? [:] {
                let marker = ModelEntity(mesh: .generateBox(size: SIMD3(0.048, 0.034, 0.008), cornerRadius: 0.004),
                                         materials: [materials.accent])
                marker.position = outlet.position + outlet.normal * 0.009
                marker.orientation = simd_quatf(from: LabRackPower.rear, to: outlet.normal)
                root.addChild(marker)
            }
            powerFeeds?.removeFromParent()
            powerFeeds = root
            externalUPSSources = plan.externalUPSSources
            renderedPowerAssembly = assembly
            content.addChild(root)
            if parent.walkthrough?.powerRouteReviews != plan.reviewRacks {
                parent.walkthrough?.powerRouteReviews = plan.reviewRacks
            }
        }

        private func makeElectricalRoutes(_ facility: TierFacility, placements: [LabPlacement]) throws -> Entity {
            let container = Entity()
            var supports = LabSceneMesh()
            let rackHeight = HardwareCatalog.renderSize("rack-r42612").y
            let overhead = facility.conduitHeight
            let local = simd_quatf(angle: -facility.yaw, axis: SIMD3(0, 1, 0))
            let devices = Dictionary(grouping: parent.topology?.devices ?? [], by: \.placementID)
            let racks = placements.filter { $0.kind == .rack && $0.id.hasPrefix("rack-") }
                .map { rack in
                    (rack, LabRackPower.strips(for: rack.size, configuration: .dual,
                                               devices: devices[rack.id] ?? [], includesLeads: false))
                }
            for side: Float in [-1, 1] {
                var runs = LabSceneMesh()
                func conduit(_ points: [SIMD3<Float>]) {
                    guard let bends = LabGeometry.cableBends(points, radius: 0.090) else { return }
                    runs.cable(bends, radius: 0.013)
                    for (a, b) in zip(points, points.dropFirst()) {
                        let length = simd_distance(a, b)
                        guard abs(a.y - b.y) < 0.01, length >= 0.8 else { continue }
                        let clamps = max(1, Int(ceil(length / 1.25)))
                        for index in 0..<clamps {
                            let point = a + (b - a) * ((Float(index) + 0.5) / Float(clamps))
                            supports.box(size: SIMD3(0.044, 0.035, 0.044), center: point)
                            let drop = facility.height - point.y
                            supports.box(size: SIMD3(0.012, drop, 0.012), center: point + SIMD3(0, drop / 2, 0))
                        }
                    }
                }
                let origin = side * 6.15
                let trunkZ: Float = side < 0 ? TierFacility.conduitAZ : 2.36
                conduit([SIMD3(origin, rackHeight, -3.03), SIMD3(origin, overhead, -3.03),
                         SIMD3(origin, overhead, trunkZ), SIMD3(-side * 4.1, overhead, trunkZ)])
                conduit([SIMD3(side * 6.62, 1.63, -1.86), SIMD3(side * 6.62, overhead + 0.19, -1.86),
                         SIMD3(side * 6.62, overhead + 0.19, -3.03),
                         SIMD3(origin, overhead + 0.19, -3.03), SIMD3(origin, rackHeight, -3.03)])
                for (rack, strips) in racks {
                    let index = side < 0 ? 0 : 1
                    let outsideUPS = externalUPSSources[.support(rack.id)]
                    if index == 0 && parent.directPowerOutlets[.support(rack.id)] != nil { continue }
                    let strip = strips[index]
                    if index != 0 && (outsideUPS != nil || strip.upsID != nil && strip.upsID == strips[0].upsID) { continue }
                    let rotation = simd_quatf(angle: rack.yaw, axis: SIMD3(0, 1, 0))
                    let port = local.act((outsideUPS?.point ?? rack.position + rotation.act(strip.upstream.point)) - facility.origin)
                    let exit = local.act((outsideUPS?.exit ?? rack.position + rotation.act(strip.upstream.exit)) - facility.origin)
                    let tap = SIMD3(exit.x, overhead, trunkZ)
                    let edge = -side * 4.1
                    if side * (port.x - edge) < 0 {
                        conduit([SIMD3(edge, overhead, trunkZ), tap])
                    }
                    let riser = SIMD3(exit.x, overhead, exit.z)
                    conduit([tap, riser, exit, port])
                }
                if !runs.indices.isEmpty { container.addChild(try runs.model(material: side < 0 ? materials.powerA : materials.powerB)) }
            }
            if !supports.indices.isEmpty { container.addChild(try supports.model(material: materials.metal)) }
            return container
        }

        private func holeRect(_ hole: RoomStructure.Surface, wall: RoomStructure.Surface) throws -> CGRect {
            let relative = try simd_inverse(LabGeometry.matrix(wall)) * LabGeometry.matrix(hole)
            guard abs(abs(relative.columns.0.x) - 1) < 0.01, abs(abs(relative.columns.1.y) - 1) < 0.01,
                  abs(relative.columns.3.z) <= 0.03 else {
                throw LabLayoutError.invalid("Abertura inclinada o no alineada con la pared. Revisa la captura.")
            }
            let a = relative * SIMD4(-hole.dimensions[0] / 2, -hole.dimensions[1] / 2, 0, 1)
            let b = relative * SIMD4(hole.dimensions[0] / 2, hole.dimensions[1] / 2, 0, 1)
            let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
            let halfW = wall.dimensions[0] / 2, halfH = wall.dimensions[1] / 2
            guard minX >= -halfW - 0.03, maxX <= halfW + 0.03, minY >= -halfH - 0.03, maxY <= halfH + 0.03 else {
                throw LabLayoutError.invalid("Una abertura sobrepasa su pared. Revisa las medidas del escaneo.")
            }
            return CGRect(x: CGFloat(max(minX, -halfW)), y: CGFloat(max(minY, -halfH)),
                          width: CGFloat(min(maxX, halfW) - max(minX, -halfW)),
                          height: CGFloat(min(maxY, halfH) - max(minY, -halfH)))
        }

        private func makePlacement(_ placement: LabPlacement) throws -> Entity {
            guard placement.size.x > 0, placement.size.y > 0, placement.size.z > 0,
                  [placement.size.x, placement.size.y, placement.size.z, placement.position.x,
                   placement.position.y, placement.position.z, placement.yaw].allSatisfy(\.isFinite) else {
                throw LabLayoutError.invalid("Equipo con tamaño o posición inválidos.")
            }
            let entity = Entity()
            entity.name = "placement:" + placement.id
            entity.position = placement.position
            entity.orientation = simd_quatf(angle: placement.yaw, axis: SIMD3(0, 1, 0))
            let hasDesktop = parent.topology?.devices.contains {
                $0.placementID == placement.id && $0.visualModelID == "pc-optiplex7010"
            } ?? false
            let parts = switch placement.kind {
            case .rack: rackMeshes(placement.size)
            case .workstation: workstationMeshes(placement.size, withDisplay: placement.bareDesk != true && (!parent.layout.importedRoom || hasDesktop))
            case .floor: [LabSceneMesh]()
            }
            let surfaceMaterials: [any RealityKit.Material] = [materials.graphite, materials.panel, materials.metal, materials.dark, materials.power, materials.screen]
            for (index, mesh) in parts.enumerated() where !mesh.indices.isEmpty {
                let model = try mesh.model(material: surfaceMaterials[index])
                entity.addChild(model)
                if index == 4 { indicators[placement.id, default: []].append(model) }
                if index == 5 { screens[placement.id, default: []].append(model) }
            }
            let s = placement.size
            let shapes: [ShapeResource]
            if placement.kind == .rack {
                shapes = [-s.x / 2 + 0.007, s.x / 2 - 0.007].map {
                    ShapeResource.generateBox(size: SIMD3(0.014, s.y, s.z)).offsetBy(translation: SIMD3($0, s.y / 2, 0))
                } + [Float(0.045), s.y - 0.025].map {
                    ShapeResource.generateBox(size: SIMD3(s.x, 0.05, s.z)).offsetBy(translation: SIMD3(0, $0, 0))
                }
            } else if placement.kind == .workstation {
                shapes = [ShapeResource.generateBox(size: SIMD3(s.x, 0.04, s.z)).offsetBy(translation: SIMD3(0, 0.73, 0))]
            } else {
                shapes = []
            }
            if !shapes.isEmpty { entity.components.set(CollisionComponent(shapes: shapes)) }
            try addHardware(to: entity, placement: placement)
            if parent.layout.importedRoom && placement.kind == .workstation {
                let nameplate = try label(placement.title, width: 0.49, height: 0.032)
                nameplate.position = SIMD3(0, 0.73, -placement.size.z / 2 - 0.002)
                entity.addChild(nameplate)
            }
            if placement.kind == .rack {
                try addRackElectrical(to: entity, placement: placement, assembly: parent.assembly)
            }
            var outline = LabSceneMesh()
            let w = placement.size.x / 2 + 0.006, h = placement.size.y, d = placement.size.z / 2 + 0.006
            for x in [-w, w] { for z in [-d, d] { outline.box(size: SIMD3(0.004, h, 0.004), center: SIMD3(x, h / 2, z)) } }
            for y in [Float(0.004), h] {
                for z in [-d, d] { outline.box(size: SIMD3(w * 2, 0.004, 0.004), center: SIMD3(0, y, z)) }
                for x in [-w, w] { outline.box(size: SIMD3(0.004, 0.004, d * 2), center: SIMD3(x, y, 0)) }
            }
            let highlight = try outline.model(material: materials.accent)
            highlight.isEnabled = false
            entity.addChild(highlight)
            highlights[placement.id] = highlight
            if parent.mode == .ar && parent.layout.facility != nil && parent.assembly == nil {
                let shell = Entity()
                for child in Array(entity.children) where !child.name.hasPrefix("device:") {
                    shell.addChild(child)
                }
                entity.addChild(shell)
                placementShells[placement.id] = shell
            }
            return entity
        }

        private func addRackElectrical(to rack: Entity, placement: LabPlacement, assembly: LabARAssembly?) throws {
            let devices = (parent.topology?.devices ?? [])
                .filter { $0.placementID == placement.id && assembly?.piece(.device($0.id)) == nil }
            let owner = LabARAssembly.Item.support(placement.id)
            pduHits = pduHits.filter { $0.value.rack != owner }
            pduLamps.removeAll { $0.rack == owner }
            let (hardware, wires) = try makeRackPower(size: placement.size,
                configuration: parent.layout.pduConfiguration(for: placement.id), devices: devices, owner: owner)
            if let facility = parent.layout.facility, placement.id.hasPrefix("rack-"), placement.size.y >= 1.98,
               facility.fixtures.contains(where: { $0.kind == .batteryBank }) {
                var transfer = LabSceneMesh()
                let position = SIMD3<Float>(0, 1.91, placement.size.z / 2 - 0.217)
                transfer.box(size: SIMD3(0.439, 0.044, 0.203), center: position)
                hardware.addChild(try transfer.model(material: materials.metal))
                let tag = try label("ATS · ENTRADAS A/B", width: 0.22, height: 0.016)
                tag.position = position + SIMD3(0, 0, 0.103)
                tag.orientation = simd_quatf()
                hardware.addChild(tag)
            }
            let previous = rack.findEntity(named: "rack-power")
            (previous?.parent ?? rack).addChild(hardware)
            previous?.removeFromParent()
            electricalLeads[placement.id] = wires
        }

        private func makeRackPower(size: SIMD3<Float>, configuration: LabRackPower.Configuration,
                                   devices: [LabTopology.Device], owner: LabARAssembly.Item? = nil) throws -> (Entity, Entity) {
            let hardware = Entity(), wires = Entity()
            hardware.name = "rack-power"
            hardware.addChild(wires)
            var housings = LabSceneMesh(), faceplates = LabSceneMesh(), openings = LabSceneMesh()
            var fasteners = LabSceneMesh(), plugs = LabSceneMesh()
            for (index, strip) in LabRackPower.strips(for: size, configuration: configuration, devices: devices).enumerated() {
                guard let top = strip.sockets.last else { continue }
                let height = top.y - strip.input.y + 0.024
                let center = (strip.input + top) / 2 + SIMD3(0, 0.004, 0)
                if let owner, parent.onInspectPDU != nil, !parent.usesCompactTierOverview {
                    let panel = Entity()
                    panel.position = center
                    panel.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(0.048, height, 0.004))]))
                    pduHits[ObjectIdentifier(panel)] = (owner, index, strip.sockets.map { $0.y - center.y })
                    hardware.addChild(panel)
                }
                housings.box(size: SIMD3(0.048, height, 0.042), center: center - SIMD3(0, 0, 0.027))
                faceplates.box(size: SIMD3(0.039, height - 0.005, 0.005), center: center - SIMD3(0, 0, 0.004))
                let side = strip.side.sign
                for y in [strip.input.y + 0.007, top.y + 0.010] {
                    let mount = SIMD3(top.x + side * 0.022, y, top.z - 0.024)
                    faceplates.box(size: SIMD3(0.028, 0.016, 0.046), center: mount)
                    fasteners.box(size: SIMD3(0.006, 0.006, 0.003), center: mount + SIMD3(side * 0.009, 0, 0.024))
                }
                for socket in strip.sockets + [strip.input] {
                    housings.box(size: SIMD3(0.030, 0.021, 0.004), center: socket - SIMD3(0, 0, 0.001))
                    openings.box(size: SIMD3(0.023, 0.015, 0.001), center: socket + SIMD3(0, 0, 0.001))
                    for pin: SIMD2<Float> in [[-0.006, -0.003], [0.006, -0.003], [0, 0.004]] {
                        fasteners.box(size: SIMD3(0.0018, 0.004, 0.001), center: socket + SIMD3(pin.x, pin.y, 0.0018))
                    }
                }
                let title = configuration == .dual ? (index == 0 ? "PDU A" : "PDU B") : "PDU 0U"
                let tag = try label(title, width: 0.035, height: 0.008)
                tag.position = top + SIMD3(0, 0.012, 0.003)
                tag.orientation = simd_quatf()
                hardware.addChild(tag)
                let dark = owner.map { isPoweredOff($0.name) } == true || strip.upsID.map(isPoweredOff) == true
                let indicator = ModelEntity(mesh: .generateBox(size: SIMD3(0.003, 0.021, 0.002)),
                                            materials: [dark ? materials.off as any RealityKit.Material : materials.power])
                indicator.position = top + SIMD3(-side * 0.018, -0.019, 0)
                hardware.addChild(indicator)
                if let owner { pduLamps.append((owner, strip.upsID, indicator)) }
                var mesh = LabSceneMesh()
                for lead in strip.leads {
                    mesh.cable(lead.points, radius: 0.0038)
                    for point in [lead.points.first, lead.points.last].compactMap({ $0 }) {
                        plugs.box(size: SIMD3(0.019, 0.014, 0.013), center: point + SIMD3(0, 0, 0.006))
                        plugs.tube(from: point + SIMD3(0, 0, 0.011),
                                   to: point + LabRackPower.rear * LabRackPower.cordExit, radius: 0.0054)
                    }
                }
                if !mesh.indices.isEmpty {
                    wires.addChild(try mesh.model(material: index == 0 ? materials.powerA : materials.powerB))
                }
            }
            hardware.addChild(try housings.model(material: materials.graphite))
            hardware.addChild(try faceplates.model(material: materials.panel))
            hardware.addChild(try openings.model(material: materials.dark))
            hardware.addChild(try fasteners.model(material: materials.metal))
            if !plugs.indices.isEmpty { wires.addChild(try plugs.model(material: materials.dark)) }
            wires.isEnabled = parent.showCables && parent.visibleCableIDs == nil
            return (hardware, wires)
        }

        private func rackMeshes(_ size: SIMD3<Float>) -> [LabSceneMesh] {
            var parts = Array(repeating: LabSceneMesh(), count: 6)
            let w = size.x, h = size.y, d = size.z, front = -d / 2
            func box(_ part: Int, _ dimensions: SIMD3<Float>, _ center: SIMD3<Float>) { parts[part].box(size: dimensions, center: center) }
            let capacity = RackMount.capacity(height: h)
            let railZ = RackMount.CableFace.front.railDepth(in: size)
            let rearRailZ = RackMount.CableFace.rear.railDepth(in: size)
            for sign: Float in [-1, 1] {
                let side = sign * (w / 2 - 0.007)
                box(0, SIMD3(0.014, h - 0.09, d - 0.06), SIMD3(side, h / 2, 0))
                for z in [front + 0.018, d / 2 - 0.018] {
                    box(0, SIMD3(0.024, h - 0.055, 0.036), SIMD3(sign * (w / 2 - 0.013), h / 2, z))
                    box(3, SIMD3(0.064, 0.04, 0.074), SIMD3(sign * (w / 2 - 0.047), 0.02, z))
                }
                let railX = sign * RackMount.frontRailX
                let rearRailX = sign * (w / 2 - 0.020)
                let railHeight = RackMount.unit * Float(capacity)
                box(2, SIMD3(0.014, RackMount.unit * Float(capacity), 0.022),
                    SIMD3(railX, RackMount.base + RackMount.unit * Float(capacity) / 2, railZ))
                box(1, SIMD3(0.019, railHeight, 0.026),
                    SIMD3(rearRailX, RackMount.base + railHeight / 2, rearRailZ))
                for unit in 0..<capacity {
                    for offset: Float in [0.00635, 0.02222, 0.03810] {
                        let y = RackMount.base + Float(unit) * RackMount.unit + offset
                        box(3, SIMD3(0.008, 0.008, 0.002), SIMD3(railX, y, railZ - 0.012))
                        box(3, SIMD3(0.008, 0.008, 0.001), SIMD3(rearRailX, y, rearRailZ + 0.013))
                    }
                }
                for y in [RackMount.base + 0.014, RackMount.base + railHeight - 0.014] {
                    box(2, SIMD3(0.032, 0.024, 0.031), SIMD3(rearRailX, y, rearRailZ - 0.010))
                    box(2, SIMD3(0.006, 0.006, 0.003), SIMD3(rearRailX - sign * 0.013, y, rearRailZ + 0.012))
                }
            }
            // Corner openings leave a cable feed at both ends of the base and roof.
            let entry: Float = 0.060
            box(0, SIMD3(w, 0.055, d - 2 * entry), SIMD3(0, 0.069, 0))
            for face in [RackMount.CableFace.front, .rear] {
                box(0, SIMD3(w - 2 * entry, 0.055, entry), SIMD3(0, 0.069, face.sign * (d - entry) / 2))
            }
            box(0, SIMD3(w, 0.042, d - 0.17 - entry), SIMD3(0, h - 0.021, -0.085 + entry / 2))
            box(0, SIMD3(w, 0.058, 0.04), SIMD3(0, h - 0.035, d / 2 - entry - 0.020))
            for face in [RackMount.CableFace.front, .rear] {
                box(0, SIMD3(w - 2 * entry, 0.042, entry), SIMD3(0, h - 0.021, face.sign * (d - entry) / 2))
            }
            for vent in 0..<18 {
                box(3, SIMD3(0.013, 0.003, d * 0.20), SIMD3(-0.21 + Float(vent) * 0.024, h, 0.1))
            }
            return parts
        }

        private func workstationMeshes(_ size: SIMD3<Float>, withDisplay: Bool) -> [LabSceneMesh] {
            var parts = Array(repeating: LabSceneMesh(), count: 6)
            func box(_ part: Int, _ dimensions: SIMD3<Float>, _ center: SIMD3<Float>) { parts[part].box(size: dimensions, center: center) }
            let w = size.x, d = size.z, top: Float = 0.75
            box(1, SIMD3(w, 0.04, d), SIMD3(0, top - 0.02, 0))
            for x in [-w / 2 + 0.07, w / 2 - 0.07] { for z in [-d / 2 + 0.07, d / 2 - 0.07] {
                box(2, SIMD3(0.035, top - 0.04, 0.035), SIMD3(x, (top - 0.04) / 2, z))
            } }
            guard withDisplay else { return parts }
            box(0, SIMD3(0.2, 0.018, 0.15), SIMD3(-0.1, top + 0.009, 0.1))
            box(2, SIMD3(0.035, 0.15, 0.025), SIMD3(-0.1, top + 0.09, 0.14))
            box(0, SIMD3(0.52, 0.32, 0.035), SIMD3(-0.1, top + 0.29, 0.14))
            box(5, SIMD3(0.477, 0.277, 0.003), SIMD3(-0.1, top + 0.29, 0.12))
            box(0, SIMD3(0.4, 0.012, 0.14), SIMD3(-0.1, top + 0.008, -0.19))
            for row in 0..<4 { for key in 0..<12 {
                box(2, SIMD3(0.023, 0.003, 0.018), SIMD3(-0.27 + Float(key) * 0.031, top + 0.016, -0.233 + Float(row) * 0.028))
            } }
            return parts
        }

        private func addHardware(to entity: Entity, placement: LabPlacement) throws {
            if let topology = parent.topology {
                let devices = topology.devices.filter { $0.placementID == placement.id && $0.modelID != "rack-r42612" }
                var brackets = LabSceneMesh(), fasteners = LabSceneMesh()
                if parent.usesCompactTierOverview && placement.kind == .rack {
                    try addCompactRackDevices(devices, to: entity)
                }
                for device in devices where !parent.usesCompactTierOverview || placement.kind != .rack {
                    let model: Entity
                    if ["ups-9px", "battery-9px"].contains(device.visualModelID) {
                        model = try makeFacilityEquipment(device.visualModelID, circuit: "A")
                    } else if device.visualModelID == RackMount.Equipment.fans.rawValue {
                        model = try makeFanTray(device)
                    } else {
                        model = try hardware(device.visualModelID)
                    }
                    model.name = "device:" + device.id
                    model.position = device.offset
                    entity.addChild(model)
                    deviceModels[device.id] = model
                    if parent.isTierMiniature && placement.kind == .rack {
                        appendRackMount(modelID: device.visualModelID, at: device.offset, brackets: &brackets, fasteners: &fasteners)
                    } else {
                        try addRackMount(to: entity, modelID: device.visualModelID, at: device.offset, placement: placement)
                    }
                    devicePowerParents[device.id] = placement.id
                    registerPower(model, placementID: device.id)
                    deviceHighlights[device.id] = model.findEntity(named: "hardware-selection")
                    try addPorts(device: device, to: model)
                    let size = device.visualSize
                    let name = device.providesDHCP && !device.name.localizedCaseInsensitiveContains("dhcp")
                        ? device.name + " · DHCP" : device.name
                    let width = min(device.providesDHCP ? 0.28 : 0.19, size.x - 0.012)
                    let height: Float = device.providesDHCP ? 0.021 : 0.016
                    let title = String(name.prefix(38))
                    let hasRearLabel = parent.layout.importedRoom && device.providesDHCP
                    if placement.kind == .rack {
                        // Keep the name on the lid, behind both connector faces.
                        let inset = min(0.022, size.z / 4)
                        model.addChild(try topLabel(title, width: width, depth: height,
                                                   at: SIMD3(0, size.y / 2, -size.z / 2 + inset)))
                        if hasRearLabel {
                            model.addChild(try topLabel(title, width: width, depth: height,
                                                       at: SIMD3(0, size.y / 2, size.z / 2 - inset), facing: .rear))
                        }
                    } else {
                        let badge = try label(title, width: width, height: height)
                        badge.position = SIMD3(0, size.y / 2 - 0.010, -size.z / 2 - 0.013)
                        model.addChild(badge)
                        if hasRearLabel {
                            let rear = badge.clone(recursive: false)
                            rear.position.z = size.z / 2 + 0.013
                            rear.orientation = simd_quatf()
                            model.addChild(rear)
                        }
                    }
                }
                if placement.kind == .rack {
                    try addRackMountMeshes(to: entity, brackets: brackets, fasteners: fasteners)
                    if topology.operationsProfile != nil && parent.assembly == nil {
                        try addRackPanels(to: entity, placement: placement, topology: topology)
                        if parent.layout.rackMonitors?[placement.id] == nil {
                            let monitored = topology.devices.filter { $0.placementID == placement.id && $0.hasDashboard }
                            try addDashboardMonitors(to: entity, placement: placement, devices: monitored)
                        }
                    }
                    if parent.assembly == nil {
                        for mount in parent.layout.rackMonitors?[placement.id] ?? [] {
                            guard let device = topology.devices.first(where: { $0.id == mount.device }) else { continue }
                            let monitor = makeAssemblyMonitor(device, panel: mount.panel, owner: mount.item,
                                                              mount: mount.piece(on: placement).monitorMount)
                            monitor.name = "placement:" + placement.id
                            monitor.position = LabARAssembly.monitorOffset(on: placement, side: mount.side, row: mount.row)
                            entity.addChild(monitor)
                        }
                    }
                    try addRackTitle(to: entity, placement: placement)
                } else if placement.bareDesk != true, topology.operationsProfile != nil, parent.assembly == nil,
                          let station = topology.devices.first(where: { $0.placementID == placement.id && $0.modelID == "pc-optiplex7010" }) {
                    try addConsoleScreen(to: entity, station: station)
                }
                return
            }
            if placement.kind == .rack {
                let devices: [(String, Float)] = [("switch-2960", 1.79), ("switch-3560", 1.67),
                    ("router-1941", 1.46), ("router-2911", 1.23), ("firewall-asa5505", 1.02),
                    ("server-c220m5", 0.77), ("server-c220m5", 0.59), ("server-c220m5", 0.41)]
                for (id, height) in devices {
                    let model = try hardware(id)
                    model.position = RackMount.center(id, rackDepth: placement.size.z, slot: RackMount.slot(id, near: height))
                    entity.addChild(model)
                    try addRackMount(to: entity, modelID: id, at: model.position, placement: placement)
                    registerPower(model, placementID: placement.id)
                }
                try addRackTitle(to: entity, placement: placement)
            } else {
                let desktop = try hardware("pc-optiplex7010")
                let desktopSize = hardwareSize("pc-optiplex7010")
                desktop.position = SIMD3(placement.size.x / 2 - 0.16, desktopSize.y / 2 + 0.015, 0)
                entity.addChild(desktop); registerPower(desktop, placementID: placement.id)
                let laptop = try hardware("laptop-latitude5420")
                laptop.position = SIMD3(0.37, 0.77, -0.13)
                entity.addChild(laptop); registerPower(laptop, placementID: placement.id)
                let phone = try hardware("phone-7960")
                phone.position = SIMD3(-0.47, 0.79, 0.13)
                entity.addChild(phone); registerPower(phone, placementID: placement.id)
            }
        }

        private func addCompactRackDevices(_ devices: [LabTopology.Device], to rack: Entity) throws {
            var parts = Array(repeating: LabSceneMesh(), count: 10)
            var brackets = LabSceneMesh(), fasteners = LabSceneMesh()
            for device in devices {
                let id = device.visualModelID
                let picker: Entity
                if id == Catalyst2960Asset.modelID {
                    picker = try hardware(id, compact: true)
                    registerPower(picker, placementID: device.id)
                } else if id == RackMount.Equipment.fans.rawValue {
                    picker = try makeFanTray(device)
                } else if ["ups-9px", "battery-9px"].contains(id) {
                    picker = try makeFacilityEquipment(id, circuit: "A")
                } else {
                    let meshes = hardwareMeshScratch[id] ?? hardwareMeshes(id)
                    hardwareMeshScratch[id] = meshes
                    for (index, mesh) in meshes.enumerated() where !mesh.indices.isEmpty {
                        let slot = index == 6 ? (id == "switch-3650" ? 8 : id == "router-2811" ? 9 : 6) : index
                        parts[slot].append(positions: mesh.positions.map { $0 + device.offset }, normals: mesh.normals, indices: mesh.indices)
                    }
                    picker = Entity()
                    try addHardwareSelection(to: picker, id: id)
                }
                appendRackMount(modelID: id, at: device.offset, brackets: &brackets, fasteners: &fasteners)
                picker.name = "device:" + device.id
                picker.position = device.offset
                deviceModels[device.id] = picker
                devicePowerParents[device.id] = device.placementID
                deviceHighlights[device.id] = picker.findEntity(named: "hardware-selection")
                rack.addChild(picker)
            }
            let palette = hardwareMaterials("") + [hardwareMaterials("switch-3650")[6], hardwareMaterials("router-2811")[6]]
            for (index, mesh) in parts.enumerated() where !mesh.indices.isEmpty {
                rack.addChild(try mesh.model(material: palette[index]))
            }
            try addRackMountMeshes(to: rack, brackets: brackets, fasteners: fasteners)
        }

        private func addConsoleScreen(to workstation: Entity, station: LabTopology.Device) throws {
            let monitor = Entity()
            monitor.name = "device:" + station.id
            monitor.position = SIMD3(-0.1, 1.04, 0.119)
            monitor.components.set(CollisionComponent(shapes: [
                ShapeResource.generateBox(size: SIMD3(0.51, 0.31, 0.035))
            ]))
            let terminal = try label("NEXUS · CONSOLA DE OPERACIÓN", width: 0.40, height: 0.042)
            terminal.position = SIMD3(0, 0.065, -0.004)
            terminal.name = "screen"
            monitor.addChild(terminal)
            consoleScreens[station.id, default: []].append(terminal)
            workstation.addChild(monitor)
        }

        private func addDashboardMonitors(to rack: Entity, placement: LabPlacement,
                                         devices: [LabTopology.Device]) throws {
            let width = LabMonitorMount.displayWidth, height = LabMonitorMount.displayHeight
            let frameSize = SIMD3(width + LabMonitorMount.bezel, height + LabMonitorMount.bezel, 0.022)
            let template = MeshResource.generateBox(size: frameSize, cornerRadius: 0.007)
            let front = -placement.size.z / 2 + LabMonitorMount.inset
            var steel = LabSceneMesh(), brackets = LabSceneMesh(), screws = LabSceneMesh(), harness = LabSceneMesh()
            for (index, device) in devices.enumerated() {
                let side: Float = index.isMultiple(of: 2) ? 1 : -1
                let x = LabMonitorMount.centerX(for: placement.size.x, side: side)
                let columnX = side * (placement.size.x / 2 + 0.041)
                let highest = min(Float(1.78), placement.size.y - height / 2 - 0.06)
                let row = index / 2
                let y = highest - Float(row) * 0.247
                if y < height / 2 + 0.10 { continue }
                let postZ = front + 0.050
                if row == 0 {
                    steel.box(size: SIMD3(0.048, highest + 0.057, 0.047),
                              center: SIMD3(columnX, 0.021 + (highest + 0.057) / 2, postZ))
                    brackets.box(size: SIMD3(0.113, 0.023, 0.220), center: SIMD3(columnX + side * 0.032, 0.0115, postZ + 0.041))
                    for dx: Float in [-0.032, 0.032] {
                        for dz: Float in [-0.066, 0.066] {
                            let bolt = SIMD3(columnX + side * 0.032 + dx, 0.023, postZ + 0.041 + dz)
                            screws.tube(from: bolt, to: bolt + SIMD3(0, 0.007, 0), radius: 0.007)
                        }
                    }
                    harness.tube(from: SIMD3(columnX + side * 0.031, 0.029, postZ + 0.033),
                                 to: SIMD3(columnX + side * 0.031, highest + 0.006, postZ + 0.033), radius: 0.0055)
                }

                // Clamp, two pinned links and a rear VESA plate. Each screen has its own load path to the post.
                brackets.box(size: SIMD3(0.070, 0.056, 0.056), center: SIMD3(columnX, y, postZ))
                let base = SIMD3(columnX + side * 0.033, y, postZ)
                let elbow = SIMD3(columnX + side * 0.112, y, front + 0.090)
                let head = SIMD3(x, y, front + 0.027)
                for (a, b) in [(base, elbow), (elbow, head)] {
                    let delta = b - a
                    var transform = simd_float4x4(simd_quatf(from: SIMD3(1, 0, 0), to: simd_normalize(delta)))
                    transform.columns.3 = SIMD4((a + b) / 2, 1)
                    steel.box(size: SIMD3(simd_length(delta), 0.029, 0.026), center: .zero, matrix: transform)
                }
                for joint in [base, elbow, head] {
                    brackets.tube(from: joint - SIMD3(0, 0.021, 0), to: joint + SIMD3(0, 0.021, 0), radius: 0.020)
                    screws.tube(from: joint + SIMD3(0, 0.020, 0), to: joint + SIMD3(0, 0.025, 0), radius: 0.008)
                }
                brackets.box(size: SIMD3(0.093, 0.088, 0.010), center: SIMD3(x, y, front + 0.016))
                for dx: Float in [-0.0375, 0.0375] {
                    for dy: Float in [-0.0375, 0.0375] {
                        let bolt = SIMD3(x + dx, y + dy, front + 0.021)
                        screws.tube(from: bolt, to: bolt + SIMD3(0, 0, 0.003), radius: 0.004)
                    }
                }
                let outlet = SIMD3(x + side * 0.044, y - 0.057, front + 0.014)
                let loop = SIMD3(x + side * 0.044, y - 0.110, front + 0.041)
                let bend = SIMD3(x - side * 0.031, y - 0.088, front + 0.098)
                let clip = SIMD3(columnX + side * 0.031, y - 0.044, postZ + 0.033)
                let cable = [outlet, loop, bend, clip]
                for (a, b) in zip(cable, cable.dropFirst()) { harness.tube(from: a, to: b, radius: 0.0038) }

                let monitor = Entity()
                monitor.name = "device:" + device.id
                monitor.position = SIMD3(x, y, front)
                monitor.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: frameSize)]))
                monitor.addChild(ModelEntity(mesh: template, materials: [materials.graphite]))
                let face = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [materials.dark])
                face.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
                face.position.z = -0.012
                monitor.addChild(face)
                dashboards.append(Dashboard(device: device, face: face))
                rack.addChild(monitor)
            }
            if !steel.indices.isEmpty {
                rack.addChild(try steel.model(material: materials.metal))
                rack.addChild(try brackets.model(material: materials.graphite))
                rack.addChild(try screws.model(material: materials.metal))
                rack.addChild(try harness.model(material: materials.dark))
            }
        }

        private func dashboardImage(for device: LabTopology.Device, frame: DashboardFrame) -> CGImage? {
            dashboardRenderer.image { context in
                let graphics = context.cgContext
                UIColor(red: 0.025, green: 0.043, blue: 0.070, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: LabMonitorMount.faceSize))
                let secondary = UIColor(red: 0.69, green: 0.77, blue: 0.87, alpha: 1)
                func draw(_ value: String, size: CGFloat, in bounds: CGRect, color: UIColor,
                          alignment: NSTextAlignment = .left) {
                    let font = UIFont.systemFont(ofSize: size, weight: .semibold)
                    let style = NSMutableParagraphStyle()
                    style.alignment = alignment
                    style.lineBreakMode = .byTruncatingTail
                    let line = value.components(separatedBy: .newlines).joined(separator: " ")
                    graphics.saveGState()
                    graphics.clip(to: bounds)
                    let text = CGRect(x: bounds.minX, y: bounds.midY - font.lineHeight / 2,
                                      width: bounds.width, height: font.lineHeight + 1)
                    (line as NSString).draw(in: text, withAttributes: [
                        .foregroundColor: color, .font: font, .paragraphStyle: style
                    ])
                    graphics.restoreGState()
                }
                let panel = frame.configuration.panel
                let heading = LabMonitorMount.heading
                let (eyebrow, remaining) = heading.divided(atDistance: 17, from: .minYEdge)
                let (title, status) = remaining.divided(atDistance: 26, from: .minYEdge)
                draw("Simulación · " + panel.rawValue, size: 12, in: eyebrow, color: secondary)
                draw(device.name, size: 19, in: title, color: .white)
                let statusColor: UIColor = switch frame.state {
                case .available: UIColor(red: 0.46, green: 0.91, blue: 0.70, alpha: 1)
                case .isolated: UIColor(red: 1, green: 0.76, blue: 0.37, alpha: 1)
                case .offline: secondary
                }
                draw(frame.state.rawValue, size: 13, in: status, color: statusColor)

                if panel == .services {
                    let services = frame.services
                    let rows = services.isEmpty ? ["Sin servicios asignados"] : Array(services.prefix(4))
                    for (index, service) in rows.enumerated() {
                        draw(service, size: 14, in: CGRect(x: heading.minX, y: heading.maxY + 6 + CGFloat(index) * 23,
                                                          width: heading.width, height: 23), color: .white)
                    }
                } else {
                    for (index, pair) in zip(panel.metrics, frame.values).enumerated() {
                        let (metric, value) = pair
                        let plot = LabMonitorMount.chartFrame(at: index)
                        let caption = LabMonitorMount.captionFrame(at: index)
                        let (label, reading) = caption.divided(atDistance: 17, from: .minYEdge)
                        let rings = frame.configuration.usesRings
                        graphics.saveGState()
                        graphics.clip(to: plot)
                        graphics.setFillColor(UIColor(red: 0.19, green: 0.25, blue: 0.34, alpha: 1).cgColor)
                        graphics.addPath(LabMonitorChart(rings: rings, fraction: 1).path(in: plot).cgPath)
                        graphics.fillPath()
                        graphics.setFillColor(UIColor(red: 0.32, green: 0.69, blue: 1, alpha: 1).cgColor)
                        graphics.addPath(LabMonitorChart(rings: rings, fraction: value / metric.maximum).path(in: plot).cgPath)
                        graphics.fillPath()
                        graphics.restoreGState()
                        draw(metric.rawValue, size: 13, in: label, color: secondary, alignment: .center)
                        draw(metric.formatted(value), size: 16, in: reading, color: .white, alignment: .center)
                    }
                }
            }.cgImage
        }

        private func updateDashboards(force: Bool = false) {
            guard !dashboards.isEmpty, parent.isForeground, !parent.usesCompactTierOverview,
                  let topology = parent.topology else { return }
            if parent.isTierAR && (!tracking || awaitingPlacement || rootAnchor?.isEnabled != true) { return }
            let now = Date()
            let tick = floor(now.timeIntervalSince1970 / LabServerSample.interval)
            guard force || tick != lastDashboardTick else { return }
            lastDashboardTick = tick
            let options = TextureResource.CreateOptions(semantic: .color)
            for index in dashboards.indices {
                if parent.isTierAR && !dashboards[index].face.isEnabledInHierarchy { continue }
                let device = dashboards[index].device
                var configuration = parent.monitorConfigurations[device.id] ?? .init()
                if let panel = dashboards[index].panel { configuration.panel = panel }
                let sample = LabServerSample(device: device, topology: topology, poweredOff: parent.poweredOff, timestamp: now)
                let values = configuration.panel.metrics.map { ($0.value(in: sample) * 10).rounded() / 10 }
                let services = configuration.panel == .services ? topology.serviceRows(for: device) : []
                let frame = DashboardFrame(configuration: configuration, state: sample.state, values: values, services: services)
                guard dashboards[index].frame != frame, let image = dashboardImage(for: device, frame: frame) else { continue }
                do {
                    if let texture = dashboards[index].texture {
                        try texture.replace(withImage: image, options: options)
                    } else {
                        let texture = try TextureResource.generate(from: image, options: options)
                        var material = UnlitMaterial()
                        material.color = .init(tint: .white, texture: .init(texture))
                        dashboards[index].face.model?.materials = [material]
                        dashboards[index].texture = texture
                    }
                    dashboards[index].frame = frame
                } catch {
                    Logger(subsystem: "org.unsm.NexusRoomCapture", category: "scene")
                        .error("Error al actualizar el monitor: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private func addRackPanels(to rack: Entity, placement: LabPlacement, topology: LabTopology) throws {
            let capacity = RackMount.capacity(height: placement.size.y)
            let used = Set(topology.devices.filter { $0.placementID == placement.id }.flatMap { device in
                let start = RackMount.slot(device.modelID, near: device.offset.y)
                return start..<(start + RackMount.units(device.modelID))
            })
            let front = -placement.size.z / 2 + RackMount.frontInset + 0.004
            var blanks = LabSceneMesh(), hardware = LabSceneMesh()
            for slot in 0..<capacity where !used.contains(slot) {
                let y = RackMount.base + (Float(slot) + 0.5) * RackMount.unit
                blanks.box(size: SIMD3(0.488, RackMount.unit - 0.003, 0.013), center: SIMD3(0, y, front))
                for side: Float in [-1, 1] {
                    hardware.box(size: SIMD3(0.008, 0.006, 0.002), center: SIMD3(side * 0.232, y, front - 0.007))
                }
                if slot.isMultiple(of: 3) {
                    hardware.box(size: SIMD3(0.070, 0.003, 0.003), center: SIMD3(0, y, front - 0.007))
                }
            }
            if !blanks.indices.isEmpty {
                rack.addChild(try blanks.model(material: materials.graphite))
                rack.addChild(try hardware.model(material: materials.panel))
            }
        }

        private func addRackMount(to rack: Entity, modelID: String, at center: SIMD3<Float>, placement: LabPlacement) throws {
            guard placement.kind == .rack else { return }
            var brackets = LabSceneMesh(), fasteners = LabSceneMesh()
            appendRackMount(modelID: modelID, at: center, brackets: &brackets, fasteners: &fasteners)
            try addRackMountMeshes(to: rack, brackets: brackets, fasteners: fasteners)
        }

        private func addRackMountMeshes(to rack: Entity, brackets: LabSceneMesh, fasteners: LabSceneMesh) throws {
            if !brackets.indices.isEmpty { rack.addChild(try brackets.model(material: materials.graphite)) }
            if !fasteners.indices.isEmpty { rack.addChild(try fasteners.model(material: materials.metal)) }
        }

        private func appendRackMount(modelID: String, at center: SIMD3<Float>, brackets: inout LabSceneMesh,
                                     fasteners: inout LabSceneMesh) {
            let size = hardwareSize(modelID)
            let front = center.z - size.z / 2
            if modelID == "raspberry-pi5" {
                fasteners.box(size: SIMD3(0.487, 0.005, 0.20),
                              center: SIMD3(0, center.y - size.y / 2 - 0.003, front + 0.083))
                for side: Float in [-1, 1] {
                    fasteners.box(size: SIMD3(0.027, 0.043, 0.005),
                                  center: SIMD3(side * 0.239, center.y + 0.006, front))
                }
                return
            }
            if modelID == "firewall-asa5505" {
                let y = center.y - size.y / 2 - 0.004
                brackets.box(size: SIMD3(0.49, 0.008, 0.23), center: SIMD3(0, y, front + 0.107))
            }
            for sign: Float in [-1, 1] {
                let width = 0.253 - size.x / 2
                let x = sign * (0.253 - width / 2)
                let y = modelID == "firewall-asa5505" ? center.y - size.y / 2 : center.y
                let height = modelID == "firewall-asa5505" ? 0.018 : size.y - 0.004
                let earWidth = modelID == "firewall-asa5505" ? 0.024 : width
                brackets.box(size: SIMD3(earWidth, height, 0.006),
                             center: SIMD3(modelID == "firewall-asa5505" ? sign * 0.244 : x, y, front - 0.001))
                fasteners.tube(from: SIMD3(sign * 0.247, y, front - 0.003),
                               to: SIMD3(sign * 0.247, y, front - 0.007), radius: 0.003)
            }
        }

        private func addRackTitle(to entity: Entity, placement: LabPlacement) throws {
            let capacity = RackMount.capacity(height: placement.size.y)
            let width = placement.size.x - 0.12
            let title = try label("\(placement.title) · \(capacity) U", width: width, height: 0.030)
            if capacity == 42 { title.name = "hardware:rack-r42612" }
            title.position = SIMD3(0, placement.size.y - 0.021, -placement.size.z / 2 - 0.001)
            title.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3(width, 0.030, 0.004))]))
            entity.addChild(title)
        }

        private func worldPort(_ device: LabTopology.Device, _ name: String) throws -> LabScenePort {
            try LabScenePort.world(device, name, in: parent.layout)
        }

        private func addPorts(device: LabTopology.Device, to entity: Entity) throws {
            var sockets = LabSceneMesh()
            var modules = LabSceneMesh()
            var installed = Set<Int>()
            for name in device.ports where !name.lowercased().contains("power") && !name.lowercased().contains("psu") {
                let port = try LabScenePort.local(device, name)
                let orientation = simd_quatf(from: SIMD3(0, 0, 1), to: port.normal)
                let serial = name.hasPrefix("Serial")
                if !parent.isTierMiniature {
                    let hit = Entity(); hit.name = "port:" + name
                    hit.position = port.point + port.normal * 0.004
                    hit.orientation = orientation
                    let width: Float = serial ? 0.025 : (device.modelID == "patch-copper" ? 0.015 : 0.019)
                    hit.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3(width, 0.016, 0.012))]))
                    entity.addChild(hit)
                    portHits[ObjectIdentifier(hit)] = try worldPort(device, name)
                }
                if !serial && LabScenePort.networkPanel(device.visualModelID, port: name) != nil { continue }
                if serial, let slot = name.split(separator: "/").dropFirst().first.flatMap({ Int($0) }),
                   installed.insert(slot).inserted {
                    let center = LabScenePort.moduleCenter(device.visualModelID, slot: slot)
                    modules.box(size: SIMD3(0.054, 0.016, 0.004), center: SIMD3(center.x, center.y, port.point.z))
                }
                var matrix = simd_float4x4(orientation)
                matrix.columns.3 = SIMD4(port.point + port.normal * 0.002, 1)
                sockets.box(size: SIMD3(serial ? 0.023 : 0.015, serial ? 0.008 : 0.012, 0.002), center: .zero, matrix: matrix)
            }
            if !modules.indices.isEmpty { entity.addChild(try modules.model(material: materials.metal)) }
            if !sockets.indices.isEmpty { entity.addChild(try sockets.model(material: materials.dark)) }
        }

        private func makeCable(_ segment: LabCablePlan.Segment) throws -> (picker: Entity, body: ModelEntity) {
            let link = segment.link
            var wire = LabSceneMesh()
            wire.cable(segment.points, radius: link.medium.cableRadius)
            let body = try wire.model(material: wireMaterial(link.medium))
            let picker = cablePicker(for: segment)
            picker.addChild(body)
            for (style, mesh) in Self.connectorMeshes(for: [(link.medium, segment.endpoints)]) {
                picker.addChild(try mesh.model(material: cableMaterial(style)))
            }
            return (picker, body)
        }

        private typealias CableModels = [(picker: Entity, body: ModelEntity)]

        private func installCables(_ plan: LabCablePlan, for topology: LabTopology, in container: Entity,
                                   models: CableModels? = nil) throws {
            let cables = try models ?? plan.segments.map(makeCable)
            let guides = Self.guideMeshes(plan.guides, anchors: plan.anchors, terminations: plan.terminations,
                                          organizers: plan.organizers, floor: parent.layout.floorHeight,
                                          overhead: plan.channelHeight, ceiling: plan.ceiling)
            let guideGroup = Entity()
            for (style, mesh) in guides where !mesh.indices.isEmpty {
                guideGroup.addChild(try mesh.model(material: cableMaterial(style)))
            }
            for (segment, cable) in zip(plan.segments, cables) {
                container.addChild(cable.picker)
                linkEntities[segment.link.id] = cable.picker
                linkBodies[segment.link.id] = cable.body
                pingPaths[segment.link.id] = segment.points
            }
            container.addChild(guideGroup)
            cableGuides = guideGroup
            committedCableReviews = plan.reviewCount
            reportCableReviews(plan.reviewCount)
            makeTraffic(topology, paths: pingPaths, cables: container)
            #if DEBUG
            let missing = topology.links.filter { linkBodies[$0.id] == nil }.map(\.id)
            Logger(subsystem: "org.unsm.NexusRoomCapture", category: "scene")
                .info("Cableado de \(topology.name, privacy: .public): \(self.linkBodies.count)/\(topology.links.count). Omitidos: \(missing.joined(separator: ", "), privacy: .public)")
            #endif
        }

        @concurrent private static func planRoomCables(_ topology: LabTopology, room: RoomStructure,
                                                       layout: LabLayout) async throws -> LabCablePlan {
            try LabCablePlan.make(topology, room: room, layout: layout)
        }

        private func loadRoomCables(_ topology: LabTopology, in container: Entity) {
            guard !topology.links.isEmpty else { reportCableReviews(0); return }
            let room = parent.room, layout = parent.layout
            roomCablingTask = Task { @MainActor [weak self, weak container] in
                do {
                    let plan = try await Self.planRoomCables(topology, room: room, layout: layout)
                    var models: CableModels = []
                    models.reserveCapacity(plan.segments.count)
                    for (index, segment) in plan.segments.enumerated() {
                        if index.isMultiple(of: 8) { try await Task.sleep(for: .milliseconds(1)) }
                        try Task.checkCancellation()
                        guard let self else { return }
                        try models.append(autoreleasepool { try makeCable(segment) })
                    }
                    try Task.checkCancellation()
                    guard let self, let container, cablesEntity === container else { return }
                    defer {
                        roomCablingTask = nil
                        trafficSettings = nil
                        lastVisibleCableIDs = nil
                        updateTraceAndPortLabels()
                        updatePingOverlay()
                        updatePacketJourney()
                        updateState()
                    }
                    try installCables(plan, for: topology, in: container, models: models)
                } catch is CancellationError {
                } catch {
                    guard let self, let container, cablesEntity === container else { return }
                    roomCablingTask = nil
                    report("No se pudo cargar el cableado. " + error.localizedDescription)
                }
            }
        }

        private func cablePicker(for segment: LabCablePlan.Segment) -> Entity {
            let cable = Entity()
            cable.name = "cable:" + segment.link.id
            let path = segment.pickingPath
            let shapes = zip(path, path.dropFirst()).compactMap { start, end -> ShapeResource? in
                let delta = end - start, length = simd_length(delta)
                guard length > 0.0001 else { return nil }
                let radius: Float = 0.009
                return ShapeResource.generateCapsule(height: length + radius * 2, radius: radius)
                    .offsetBy(rotation: simd_quatf(from: SIMD3(0, 1, 0), to: delta / length), translation: (start + end) / 2)
            }
            cable.components.set(CollisionComponent(shapes: shapes))
            return cable
        }

        private func loadTierCables() {
            guard parent.isTierAR, parent.assembly == nil, parent.isForeground, !tierCablesLoaded, tierCableTask == nil,
                  let container = cablesEntity, let topology = parent.topology else { return }
            let generation = ObjectIdentifier(container)
            let room = parent.room, layout = parent.layout
            let miniature = parent.isTierMiniature
            tierCableTask = Task { @MainActor [weak self] in
                do {
                    self?.parent.walkthrough?.tierCableStatus = .loading
                    let geometry = try await Self.roomCableGeometry(topology, room: room, layout: layout, visibleLinks: nil,
                                                                   cableSides: miniature ? 4 : 8)
                    try Task.checkCancellation()
                    let mesh = try await Self.assemblyMeshResource(geometry.batches.map(\.1))
                    try Task.checkCancellation()
                    guard let self, let container = cablesEntity, ObjectIdentifier(container) == generation else { return }
                    if let mesh {
                        container.addChild(ModelEntity(mesh: mesh, materials: geometry.batches.map { cableMaterial($0.0) }))
                    }
                    if !miniature {
                        for segment in geometry.plan.segments {
                            autoreleasepool { container.addChild(cablePicker(for: segment)) }
                        }
                    }
                    pingPaths = Dictionary(uniqueKeysWithValues: geometry.plan.segments.map { ($0.link.id, $0.points) })
                    makeTraffic(topology, paths: pingPaths, cables: container)
                    parent.walkthrough?.renderedLinks = Set(pingPaths.keys)
                    parent.walkthrough?.tierCableStatus = .idle
                    trafficSettings = nil
                    tierCablesLoaded = true
                    tierCableTask = nil
                    updateTraceAndPortLabels()
                    updatePingOverlay()
                    updatePacketJourney()
                    configureTraffic()
                } catch is CancellationError {
                } catch {
                    guard let self, let container = cablesEntity, ObjectIdentifier(container) == generation else { return }
                    tierCableTask = nil
                    tierCablesLoaded = true
                    parent.walkthrough?.tierCableStatus = .failed
                    Logger(subsystem: "org.unsm.NexusRoomCapture", category: "scene")
                        .error("Cableado AR de Tier IV: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private func reportCableReviews(_ count: Int) {
            guard parent.onCableReviews != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, self.view != nil else { return }
                self.parent.onCableReviews?(count)
            }
        }

        private func makeTraffic(_ topology: LabTopology, paths: [String: [SIMD3<Float>]], cables: Entity) {
            activeTraffic.removeAll()
            trafficCircuits.removeAll()
            pulsePairs.removeAll()
            for link in topology.links where link.circuitID == nil || link.id == link.circuitID {
                let circuit = topology.circuit(for: link)
                let segments = circuit.compactMap { paths[$0.id] }
                guard segments.count == circuit.count, let route = LabTrafficRoute(segments) else { continue }
                let terminals = Self.terminals(of: circuit)
                let participants = Set(circuit.flatMap { [$0.fromDeviceID, $0.toDeviceID] })
                trafficCircuits.append(.init(id: link.id, links: Set(circuit.map(\.id)), devices: participants,
                                             terminals: terminals, route: route, cableRadius: link.medium.cableRadius))
            }
            guard !trafficCircuits.isEmpty else { return }
            let dot = MeshResource.generateSphere(radius: 0.005)
            for _ in 0..<min(5, trafficCircuits.count) {
                let lights = [ModelEntity(mesh: dot, materials: [materials.power]),
                              ModelEntity(mesh: dot, materials: [materials.activity]),
                              ModelEntity(mesh: dot, materials: [materials.power]),
                              ModelEntity(mesh: dot, materials: [materials.activity])]
                for marker in lights {
                    marker.isEnabled = false
                    cables.addChild(marker)
                }
                pulsePairs.append(lights)
            }
        }

        private static func terminals(of circuit: [LabTopology.Link]) -> [LabTopology.Port] {
            guard let first = circuit.first, let last = circuit.last else { return [] }
            return [.init(deviceID: first.fromDeviceID, name: first.fromPort),
                    .init(deviceID: last.toDeviceID, name: last.toPort)]
        }

        private func refreshSignalLamps(_ topology: LabTopology?, settings: TrafficSettings) -> Set<String> {
            guard let topology else { return [] }
            let devices = Dictionary(uniqueKeysWithValues: topology.devices.map { ($0.id, $0) })
            let pending = topology.pendingSignalDevices(in: parent.layout, assembly: settings.assembly)
            var active = Set<String>(), used = Set<LabTopology.Port>()
            for link in topology.links where link.circuitID == nil || link.id == link.circuitID {
                let circuit = topology.circuit(for: link)
                let signal = LabTopology.signal(for: circuit, devices: devices, poweredOff: settings.poweredOff,
                                                pending: pending, negotiating: settings.negotiatingLink)
                if signal == .active { active.insert(link.id) }
                guard !parent.usesCompactTierOverview, [.copper, .fiber, .serial].contains(link.medium) else { continue }
                for port in Self.terminals(of: circuit) {
                    guard let device = devices[port.deviceID], !device.modelID.hasPrefix("patch-"),
                          let parent = deviceModels[device.id], let socket = try? LabScenePort.local(device, port.name) else { continue }
                    used.insert(port)
                    let lamp: ModelEntity
                    if let existing = portLamps[port] {
                        lamp = existing
                    } else {
                        let mesh = portLampMesh ?? .generateBox(size: SIMD3(0.0042, 0.0028, 0.0024))
                        portLampMesh = mesh
                        lamp = ModelEntity(mesh: mesh, materials: [materials.off])
                        lamp.position = socket.point + socket.normal * 0.003 + SIMD3(0, 0.008, 0)
                        lamp.orientation = simd_quatf(from: LabRackPower.rear, to: socket.normal)
                        parent.addChild(lamp)
                        portLamps[port] = lamp
                    }
                    switch signal {
                    case .active: lamp.model?.materials = [materials.power]
                    case .blocked, .negotiating: lamp.model?.materials = [materials.activity]
                    default: lamp.model?.materials = [materials.off]
                    }
                    lamp.isEnabled = true
                }
            }
            for port in Set(portLamps.keys).subtracting(used) { portLamps.removeValue(forKey: port)?.removeFromParent() }
            return active
        }

        private func isPoweredOff(_ id: String) -> Bool {
            parent.poweredOff.contains(id) || devicePowerParents[id].map { parent.poweredOff.contains($0) } == true
        }

        private func makeFanTray(_ device: LabTopology.Device) throws -> Entity {
            let root = try hardware(device.visualModelID)
            let front = -device.visualSize.z / 2
            var frames = LabSceneMesh(), blades = LabSceneMesh(), intake = LabSceneMesh(), exhaust = LabSceneMesh()
            blades.tube(from: SIMD3(0, 0, -0.0008), to: SIMD3(0, 0, 0.001), radius: 0.0048)
            let blade = SIMD3<Float>(0.0048, 0.010, 0.0017)
            for index in 0..<5 {
                let angle = Float(index) * 2 * .pi / 5
                blades.box(size: blade, center: SIMD3(0.0017, 0.009, 0),
                           matrix: simd_float4x4(simd_quatf(angle: angle, axis: LabRackPower.rear)))
            }
            let rotor = try blades.model(material: materials.metal)
            var rotors: [Entity] = []
            for x: Float in [-0.11, 0, 0.11] {
                let center = SIMD3(x, 0, front - 0.003)
                frames.tube(from: center, to: center + LabRackPower.rear * 0.002, radius: 0.0185)
                let fan = rotor.clone(recursive: false)
                fan.position = center - LabRackPower.rear * 0.002
                root.addChild(fan)
                rotors.append(fan)
                func arrow(in arrows: inout LabSceneMesh, from z: Float) {
                    let start = SIMD3(x, 0.017, z), tip = start + LabRackPower.rear * 0.095
                    arrows.tube(from: start, to: tip, radius: 0.0027)
                    for side: Float in [-1, 1] {
                        arrows.tube(from: tip, to: tip + SIMD3(side * 0.014, 0, -0.019), radius: 0.0027)
                    }
                }
                arrow(in: &intake, from: front - 0.14)
                arrow(in: &exhaust, from: -front + 0.011)
            }
            root.addChild(try frames.model(material: materials.dark))
            let airflow = Entity()
            airflow.addChild(try intake.model(material: materials.accent))
            airflow.addChild(try exhaust.model(material: materials.activity))
            var warmth = materials.activity
            warmth.blending = .transparent(opacity: 0.16)
            let warmZone = ModelEntity(mesh: .generateBox(size: SIMD3(0.29, 0.048, 0.13), cornerRadius: 0.022),
                                       materials: [warmth])
            warmZone.position = SIMD3(0, 0.017, -front + 0.077)
            airflow.addChild(warmZone)
            airflow.isEnabled = false
            root.addChild(airflow)
            fanTrays[device.id] = (rotors, airflow)
            return root
        }

        private func configureTraffic() {
            let visible = parent.isForeground && (parent.mode != .ar || tracking && !awaitingPlacement)
            let enabled = parent.showTraffic && parent.showCables && visible
            let settings = TrafficSettings(enabled: enabled, visibleLinks: parent.visibleCableIDs,
                                           reducedMotion: parent.reduceMotion || parent.usesCompactTierOverview,
                                           poweredOff: parent.poweredOff, links: parent.topology?.links ?? [],
                                           assembly: parent.assembly, showAirflow: parent.showRackAirflow,
                                           negotiatingLink: parent.negotiatingLink, visible: visible,
                                           trace: parent.selectedLinkID,
                                           focus: parent.lockedDeviceID, monitors: parent.monitorConfigurations,
                                           samplesMonitors: visible && !dashboards.isEmpty && !parent.usesCompactTierOverview)
            guard trafficSettings != settings else { return }
            trafficSettings = settings
            let activeSignals = refreshSignalLamps(parent.topology, settings: settings)
            let traced = settings.links.first { $0.id == settings.trace }
            let circuitID = traced.map { $0.circuitID ?? $0.id }
            var focused: [Int] = [], ordinary: [Int] = []
            for (index, circuit) in trafficCircuits.enumerated() {
                guard activeSignals.contains(circuit.id), enabled, settings.visibleLinks.map(circuit.links.isSubset(of:)) ?? true else { continue }
                if let circuitID {
                    if circuit.id == circuitID { focused.append(index) }
                } else if let focus = settings.focus {
                    if circuit.devices.contains(focus) { focused.append(index) }
                } else { ordinary.append(index) }
            }
            if ordinary.count > pulsePairs.count {
                // Spread the overview across the topology. A trace or a pin keeps its own circuits.
                activeTraffic = pulsePairs.indices.map { ordinary[$0 * ordinary.count / pulsePairs.count] }
            } else {
                activeTraffic = Array((focused + ordinary).prefix(pulsePairs.count))
            }
            for (index, lights) in pulsePairs.enumerated() {
                for marker in lights {
                    marker.isEnabled = index < activeTraffic.count
                }
            }
            trafficTask?.cancel()
            trafficTask = nil
            paintTraffic(at: ProcessInfo.processInfo.systemUptime, staticFrame: settings.reducedMotion)
            updateDashboards(force: true)
            let animateTraffic = !settings.reducedMotion && !activeTraffic.isEmpty
            let movingFans = fanTrays.flatMap { id, tray -> [Entity] in
                let powered = !isPoweredOff(id)
                tray.airflow.isEnabled = powered && settings.showAirflow
                return settings.visible && !settings.reducedMotion && powered ? tray.rotors : []
            }
            guard animateTraffic || !movingFans.isEmpty || settings.samplesMonitors else { return }
            trafficTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    let interval = animateTraffic || !movingFans.isEmpty ? (self?.parent.isTierMiniature == true ? 66 : 33) : 500
                    do { try await Task.sleep(for: .milliseconds(interval)) } catch { break }
                    guard let self else { break }
                    let time = ProcessInfo.processInfo.systemUptime
                    if animateTraffic { self.paintTraffic(at: time, staticFrame: false) }
                    let angle = Float((time * 2.3).truncatingRemainder(dividingBy: 1)) * 2 * .pi
                    let rotation = simd_quatf(angle: angle, axis: LabRackPower.rear)
                    for rotor in movingFans where rotor.isEnabledInHierarchy { rotor.orientation = rotation }
                    self.updateDashboards()
                }
            }
        }

        private func trafficCamera() -> (eye: SIMD3<Float>, forward: SIMD3<Float>, focal: Float)? {
            guard let view, view.bounds.height > 0 else { return nil }
            let height = Float(view.bounds.height)
            if let camera {
                let focal = height / (2 * tan(camera.camera.fieldOfViewInDegrees * .pi / 360))
                return (camera.position, camera.orientation.act(SIMD3(0, 0, -1)), focal)
            }
            guard let arCamera = view.session.currentFrame?.camera, let rootAnchor else { return nil }
            let windowScene = view.window?.windowScene
            let interfaceOrientation: UIInterfaceOrientation?
            if #available(iOS 26, *) { interfaceOrientation = windowScene?.effectiveGeometry.interfaceOrientation }
            else { interfaceOrientation = windowScene?.interfaceOrientation }
            let orientation = interfaceOrientation.flatMap { $0 == .unknown ? nil : $0 } ?? .portrait
            let projection = arCamera.projectionMatrix(for: orientation, viewportSize: view.bounds.size, zNear: 0.01, zFar: 100)
            let transform = simd_inverse(rootAnchor.transform.matrix) * arCamera.transform
            let eye = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                + focusOrigin * parent.sceneScale
            let forward = simd_normalize(-SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            return (eye, forward, height * abs(projection.columns.1.y) / 2)
        }

        private func paintTraffic(at time: TimeInterval, staticFrame: Bool) {
            guard !activeTraffic.isEmpty, let viewGeometry = trafficCamera() else { return }
            for (slot, index) in activeTraffic.enumerated() {
                let circuit = trafficCircuits[index]
                let period = max(1.1, circuit.route.length / 1.3)
                let phase = Float((time / Double(period) + Double(index) * 0.173).truncatingRemainder(dividingBy: 1))
                let outbound: Float = staticFrame ? 0.23 : phase
                let inbound: Float = staticFrame ? 0.73 : 1 - (phase + 0.42).truncatingRemainder(dividingBy: 1)
                let tailLength = min(0.05, 0.033 / circuit.route.length)
                let fractions = [outbound, inbound, outbound - tailLength, inbound + tailLength]
                let surface = circuit.cableRadius * (parent.selectedLinkID == nil ? 1 : 1.55)
                for (index, marker) in pulsePairs[slot].enumerated() {
                    let fraction = fractions[index]
                    let point = circuit.route.point(at: fraction)
                    let delta = point - viewGeometry.eye
                    let depth = simd_dot(delta, viewGeometry.forward)
                    let shown = depth > 0.02 && (0...1).contains(fraction)
                    marker.isEnabled = shown
                    guard shown else { continue }
                    let radius = LabTrafficRoute.markerRadius(cableRadius: circuit.cableRadius, depth: depth,
                                                             projectedPointsAtOneMeter: viewGeometry.focal)
                    marker.scale = SIMD3(repeating: radius / 0.005 * (index < 2 ? 1 : 0.62))
                    // Bias toward the viewer by one wire radius so a tiny packet isn't buried inside the wire.
                    marker.position = point - simd_normalize(delta) * surface * 0.96
                }
                for (index, port) in circuit.terminals.enumerated() {
                    let atJack = index == 0 ? min(outbound, inbound) < 0.12 : max(outbound, inbound) > 0.88
                    portLamps[port]?.isEnabled = staticFrame || !atJack
                }
            }
        }

        private func repaintStaticTraffic() {
            if parent.reduceMotion || parent.usesCompactTierOverview { paintTraffic(at: 0, staticFrame: true) }
        }

        private func wireMaterial(_ medium: LabTopology.Medium) -> SimpleMaterial {
            switch medium {
            case .fiber: return materials.fiberWire
            case .serial: return materials.serialWire
            case .console: return materials.consoleWire
            default: return materials.copperWire
            }
        }

        private func showPortLabels(_ ports: [LabScenePort]) {
            guard let container = portLabelsEntity else { return }
            container.children.removeAll()
            do {
                for port in ports {
                    let tag = try label(port.name, width: 0.12, height: 0.018)
                    tag.position = port.point + port.normal * 0.035 + SIMD3(0, 0.025, 0)
                    tag.orientation = simd_quatf(angle: atan2(port.normal.x, port.normal.z), axis: SIMD3(0, 1, 0))
                    container.addChild(tag)
                }
            } catch { report(error.localizedDescription) }
        }

        private func registerPower(_ entity: Entity, placementID: String) {
            if let model = entity as? ModelEntity {
                if model.name == "power" { indicators[placementID, default: []].append(model) }
                if model.name == "screen" { screens[placementID, default: []].append(model) }
            }
            for child in entity.children { registerPower(child, placementID: placementID) }
        }

        private func hardwareSize(_ id: String) -> SIMD3<Float> { HardwareCatalog.renderSize(id) }

        private func hardwareMeshes(_ id: String) -> [LabSceneMesh] {
            var parts = Array(repeating: LabSceneMesh(), count: 8)
            func box(_ part: Int, _ size: SIMD3<Float>, _ center: SIMD3<Float>) { parts[part].box(size: size, center: center) }
            let size = hardwareSize(id), w = size.x, h = size.y, d = size.z
            let networkChassis = id.hasPrefix("switch-") || id.hasPrefix("router-")
            let rackDevice = RackMount.units(id) == 2 || networkChassis || id.hasPrefix("patch-") || id.hasPrefix("server-")
            if id != "raspberry-pi5" && id != "pt-desktop" {
                box(rackDevice || id == "pc-optiplex7010" || id == "phone-7960" ? 0 : 1, size, .zero)
            }
            let front = -d / 2 - 0.002
            if id.hasPrefix("patch-") {
                let count = LabDemo.ports(id).count / 2
                for side: Float in [-1, 1] {
                    let z = side * (d / 2 + 0.002)
                    box(1, SIMD3(w - 0.004, h - 0.003, 0.004), SIMD3(0, 0, z))
                    for port in 0..<count {
                        let x = (Float(port) - Float(count - 1) / 2) * (w - 0.045) / Float(count)
                        box(2, SIMD3(0.014, 0.014, 0.003), SIMD3(x, -0.004, z + side * 0.002))
                        box(3, SIMD3(0.011, 0.010, 0.002), SIMD3(x, -0.004, z + side * 0.004))
                    }
                }
            } else if id == "ups-9px" {
                box(1, SIMD3(w - 0.012, h - 0.012, 0.006), SIMD3(0, 0, front))
                box(5, SIMD3(0.094, 0.026, 0.003), SIMD3(0.115, -0.005, front - 0.004))
                box(4, SIMD3(0.009, 0.006, 0.003), SIMD3(0.17, -0.009, front - 0.004))
                for slot in 0..<17 {
                    box(3, SIMD3(0.005, 0.039, 0.002), SIMD3(-0.19 + Float(slot) * 0.013, -0.005, front - 0.004))
                }
                for socket in 0..<8 {
                    box(3, SIMD3(0.026, 0.021, 0.004), SIMD3(-0.17 + Float(socket) * 0.044, 0, d / 2 + 0.003))
                }
            } else if networkChassis {
                let rear = d / 2 + 0.001
                let powerSocket = LabRackPower.equipmentSocket(id)
                let isSwitch = id.hasPrefix("switch-")
                box(6, SIMD3(w - 0.006, h - 0.003, 0.004), SIMD3(0, 0, front))
                box(2, SIMD3(w - 0.006, h - 0.004, 0.003), SIMD3(0, 0, rear))
                for end: Float in [-1, 1] {
                    let x = end * (w / 2 - 0.009)
                    for z in [-d / 2 + 0.024, d / 2 - 0.027] {
                        box(3, SIMD3(0.004, 0.0008, 0.004), SIMD3(x, h / 2 + 0.0005, z))
                    }
                    for slit in 0..<14 {
                        let z = -d / 2 + 0.055 + Float(slit) * min(0.009, (d - 0.095) / 14)
                        box(3, SIMD3(0.001, h * 0.43, 0.003), SIMD3(end * (w / 2 + 0.0005), h * 0.04, z))
                    }
                }
                for name in LabDemo.ports(id) {
                    guard let port = LabScenePort.networkPanel(id, port: name) else { continue }
                    let fiber = LabTopology.mediumForPort(modelID: id, port: name) == .fiber
                    let sign = port.normal.z
                    let inner = SIMD3<Float>(fiber ? 0.015 : 0.013, fiber ? 0.008 : 0.010, 0.002)
                    let socket = port.point - port.normal * 0.0005
                    box(2, inner + SIMD3(0.003, 0.003, 0.001), socket - port.normal * 0.001)
                    box(name == "Console" ? 5 : 3, inner, socket + port.normal * 0.0005)
                    if !fiber && name != "Console" {
                        for pin in 0..<8 {
                            box(7, SIMD3(0.0006, 0.0027, 0.0005),
                                socket + SIMD3((Float(pin) - 3.5) * 0.00115, 0.0032, sign * 0.0017))
                        }
                    }
                    if isSwitch && !fiber {
                        box(3, SIMD3(0.003, 0.0024, 0.001), socket + SIMD3(0.008, 0.0058, sign * 0.001))
                    }
                }
                if isSwitch {
                    let ledX = w / 2 - 0.028
                    box(3, SIMD3(0.027, h - 0.010, 0.002), SIMD3(ledX, 0, front - 0.003))
                    for led in 0..<4 {
                        box(led == 0 ? 4 : 2, SIMD3(0.003, 0.002, 0.001),
                            SIMD3(ledX + 0.006, -0.009 + Float(led) * 0.005, front - 0.0045))
                    }
                    box(2, SIMD3(0.006, 0.006, 0.003), SIMD3(ledX - 0.005, -0.008, front - 0.004))
                    if id == "switch-3650" {
                        for x: Float in [-0.145, -0.056] {
                            box(0, SIMD3(0.078, 0.031, 0.005), SIMD3(x, 0, rear + 0.003))
                            box(3, SIMD3(0.022, 0.016, 0.004), SIMD3(x - 0.018, powerSocket.y, powerSocket.z - 0.002))
                            box(2, SIMD3(0.006, 0.018, 0.004), SIMD3(x + 0.031, 0, rear + 0.006))
                        }
                        for x: Float in [0.014, 0.072, 0.13] {
                            box(0, SIMD3(0.052, 0.034, 0.004), SIMD3(x, 0, rear + 0.002))
                            for slit in 0..<8 {
                                box(3, SIMD3(0.002, 0.022, 0.001),
                                    SIMD3(x - 0.018 + Float(slit) * 0.005, 0, rear + 0.004))
                            }
                        }
                        for y: Float in [-0.009, 0.009] {
                            box(3, SIMD3(0.027, 0.009, 0.003), SIMD3(w / 2 - 0.040, y, rear + 0.003))
                        }
                    } else {
                        box(0, SIMD3(0.064, 0.022, 0.003), SIMD3(-0.13, 0, rear + 0.003))
                        box(3, SIMD3(0.028, 0.016, 0.004), powerSocket - SIMD3(0, 0, 0.002))
                        box(5, SIMD3(0.014, 0.012, 0.004), SIMD3(0.118, 0, rear + 0.003))
                    }
                } else {
                    let moduleCount = id == "router-1941" ? 2 : 4
                    for slot in 0..<moduleCount {
                        let center = id == "router-1941"
                            ? SIMD2(Float(slot) * (w * 0.5) - w * 0.25, h * 0.23)
                            : LabScenePort.moduleCenter(id, slot: slot)
                        let width: Float = id == "router-1941" ? 0.095 : 0.059
                        box(0, SIMD3(width, 0.019, 0.004), SIMD3(center.x, center.y, rear + 0.002))
                        for side: Float in [-1, 1] {
                            box(2, SIMD3(0.0035, 0.0035, 0.002),
                                SIMD3(center.x + side * (width / 2 - 0.004), center.y, rear + 0.004))
                        }
                    }
                    box(3, SIMD3(0.026, 0.016, 0.005), powerSocket - SIMD3(0, 0, 0.0025))
                    box(0, SIMD3(0.011, 0.011, 0.005), powerSocket + SIMD3(w * 0.12, 0, -0.0025))
                    if id == "router-2911" {
                        box(0, SIMD3(0.126, 0.027, 0.004), SIMD3(-0.077, 0.025, rear + 0.003))
                    }
                    for led in 0..<4 {
                        box(led == 0 ? 4 : 2, SIMD3(0.0033, 0.0025, 0.002),
                            SIMD3(w / 2 - 0.024 - Float(led) * 0.010, h * 0.22, front - 0.003))
                    }
                    if id != "router-2811" {
                        for row in 0..<3 { for vent in 0..<20 {
                            box(3, SIMD3(0.004, 0.003, 0.001),
                                SIMD3(-w * 0.35 + Float(vent) * 0.008, (Float(row) - 1) * 0.007, front - 0.003))
                        } }
                    }
                }
            } else if id == "firewall-asa5505" {
                for port in 0..<8 {
                    box(3, SIMD3(0.016, 0.014, 0.005), SIMD3(-w / 2 + 0.027 + Float(port) * 0.021, 0, d / 2 + 0.002))
                }
                box(3, SIMD3(0.016, 0.012, 0.004), LabRackPower.equipmentSocket(id) - SIMD3(0, 0, 0.002))
            } else if id.hasPrefix("server-") {
                // Catalogued SFF example: ten 2.5-inch bays; occupancy is illustrative, not detected hardware.
                box(0, SIMD3(w - 0.035, h - 0.006, 0.005), SIMD3(0, 0, front))
                let bayWidth = (w - 0.07) / 5, bayHeight = (h - 0.008) / 2
                for row in 0..<2 { for bay in 0..<5 {
                    let x = -w / 2 + 0.035 + bayWidth * (Float(bay) + 0.5)
                    let y = (Float(row) - 0.5) * bayHeight
                    box(2, SIMD3(bayWidth - 0.002, bayHeight - 0.002, 0.006), SIMD3(x, y, front - 0.004))
                    box(3, SIMD3(bayWidth - 0.01, bayHeight * 0.35, 0.004), SIMD3(x, y, front - 0.009))
                    box(4, SIMD3(0.003, 0.003, 0.004), SIMD3(x + bayWidth * 0.37, y, front - 0.009))
                } }
                for port in LabDemo.ports(id).indices {
                    box(3, SIMD3(0.016, 0.014, 0.004), SIMD3(-0.04 + Float(port) * 0.024, 0, d / 2 + 0.003))
                }
                if id == "server-firewall" {
                    box(2, SIMD3(0.075, 0.021, 0.003), SIMD3(-0.16, 0, front - 0.009))
                }
                for supply in 0..<2 {
                    let socket = LabRackPower.equipmentSocket(id, circuit: supply)
                    let x = socket.x - 0.018
                    box(2, SIMD3(0.068, 0.035, 0.003), SIMD3(x, 0, d / 2 + 0.002))
                    box(3, SIMD3(0.018, 0.013, 0.004), socket - SIMD3(0, 0, 0.002))
                    for vent in 0..<7 {
                        box(3, SIMD3(0.003, 0.022, 0.002), SIMD3(x - 0.025 + Float(vent) * 0.0045, 0, d / 2 + 0.004))
                    }
                }
                for x in [-w / 2 + 0.01, w / 2 - 0.01] { box(2, SIMD3(0.014, h * 0.7, 0.024), SIMD3(x, 0, front - 0.008)) }
                box(4, SIMD3(0.006, 0.006, 0.005), SIMD3(-w / 2 + 0.025, 0, front - 0.005))
            } else if id == "raspberry-pi5" {
                box(0, SIMD3(w * 0.91, 0.004, d * 0.89), SIMD3(0, -0.010, 0))
                box(2, SIMD3(0.045, 0.005, 0.041), SIMD3(-0.010, 0.002, -0.005))
                for fin in 0..<9 {
                    box(2, SIMD3(0.002, 0.010, 0.041),
                        SIMD3(-0.030 + Float(fin) * 0.005, 0.008, -0.005))
                }
                for x: Float in [-0.022, 0.002, 0.026] {
                    box(2, SIMD3(0.016, 0.013, 0.017), SIMD3(x, 0, d / 2 - 0.007))
                    box(3, SIMD3(0.013, 0.008, 0.005), SIMD3(x, 0.002, d / 2 + 0.001))
                }
                for pin in 0..<12 {
                    box(2, SIMD3(0.0018, 0.007, 0.0018),
                        SIMD3(-0.038 + Float(pin) * 0.0042, -0.002, -0.027))
                }
                box(4, SIMD3(0.004, 0.002, 0.004), SIMD3(w / 2 - 0.008, -0.005, -d / 2 + 0.006))
            } else if id == "pt-access-point" {
                for x in [-w * 0.40, w * 0.40] {
                    parts[0].tube(from: SIMD3(x, 0, d * 0.36),
                                  to: SIMD3(x * 1.25, 0.068, d * 0.42), radius: 0.0045)
                }
                box(2, SIMD3(w * 0.85, 0.004, d * 0.83), SIMD3(0, h / 2, 0))
                for led in 0..<3 {
                    box(4, SIMD3(0.004, 0.002, 0.003),
                        SIMD3(-w * 0.33 + Float(led) * 0.012, h / 2 + 0.003, front + 0.022))
                }
            } else if id == "access-point" {
                box(2, SIMD3(w * 0.72, 0.006, d * 0.72), SIMD3(0, -h / 2, 0))
                box(4, SIMD3(0.030, 0.002, 0.002), SIMD3(0, h / 2 + 0.001, -d / 2 + 0.02))
                for slot in 0..<8 {
                    box(3, SIMD3(0.002, 0.009, 0.001), SIMD3(-0.052 + Float(slot) * 0.014, -0.007, front + 0.001))
                }
            } else if id == "camera-ip" {
                parts[2].tube(from: SIMD3(0, -h / 2 - 0.032, 0.038), to: SIMD3(0, 0.006, 0.038), radius: 0.017)
                box(2, SIMD3(w, 0.006, 0.083), SIMD3(0, -h / 2 - 0.033, 0.028))
                parts[3].tube(from: SIMD3(0, 0, front + 0.001), to: SIMD3(0, 0, front - 0.006), radius: 0.033)
                parts[5].tube(from: SIMD3(0, 0, front - 0.006), to: SIMD3(0, 0, front - 0.008), radius: 0.018)
                for n in 0..<8 {
                    let angle = Float(n) * .pi / 4
                    parts[2].tube(from: SIMD3(cos(angle) * 0.026, sin(angle) * 0.026, front - 0.007),
                                  to: SIMD3(cos(angle) * 0.026, sin(angle) * 0.026, front - 0.009), radius: 0.003)
                }
            } else if id == "pc-optiplex7010" {
                box(1, SIMD3(w - 0.012, h - 0.015, 0.007), SIMD3(0, 0, front))
                for vent in 0..<12 { box(3, SIMD3(w * 0.6, 0.005, 0.004), SIMD3(0, -h * 0.35 + Float(vent) * h * 0.04, front - 0.005)) }
                box(3, SIMD3(w * 0.7, 0.015, 0.004), SIMD3(0, h * 0.29, front - 0.005))
                box(4, SIMD3(0.01, 0.01, 0.005), SIMD3(0, h * 0.4, front - 0.005))
            } else if id == "pt-desktop" {
                let monitorX = -w * 0.12, towerX = w * 0.36
                box(0, SIMD3(w * 0.22, h * 0.83, d * 0.76), SIMD3(towerX, -h * 0.075, 0))
                box(3, SIMD3(w * 0.17, h * 0.39, 0.005), SIMD3(towerX, -h * 0.20, -d * 0.39))
                box(4, SIMD3(0.009, 0.006, 0.005), SIMD3(towerX, h * 0.23, -d * 0.39))
                box(0, SIMD3(w * 0.65, h * 0.58, 0.023), SIMD3(monitorX, h * 0.20, d * 0.27))
                box(5, SIMD3(w * 0.60, h * 0.51, 0.003), SIMD3(monitorX, h * 0.20, d * 0.27 - 0.013))
                box(2, SIMD3(0.036, h * 0.35, 0.04), SIMD3(monitorX, -h * 0.26, d * 0.30))
                box(0, SIMD3(0.16, 0.012, 0.10), SIMD3(monitorX, -h / 2 + 0.006, d * 0.24))
                box(0, SIMD3(w * 0.56, 0.012, 0.075),
                    SIMD3(monitorX, -h / 2 + 0.006, -d * 0.29))
                for row in 0..<4 {
                    box(2, SIMD3(w * 0.49, 0.003, 0.008),
                        SIMD3(monitorX, -h / 2 + 0.014, -d * 0.38 + Float(row) * 0.014))
                }
            } else if id == "pt-server" {
                box(0, SIMD3(w * 0.91, h * 0.95, 0.006), SIMD3(0, 0, front))
                for bay in 0..<5 {
                    let y = h * 0.32 - Float(bay) * h * 0.13
                    box(2, SIMD3(w * 0.68, h * 0.091, 0.006), SIMD3(0, y, front - 0.004))
                    box(3, SIMD3(w * 0.54, 0.006, 0.004), SIMD3(0, y, front - 0.008))
                }
                box(4, SIMD3(0.007, 0.007, 0.004), SIMD3(-w * 0.30, -h * 0.38, front - 0.002))
            } else if id == "laptop-latitude5420" || id == "pt-laptop" {
                for row in 0..<4 { for key in 0..<10 {
                    box(3, SIMD3(0.019, 0.002, 0.016), SIMD3(-0.115 + Float(key) * 0.025, h / 2 + 0.002, -0.025 + Float(row) * 0.021))
                } }
                box(0, SIMD3(0.09, 0.001, 0.045), SIMD3(0, h / 2 + 0.002, -0.073))
                box(0, SIMD3(w, 0.19, 0.012), SIMD3(0, 0.10, d / 2))
                box(5, SIMD3(w - 0.022, 0.165, 0.003), SIMD3(0, 0.10, d / 2 - 0.008))
            } else if id == "pt-printer" {
                box(2, SIMD3(w * 0.78, 0.008, d * 0.6), SIMD3(0, h / 2 + 0.003, 0))
                box(3, SIMD3(w * 0.72, 0.026, 0.005), SIMD3(0, 0.004, front))
                box(3, SIMD3(0.016, 0.014, 0.004), SIMD3(0, -h * 0.25, d / 2 + 0.002))
            } else if id == "pt-tablet" || id == "pt-smartphone" {
                box(0, SIMD3(w * 0.99, 0.002, d * 0.99), SIMD3(0, h / 2, 0))
                box(5, SIMD3(w * 0.92, 0.002, d * 0.91), SIMD3(0, h / 2, 0))
                box(3, SIMD3(w * 0.17, 0.001, d * 0.014), SIMD3(0, h / 2 + 0.0015, -d * 0.44))
            } else if id == "pt-power-distribution" {
                box(0, SIMD3(w * 0.95, h * 0.75, 0.005), SIMD3(0, 0, front))
                for index in 0..<6 {
                    box(3, SIMD3(0.028, 0.015, 0.004),
                        SIMD3(-w * 0.36 + Float(index) * w * 0.13, 0, front - 0.003))
                }
                box(4, SIMD3(0.005, 0.004, 0.003), SIMD3(w * 0.44, 0, front - 0.003))
            } else if id == "phone-7960" {
                box(0, SIMD3(w * 0.25, 0.035, d * 0.9), SIMD3(-w * 0.32, h / 2 + 0.015, 0))
                box(5, SIMD3(w * 0.44, 0.003, d * 0.25), SIMD3(w * 0.1, h / 2 + 0.003, d * 0.18))
                for row in 0..<4 { for key in 0..<3 {
                    box(2, SIMD3(0.02, 0.006, 0.017), SIMD3(-0.01 + Float(key) * 0.027, h / 2 + 0.005, -0.075 + Float(row) * 0.025))
                } }
                for key in 0..<6 { box(2, SIMD3(0.017, 0.005, 0.01), SIMD3(w * 0.39, h / 2 + 0.005, -0.005 + Float(key) * 0.017)) }
                for key in 0..<4 { box(2, SIMD3(0.014, 0.005, 0.009), SIMD3(-0.01 + Float(key) * 0.022, h / 2 + 0.005, d * 0.015)) }
            }
            return parts
        }

        private func hardwareMaterials(_ id: String) -> [any RealityKit.Material] {
            let bezel = id == "switch-3650" ? UIColor(white: 0.22, alpha: 1)
                : id == "router-2811" ? UIColor(white: 0.33, alpha: 1)
                : UIColor(red: 0.15, green: 0.29, blue: 0.36, alpha: 1)
            return [materials.graphite, materials.panel, materials.metal,
                materials.dark, materials.power, materials.screen,
                SimpleMaterial(color: bezel, roughness: 0.64, isMetallic: false),
                SimpleMaterial(color: UIColor(red: 0.72, green: 0.56, blue: 0.32, alpha: 1), roughness: 0.38, isMetallic: true)]
        }

        private func hardware(_ id: String, compact: Bool = false) throws -> Entity {
            let templateID = compact ? "overview:" + id : id
            if let template = hardwareTemplates[templateID] { return template.clone(recursive: true) }
            let group = Entity(); group.name = "hardware:" + id
            let appearance: Entity
            if id == Catalyst2960Asset.modelID {
                appearance = Entity()
                appearance.name = Self.catalystLightName
                group.addChild(appearance)
            } else { appearance = group }
            let palette = hardwareMaterials(id)
            for (index, mesh) in hardwareMeshes(id).enumerated() where !mesh.indices.isEmpty {
                // The Tier IV overview keeps the chassis, fascia, sockets and system LED.
                if compact && ![0, 3, 4, 6].contains(index) { continue }
                let model = try mesh.model(material: palette[index])
                if index == 4 { model.name = "power" }; if index == 5 { model.name = "screen" }
                (index == 4 ? group : appearance).addChild(model)
            }
            try addHardwareSelection(to: group, id: id)
            let size = hardwareSize(id), w = size.x, top = size.y / 2, front = -size.z / 2
            let networkChassis = id.hasPrefix("switch-") || id.hasPrefix("router-")
            let rackDevice = RackMount.units(id) == 2 || networkChassis || id.hasPrefix("patch-") || id.hasPrefix("server-")
            if networkChassis && !compact {
                let name = id.hasPrefix("switch-") ? "CATALYST " + String(id.suffix(4)) : "ISR " + String(id.suffix(4))
                appearance.addChild(try topLabel(name, width: 0.084, depth: 0.010,
                                                 at: SIMD3(-w / 2 + 0.053, top, front + 0.045)))
            }
            if !compact, rackDevice, parent.topology == nil, let item = HardwareCatalog.item(id) {
                appearance.addChild(try topLabel(item.name, width: min(w * 0.25, 0.09), depth: 0.012,
                                                 at: SIMD3(w * 0.24, top, front + 0.024)))
            }
            hardwareTemplates[templateID] = group
            return group.clone(recursive: true)
        }

        private func addHardwareSelection(to group: Entity, id: String) throws {
            let size = hardwareSize(id), w = size.x, d = size.z
            var shape = ShapeResource.generateBox(size: size)
            if id == "laptop-latitude5420" || id == "pt-laptop" {
                shape = .generateBox(size: SIMD3(w, 0.23, d)).offsetBy(translation: SIMD3(0, 0.10, 0))
            }
            group.components.set(CollisionComponent(shapes: [shape]))
            var rim = LabSceneMesh()
            let visualSize = id == "laptop-latitude5420" ? SIMD3(w, Float(0.23), d) : size
            let centerY: Float = id == "laptop-latitude5420" ? 0.10 : 0
            let half = visualSize / 2 + SIMD3<Float>(repeating: 0.002)
            for x in [-half.x, half.x] { for z in [-half.z, half.z] { rim.box(size: SIMD3(0.0015, half.y * 2, 0.0015), center: SIMD3(x, centerY, z)) } }
            for y in [-half.y + centerY, half.y + centerY] {
                for z in [-half.z, half.z] { rim.box(size: SIMD3(half.x * 2, 0.0015, 0.0015), center: SIMD3(0, y, z)) }
                for x in [-half.x, half.x] { rim.box(size: SIMD3(0.0015, 0.0015, half.z * 2), center: SIMD3(x, y, 0)) }
            }
            let highlight = try rim.model(material: materials.accent)
            highlight.name = "hardware-selection"; highlight.isEnabled = false
            group.addChild(highlight)
        }

        private func topLabel(_ text: String, width: Float, depth: Float, at surface: SIMD3<Float>,
                              facing face: RackMount.CableFace = .front) throws -> ModelEntity {
            let plate = try label(text, width: width, height: depth)
            plate.position = surface + SIMD3(0, 0.0002, 0)
            plate.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
            if face == .front {
                plate.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0)) * plate.orientation
            }
            return plate
        }

        private func label(_ text: String, width: Float, height: Float) throws -> ModelEntity {
            let material: UnlitMaterial
            if let cached = labelMaterials[text] { material = cached }
            else {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let image = UIGraphicsImageRenderer(size: CGSize(width: 768, height: 96), format: format).image { context in
                    UIColor(white: 0.06, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 768, height: 96))
                    let fontSize = min(CGFloat(58), CGFloat(700) / CGFloat(max(text.count, 1)) / 0.62)
                    let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
                    let style = NSMutableParagraphStyle(); style.alignment = .center
                    (text as NSString).draw(in: CGRect(x: 18, y: (96 - font.lineHeight) / 2, width: 732, height: font.lineHeight + 2),
                                           withAttributes: [.font: font, .foregroundColor: UIColor.white,
                                                            .paragraphStyle: style])
                }
                guard let cgImage = image.cgImage else { throw LabLayoutError.invalid("No se pudo generar una etiqueta de equipo.") }
                let texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
                var value = UnlitMaterial(); value.color = .init(tint: .white, texture: .init(texture))
                labelMaterials[text] = value; material = value
            }
            let entity = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [material])
            entity.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
            return entity
        }

        func updateState() {
            updateCatalystDetail()
            updateEquipmentPreview()
            updateOpenPortMarkers()
            if let assembly = parent.assembly {
                do { try updateAssembly(assembly); updateDashboards() }
                catch { report(error.localizedDescription) }
                return
            }
            updatePortIndicators()
            let scale = SIMD3(repeating: parent.sceneScale)
            if let scaledContent, scaledContent.scale != scale { scaledContent.scale = scale }
            let cutaway = parent.mode == .room && parent.virtualPose == nil && !parent.fullRoomWalls
            if roomUsesWallCutaway != cutaway, let scaledContent {
                do {
                    let replacement = try makeRoom(cutaway: cutaway)
                    roomEntity?.removeFromParent()
                    scaledContent.addChild(replacement)
                    roomEntity = replacement
                    roomUsesWallCutaway = cutaway
                } catch {
                    roomUsesWallCutaway = cutaway
                    report(error.localizedDescription)
                }
            }
            roomEntity?.isEnabled = parent.paintRoom
            updateRoomPlacementPreview()
            cablesEntity?.isEnabled = parent.showCables && previewCableEntity == nil
            let showsPower = parent.showCables && parent.visibleCableIDs == nil
            if parent.mode == .ar, let content = scaledContent,
               (renderedPowerAssembly?.powerOutlets ?? [:]) != parent.directPowerOutlets {
                do {
                    try updatePowerFeeds(directPowerAssembly(), in: content)
                    if let facility = parent.layout.facility, let container = electricalEntity?.parent {
                        let replacement = try makeElectricalRoutes(facility, placements: parent.layout.placements)
                        electricalEntity?.removeFromParent()
                        electricalEntity = replacement
                        container.addChild(replacement)
                    }
                } catch { report(error.localizedDescription) }
            }
            electricalEntity?.isEnabled = showsPower && previewPowerEntity == nil
            powerFeeds?.isEnabled = showsPower && parent.placementPreview == nil
            for lead in electricalLeads.values { lead.isEnabled = showsPower }
            portLabelsEntity?.isEnabled = parent.showCables || parent.inspectionDestination?.port != nil
            if parent.mode == .ar && parent.layout.facility != nil { updateARFocus() }
            if lastPoweredOff != parent.poweredOff {
                lastPoweredOff = parent.poweredOff
                for (rack, upsID, lamp) in pduLamps {
                    let off = isPoweredOff(rack.name) || upsID.map(isPoweredOff) == true
                    lamp.model?.materials = [off ? materials.off : materials.power]
                }
                for (id, models) in indicators { for model in models { model.model?.materials = [isPoweredOff(id) ? materials.off : materials.power] } }
                for (id, models) in screens { for model in models { model.model?.materials = [isPoweredOff(id) ? materials.dark : materials.screen] } }
                for (id, overlays) in consoleScreens {
                    for overlay in overlays { overlay.isEnabled = !isPoweredOff(id) }
                }
            }
            if lastLockedDeviceID != parent.lockedDeviceID {
                lastLockedDeviceID = parent.lockedDeviceID
                highlightedDevice?.isEnabled = false
                highlightedDevice = parent.lockedDeviceID.flatMap { deviceHighlights[$0] }
                highlightedDevice?.isEnabled = true
            }
            configureTraffic()
            for (id, entity) in highlights { entity.isEnabled = (parent.placementPreview?.id ?? parent.selection?.id) == id }
            if lastPingLinks != parent.pingLinks || lastPingBlockedLink != parent.pingBlockedLink {
                lastPingLinks = parent.pingLinks
                lastPingBlockedLink = parent.pingBlockedLink
                updatePingOverlay()
            }
            if lastPacketJourney != parent.packetJourney || lastPacketConceals != parent.packetConcealsFailure {
                lastPacketJourney = parent.packetJourney
                lastPacketConceals = parent.packetConcealsFailure
                updatePacketJourney()
            }
            if lastSelectedLinkID != parent.selectedLinkID || lastInspectedPort != parent.inspectionDestination {
                lastSelectedLinkID = parent.selectedLinkID
                lastInspectedPort = parent.inspectionDestination
                updateTraceAndPortLabels()
            }
            if lastVisibleCableIDs != parent.visibleCableIDs {
                lastVisibleCableIDs = parent.visibleCableIDs
                for (id, cable) in linkEntities { cable.isEnabled = parent.visibleCableIDs?.contains(id) ?? true }
                cableGuides?.isEnabled = parent.visibleCableIDs == nil
            }
            if parent.selection != nil && selectedHardwareHighlight !== highlightedDevice { selectedHardwareHighlight?.isEnabled = false }
            if parent.mode == .room && parent.virtualPose == nil {
                let key = parent.focusDeviceID.map { "device:" + $0 } ?? parent.selection.map { "placement:" + $0.id }
                if let destination = parent.inspectionDestination, let topology = parent.topology,
                   parent.inspectionRevision != lastInspectionRevision {
                    lastInspectionRevision = parent.inspectionRevision
                    focusOrbit(on: destination, in: topology)
                } else if key != lastFocusKey {
                    lastFocusKey = key
                    if let id = parent.focusDeviceID,
                       let device = parent.topology?.devices.first(where: { $0.id == id }),
                       let placement = parent.layout.placements.first(where: { $0.id == device.placementID }) {
                        let rotation = simd_quatf(angle: placement.yaw, axis: SIMD3(0, 1, 0))
                        cameraTarget = placement.position + rotation.act(device.offset)
                        cameraRadius = max(0.8, simd_length(device.visualSize) * 2)
                        cameraYaw = placement.yaw + .pi / 10; cameraPitch = 0.22
                        cameraMoved = true
                        updateCamera()
                    } else if let placement = parent.selection {
                        cameraTarget = placement.position + SIMD3(0, placement.size.y / 2, 0)
                        cameraRadius = max(2.5, simd_length(placement.size) * 1.5)
                        cameraYaw = placement.yaw + .pi / 10; cameraPitch = 0.3
                        cameraMoved = true
                        updateCamera()
                    }
                }
            }
        }

        private func updateCatalystDetail() {
            let detail = parent.catalystDetail
            let host = detail.flatMap { deviceModels[$0.deviceID] }
            guard catalystHost !== host || catalystTemplate !== detail?.entity else { return }
            catalystHost?.findEntity(named: Self.catalystLightName)?.isEnabled = true
            catalystOverride?.removeFromParent()
            catalystOverride = nil
            catalystHost = host
            catalystTemplate = detail?.entity
            guard let host, let detail, let light = host.findEntity(named: Self.catalystLightName) else { return }
            let appearance = detail.entity.clone(recursive: true)
            host.addChild(appearance)
            light.isEnabled = false
            catalystOverride = appearance
        }

        private func applyPlacementPreview(_ placement: LabPlacement) {
            guard let model = placementModels[placement.id] else { return }
            model.position = placement.position
            model.orientation = simd_quatf(angle: placement.yaw, axis: SIMD3(0, 1, 0))
        }

        private var pendingRoomPlacement: LabPlacement? {
            guard parent.mode == .room, parent.isForeground, parent.showCables, parent.topology != nil,
                  let target = parent.placementPreview, target != previewedPlacement, target != failedRoomPreview,
                  target != parent.layout.placements.first(where: { $0.id == target.id }) else { return nil }
            return target
        }

        private func updateRoomPlacementPreview() {
            if let target = parent.placementPreview, parent.showCables, parent.topology != nil, parent.isForeground,
               let original = parent.layout.placements.first(where: { $0.id == target.id }), target != original {
                requestRoomRouting()
                return
            }
            let needsRestore = previewCableEntity != nil
            failedRoomPreview = nil
            roomRoutingTask?.cancel(); roomRoutingTask = nil
            previewCableEntity?.removeFromParent(); previewCableEntity = nil
            previewPowerEntity?.removeFromParent(); previewPowerEntity = nil
            if needsRestore { reportCableReviews(committedCableReviews) }
            guard previewedPlacement != parent.placementPreview else { return }
            if let previous = previewedPlacement, let original = parent.layout.placements.first(where: { $0.id == previous.id }) {
                applyPlacementPreview(original)
            }
            if let target = parent.placementPreview { applyPlacementPreview(target) }
            previewedPlacement = parent.placementPreview
        }

        private func requestRoomRouting() {
            guard roomRoutingTask == nil, pendingRoomPlacement != nil else { return }
            roomRoutingTask = Task { @MainActor [weak self] in
                while !Task.isCancelled, let target = self?.pendingRoomPlacement,
                      let topology = self?.parent.topology, let room = self?.parent.room,
                      var layout = self?.parent.layout,
                      let index = layout.placements.firstIndex(where: { $0.id == target.id }) {
                    layout.placements[index] = target
                    do {
                        let visibleLinks = self?.parent.visibleCableIDs
                        let geometry = try await Self.roomCableGeometry(topology, room: room, layout: layout, visibleLinks: visibleLinks)
                        try Task.checkCancellation()
                        let mesh = try await Self.assemblyMeshResource(geometry.batches.map(\.1))
                        try Task.checkCancellation()
                        guard let self, let content = scaledContent, parent.showCables, parent.isForeground,
                              parent.placementPreview?.id == target.id else { break }
                        // The rack and its cable ends are published together from the same layout.
                        let replacement = mesh.map { model in
                            ModelEntity(mesh: model, materials: geometry.batches.map { cableMaterial($0.0) })
                        } ?? ModelEntity()
                        if visibleLinks == nil, target.kind == .rack, let facility = layout.facility, let facilityModel {
                            let power = try makeElectricalRoutes(facility, placements: layout.placements)
                            previewPowerEntity?.removeFromParent()
                            facilityModel.addChild(power)
                            previewPowerEntity = power
                            electricalEntity?.isEnabled = false
                        }
                        previewCableEntity?.removeFromParent()
                        content.addChild(replacement)
                        previewCableEntity = replacement
                        cablesEntity?.isEnabled = false
                        applyPlacementPreview(target)
                        previewedPlacement = target
                        reportCableReviews(geometry.plan.reviewCount)
                    } catch is CancellationError { break }
                    catch {
                        self?.failedRoomPreview = target
                        self?.report(error.localizedDescription)
                        break
                    }
                }
                if !Task.isCancelled { self?.roomRoutingTask = nil }
            }
        }

        @concurrent private static func roomCableGeometry(
            _ topology: LabTopology, room: RoomStructure, layout: LabLayout, visibleLinks: Set<String>?,
            cableSides: Int = 8
        ) async throws -> (batches: [(AssemblyWireStyle, LabSceneMesh)], plan: LabCablePlan) {
            let plan = try LabCablePlan.make(topology, room: room, layout: layout)
            let guides = visibleLinks == nil ? guideMeshes(plan.guides, anchors: plan.anchors, terminations: plan.terminations,
                                     organizers: plan.organizers, floor: layout.floorHeight,
                                     overhead: plan.channelHeight, ceiling: plan.ceiling) : []
            let segments = plan.segments.filter { visibleLinks?.contains($0.link.id) ?? true }
            let paths = segments.map { LabCablePacking.Path(link: $0.link, points: $0.points) }
            let plugs = connectorMeshes(for: segments.map { ($0.link.medium, $0.endpoints) })
            return (guides + wireMeshes(paths, sides: cableSides) + plugs, plan)
        }

        private func updateAssembly(_ assembly: LabARAssembly) throws {
            guard let content = scaledContent else { return }
            if waypointGrip != nil && (!parent.assemblyWaypointsEditable || waypointGrip?.linkID != parent.selectedLinkID) {
                waypointGrip = nil
            }
            let selected = parent.selectedAssemblyItem
            for (id, outline) in highlights { outline.isEnabled = selected == .support(id) }
            for (id, outline) in deviceHighlights { outline.isEnabled = selected == .device(id) }
            for (id, entity) in assemblyAccessories { entity.findEntity(named: "hardware-selection")?.isEnabled = selected == id }
            if renderedAssembly == nil || !parent.showCables || parent.topology == nil
                || assembly.hasSameCableLayout(as: wiredAssembly) {
                try presentAssembly(assembly, in: content)
            }
            cablesEntity?.isEnabled = parent.showCables && renderedAssembly?.hasSameCableLayout(as: wiredAssembly) == true
            for lead in electricalLeads.values { lead.isEnabled = parent.showCables }
            powerFeeds?.isEnabled = parent.showCables && parent.assemblyEditID == nil
            waypointHandleRoot?.isEnabled = parent.assemblyWaypointsEditable && waypointHandleLinkID == parent.selectedLinkID
            try updateRackGuide()
            updatePortIndicators()
            requestAssemblyRouting()
        }

        private func updatePortIndicators() {
            let ports: [LabTopology.Port]
            if let source = parent.assemblyPortSource {
                ports = [source] + [parent.assemblyPortDestination].compactMap { $0 }
            } else if let topology = parent.topology, let link = topology.links.first(where: { $0.id == parent.selectedLinkID }) {
                let circuit = topology.circuit(for: link)
                let start = circuit.first ?? link, end = circuit.last ?? link
                ports = [.init(deviceID: start.fromDeviceID, name: start.fromPort), .init(deviceID: end.toDeviceID, name: end.toPort)]
            } else if let destination = parent.inspectionDestination, let port = destination.port {
                ports = [.init(deviceID: destination.deviceID, name: port)]
            } else {
                ports = []
            }
            guard indicatedPorts != ports else { return }
            indicatedPorts = ports
            portIndicators.forEach { $0.removeFromParent() }
            portIndicators = ports.enumerated().compactMap { index, port in
                guard let model = deviceModels[port.deviceID],
                      let device = parent.topology?.devices.first(where: { $0.id == port.deviceID }),
                      let location = try? LabScenePort.local(device, port.name) else { return nil }
                let width: Float = port.name.hasPrefix("Serial") ? 0.025 : device.modelID == "patch-copper" ? 0.014 : 0.018
                var frame = LabSceneMesh()
                for side: Float in [-1, 1] {
                    frame.box(size: SIMD3(width, 0.002, 0.002), center: SIMD3(0, side * 0.009, 0))
                    frame.box(size: SIMD3(0.002, 0.016, 0.002), center: SIMD3(side * (width / 2 - 0.001), 0, 0))
                }
                guard let marker = try? frame.model(material: UnlitMaterial(color: index == 0 ? .systemBlue : .systemTeal)) else {
                    return nil
                }
                marker.position = location.point + location.normal * 0.009
                marker.orientation = simd_quatf(from: SIMD3(0, 0, 1), to: location.normal)
                model.addChild(marker)
                return marker
            }
        }

        private func updateOpenPortMarkers() {
            guard markedOpenPorts != parent.selectableScenePorts else { return }
            markedOpenPorts = parent.selectableScenePorts
            openPortMarkers.forEach { $0.removeFromParent() }
            openPortMarkers.removeAll()
            guard let ports = markedOpenPorts, let topology = parent.topology else { return }
            for (id, ports) in Dictionary(grouping: ports, by: \.deviceID) {
                guard let entity = deviceModels[id], let device = topology.devices.first(where: { $0.id == id }) else { continue }
                var mesh = LabSceneMesh()
                for port in ports {
                    guard let location = try? LabScenePort.local(device, port.name) else { continue }
                    var matrix = simd_float4x4(simd_quatf(from: SIMD3(0, 0, 1), to: location.normal))
                    matrix.columns.3 = SIMD4(location.point + location.normal * 0.009, 1)
                    mesh.box(size: SIMD3(0.011, 0.002, 0.002), center: SIMD3(0, 0.008, 0), matrix: matrix)
                }
                if !mesh.indices.isEmpty, let marker = try? mesh.model(material: materials.accent) {
                    entity.addChild(marker)
                    openPortMarkers.append(marker)
                }
            }
        }

        private func updateEquipmentPreview() {
            guard let placement = parent.equipmentPreview, let content = scaledContent else {
                equipmentOutline?.isEnabled = false
                return
            }
            if equipmentOutlineSize != placement.size {
                equipmentOutline?.removeFromParent()
                let size = placement.size
                let halfWidth = size.x / 2, halfDepth = size.z / 2
                let corners: [SIMD2<Float>] = [[-halfWidth, -halfDepth], [halfWidth, -halfDepth],
                                               [halfWidth, halfDepth], [-halfWidth, halfDepth]]
                var mesh = previewOutline(corners)
                for (point, next) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                    let base = SIMD3(point.x, 0.018, point.y)
                    mesh.tube(from: base, to: base + SIMD3(0, size.y, 0), radius: 0.004)
                    mesh.tube(from: base + SIMD3(0, size.y, 0), to: SIMD3(next.x, size.y + 0.018, next.y), radius: 0.004)
                }
                equipmentOutline = try? mesh.model(material: materials.accent)
                equipmentOutlineSize = placement.size
                if let equipmentOutline { content.addChild(equipmentOutline) }
            }
            equipmentOutline?.position = placement.position
            equipmentOutline?.orientation = simd_quatf(angle: placement.yaw, axis: SIMD3(0, 1, 0))
            equipmentOutline?.isEnabled = true
        }

        private func updateRackGuide() throws {
            guard guidedRackID != parent.assemblyRackID else { return }
            rackGuide?.removeFromParent()
            rackGuide = nil
            guidedRackID = parent.assemblyRackID
            guard let id = guidedRackID, let model = placementModels[id],
                  let rack = parent.layout.placements.first(where: { $0.id == id }), rack.kind == .rack else { return }
            var grid = LabSceneMesh()
            let capacity = RackMount.capacity(height: rack.size.y)
            let occupied = parent.topology?.devices.filter { $0.placementID == id }.flatMap { device -> [Int] in
                let start = RackMount.slot(device.visualModelID, near: device.offset.y)
                return Array(start..<(start + RackMount.units(device.visualModelID)))
            } ?? []
            let used = Set(occupied)
            for slot in 0..<capacity where !used.contains(slot) {
                let y = RackMount.base + Float(slot) * RackMount.unit
                grid.box(size: SIMD3(rack.size.x * 0.73, 0.0035, 0.009),
                         center: SIMD3(0, y + 0.005, -rack.size.z / 2 - 0.016))
            }
            guard !grid.indices.isEmpty else { return }
            let overlay = try grid.model(material: materials.accent)
            model.addChild(overlay)
            rackGuide = overlay
        }

        private func presentAssembly(_ assembly: LabARAssembly, in content: Entity) throws {
            if renderedAssembly?.pieces != assembly.pieces {
                try applyAssemblyPieces(assembly, to: content)
            }
            if parent.assemblyEditID == nil, renderedPowerAssembly?.pieces != assembly.pieces
                || renderedPowerAssembly?.powerOutlets != assembly.powerOutlets {
                try updatePowerFeeds(assembly, in: content)
            }
            renderedAssembly = assembly
        }

        private func applyAssemblyPieces(_ assembly: LabARAssembly, to content: Entity) throws {
            let pieces = assembly.resolvedPieces(in: parent.layout)
            let positions = Dictionary(pieces.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
            let previous = renderedAssembly.map { assembly in
                Dictionary(assembly.resolvedPieces(in: parent.layout).map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
            }
            for (id, model) in placementModels {
                let piece = positions[.support(id)]
                guard previous == nil || previous?[.support(id)] != piece else { continue }
                model.isEnabled = piece != nil
                if let piece {
                    model.position = piece.position
                    model.orientation = piece.rotation
                }
            }
            let fixtures = Dictionary(uniqueKeysWithValues: (parent.layout.facility?.fixtures ?? []).map { ($0.id, $0) })
            for device in parent.topology?.devices ?? [] {
                guard let model = deviceModels[device.id] else { continue }
                let piece = positions[.device(device.id)]
                guard previous == nil || previous?[.device(device.id)] != piece else { continue }
                if let piece {
                    if model.parent !== content { content.addChild(model) }
                    model.position = piece.world(SIMD3(0, device.visualSize.y / 2, 0))
                    model.orientation = piece.rotation
                    model.isEnabled = true
                } else if let support = placementModels[device.placementID] {
                    if model.parent !== support { support.addChild(model) }
                    model.position = device.offset
                    model.orientation = simd_quatf()
                    model.isEnabled = true
                }
            }
            let oldDetached = Set(previous?.keys.filter { if case .device = $0 { true } else { false } } ?? [])
            let detached = Set(positions.keys.filter { if case .device = $0 { true } else { false } })
            if let topology = parent.topology, renderedAssembly != nil, oldDetached != detached {
                let changed = oldDetached.symmetricDifference(detached)
                let rackIDs = Set(topology.devices.filter { changed.contains(.device($0.id)) }.map(\.placementID))
                for placement in parent.layout.placements where placement.kind == .rack && rackIDs.contains(placement.id) {
                    if let model = placementModels[placement.id] { try addRackElectrical(to: model, placement: placement, assembly: assembly) }
                }
            }
            for (id, object) in assemblyAccessories where positions[id] == nil {
                object.removeFromParent()
                assemblyAccessories.removeValue(forKey: id)
                pduHits = pduHits.filter { $0.value.rack != id }
                pduLamps.removeAll { $0.rack == id }
            }
            dashboards.removeAll { dashboard in dashboard.owner.map { positions[$0] == nil } ?? false }
            for piece in pieces {
                guard previous?[piece.id] != piece else { continue }
                let object: Entity
                if let existing = assemblyAccessories[piece.id] {
                    object = existing
                } else {
                    switch piece.id {
                    case .extra(let id, _):
                        object = try makeAssemblyAccessory(id, pduConfiguration: parent.layout.pduConfiguration(for: piece.id.name),
                                                           rackOwner: piece.id)
                    case .infrastructure(let id):
                        guard let fixture = fixtures[id] else { continue }
                        object = try makeTierFixture(fixture)
                    case .monitor(let deviceID, let panel, _):
                        guard let device = parent.topology?.devices.first(where: { $0.id == deviceID }) else { continue }
                        object = makeAssemblyMonitor(device, panel: panel, owner: piece.id, mount: piece.monitorMount)
                    default: continue
                    }
                    object.name = "assembly:" + piece.id.name
                    content.addChild(object)
                    assemblyAccessories[piece.id] = object
                }
                object.position = piece.position
                object.orientation = piece.rotation
            }
        }

        private var pendingCableAssembly: LabARAssembly? {
            guard parent.isForeground, parent.showCables, let assembly = parent.assembly,
                  !assembly.hasSameCableLayout(as: wiredAssembly) || wiredTraceID != parent.selectedLinkID
                    || wiredAssemblyLinks != parent.topology?.links else { return nil }
            return assembly
        }

        private func requestAssemblyRouting() {
            guard assemblyRoutingTask == nil, parent.topology != nil, pendingCableAssembly != nil else { return }
            assemblyRoutingTask = Task { @MainActor [weak self] in
                // Keep one build in flight. Draw its result and pick up the newest pose for the next build.
                while !Task.isCancelled, let assembly = self?.pendingCableAssembly,
                      let topology = self?.parent.topology, let layout = self?.parent.layout {
                    let editID = self?.parent.assemblyEditID
                    let traceID = self?.parent.selectedLinkID
                    do {
                        let geometry = await Self.assemblyCableGeometry(assembly, topology: topology, layout: layout, traceID: traceID)
                        try Task.checkCancellation()
                        guard self?.canPresentAssembly(assembly, editID: editID) == true else { continue }
                        let mesh = try await Self.assemblyMeshResource(geometry.batches.map(\.1))
                        try Task.checkCancellation()
                        guard let self else { return }
                        guard topology.links == self.parent.topology?.links else { continue }
                        try self.showAssemblyCableGeometry(mesh, styles: geometry.batches.map(\.0), assembly: assembly,
                                                           editID: editID, traceID: traceID, topology: topology,
                                                           paths: geometry.paths, reviewCount: geometry.reviewCount,
                                                           waypointHeight: geometry.waypointHeight)
                    } catch is CancellationError {
                        break
                    } catch {
                        if !Task.isCancelled { self?.report(error.localizedDescription) }
                        break
                    }
                }
                if !Task.isCancelled { self?.assemblyRoutingTask = nil }
            }
        }

        private enum AssemblyWireStyle: Sendable {
            case guide, termination, wire(LabTopology.Medium), capacity, trace
            case connector, copperPlug, copperContacts, boot
        }

        @concurrent private static func assemblyCableGeometry(
            _ assembly: LabARAssembly, topology: LabTopology, layout: LabLayout, traceID: String?
        ) async -> (batches: [(AssemblyWireStyle, LabSceneMesh)], paths: [String: [SIMD3<Float>]], reviewCount: Int, waypointHeight: Float?) {
            let plan = assembly.cablePlan(in: topology, layout: layout)
            let guides = guideMeshes(plan.channels, anchors: plan.anchors, terminations: plan.terminations,
                                     organizers: plan.organizers, floor: plan.floor, overhead: plan.overhead, ceiling: nil)
            let connections = plan.connections.filter(\.routed)
            let paths = connections.map { LabCablePacking.Path(link: $0.link, points: $0.points) }
            let plugs = connectorMeshes(for: connections.map { ($0.link.medium, $0.endpoints) })
            let traced = plan.connections.first { $0.link.id == traceID }
            return (guides + wireMeshes(paths, traceID: traced.map { $0.link.circuitID ?? $0.link.id }) + plugs,
                    Dictionary(uniqueKeysWithValues: connections.map { ($0.link.id, $0.points) }),
                    plan.reviewCount + plan.overCapacityLinks.count, traced?.waypointHeight)
        }

        nonisolated private static func wireMeshes(
            _ paths: [LabCablePacking.Path], traceID: String? = nil, sides: Int = 8
        ) -> [(AssemblyWireStyle, LabSceneMesh)] {
            var wires: [LabTopology.Medium: LabSceneMesh] = [:]
            var trace = LabSceneMesh()
            for path in paths {
                let medium = path.link.medium
                if (path.link.circuitID ?? path.link.id) == traceID { trace.cable(path.points, radius: medium.cableRadius * 1.07) }
                else { wires[medium, default: LabSceneMesh()].cable(path.points, radius: medium.cableRadius, sides: sides) }
            }
            return ([(AssemblyWireStyle.trace, trace)] + wires.map { (.wire($0.key), $0.value) })
                .filter { !$0.1.indices.isEmpty }
        }

        nonisolated private static func connectorMeshes(for terminations: [(LabTopology.Medium, [LabScenePort])])
            -> [(AssemblyWireStyle, LabSceneMesh)] {
            var plugs = LabSceneMesh(), rj45 = LabSceneMesh(), contacts = LabSceneMesh(), boots = LabSceneMesh()
            for (medium, endpoints) in terminations {
                for end in endpoints {
                    let yaw = atan2(end.normal.x, end.normal.z)
                    var pose = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
                    pose.columns.3 = SIMD4(end.point, 1)
                    if medium == .copper {
                        // The modular plug seats against the jack, with its latch and boot still exposed.
                        rj45.box(size: SIMD3(0.0117, 0.008, 0.015), center: SIMD3(0, 0, 0.006), matrix: pose)
                        rj45.box(size: SIMD3(0.0058, 0.0016, 0.011), center: SIMD3(0, -0.0048, 0.008), matrix: pose)
                        for pin in 0..<8 {
                            contacts.box(size: SIMD3(0.00056, 0.0004, 0.005), center: SIMD3((Float(pin) - 3.5) * 0.00102, 0.004, 0.003), matrix: pose)
                        }
                        boots.box(size: SIMD3(0.0108, 0.009, 0.006), center: SIMD3(0, 0, 0.016), matrix: pose)
                        for rib in 0..<3 {
                            let width = 0.0093 - Float(rib) * 0.001
                            boots.box(size: SIMD3(width, width, 0.0018), center: SIMD3(0, 0, 0.019 + Float(rib) * 0.002), matrix: pose)
                        }
                    } else {
                        let size: SIMD3<Float> = medium == .fiber ? [0.009, 0.008, 0.019] : [0.024, 0.010, 0.018]
                        plugs.box(size: size, center: SIMD3(0, 0, 0.008), matrix: pose)
                    }
                }
            }
            return [(AssemblyWireStyle.connector, plugs), (.copperPlug, rj45), (.copperContacts, contacts), (.boot, boots)]
                .filter { !$0.1.indices.isEmpty }
        }

        nonisolated private static func guideMeshes(
            _ channels: [LabCablePacking.Guide], anchors: [LabCablePacking.Anchor],
            terminations: [LabCablePacking.Termination], organizers: [LabCablePacking.Organizer],
            floor: Float, overhead: Float, ceiling: Float?
        ) -> [(AssemblyWireStyle, LabSceneMesh)] {
            var guides = LabSceneMesh(), warnings = LabSceneMesh(), outlets = LabSceneMesh()
            let fitted = LabCablePacking.connectGuides(channels)
            var supportLocations = Set<SIMD3<Int32>>()
            for elbow in fitted.elbows {
                if elbow.overCapacity { warnings.cableElbow(elbow) }
                else { guides.cableElbow(elbow) }
            }
            for junction in fitted.junctions {
                if junction.overCapacity { warnings.box(size: junction.size, center: junction.point) }
                else { guides.box(size: junction.size, center: junction.point) }
            }
            for channel in fitted.straights {
                if channel.overCapacity {
                    warnings.cableGuide(from: channel.start, to: channel.end, size: channel.size)
                } else {
                    guides.cableGuide(from: channel.start, to: channel.end, size: channel.size)
                }
                let span = channel.end - channel.start
                let length = simd_length(span)
                guard length > 0.12 else { continue }
                let count = max(1, Int(ceil(length / 1.25)))
                for index in 0..<count {
                    let point = channel.start + span * ((Float(index) + 0.5) / Float(count))
                    let key = SIMD3<Int32>((point * 20).rounded(.toNearestOrAwayFromZero))
                    guard supportLocations.insert(key).inserted else { continue }
                    let horizontal = abs(span.y) < 0.001
                    let onHighTray = horizontal && abs(point.y - overhead) < 0.004
                    if !onHighTray,
                       let face = anchors.compactMap({ $0.face(near: point) })
                        .min(by: { simd_distance_squared($0, point) < simd_distance_squared($1, point) }) {
                        if simd_distance_squared(face, point) > 0.000016 { guides.tube(from: face, to: point, radius: 0.008) }
                        continue
                    }
                    guard horizontal else { continue }
                    let contact = point.y + channel.size.y / 2 * (onHighTray ? 1 : -1)
                    let endpoint = LabCablePacking.supportAnchor(for: contact, onCeiling: onHighTray, floor: floor, ceiling: ceiling)
                    let height = abs(endpoint - contact)
                    guard height > 0.003, onHighTray || contact > floor else { continue }
                    let width: Float = onHighTray ? 0.012 : 0.018
                    guides.box(size: SIMD3(width, height, width),
                               center: SIMD3(point.x, (endpoint + contact) / 2, point.z))
                    guides.box(size: SIMD3(0.042, 0.006, 0.042),
                               center: SIMD3(point.x, endpoint + (onHighTray ? -0.003 : 0.003), point.z))
                }
            }
            func brace(_ point: SIMD3<Float>) {
                guard let face = anchors.compactMap({ $0.face(near: point) })
                        .min(by: { simd_distance_squared($0, point) < simd_distance_squared($1, point) }),
                      simd_distance_squared(face, point) > 0.000004 else { return }
                guides.tube(from: face, to: point, radius: 0.007)
            }
            for organizer in LabCablePacking.groupedOrganizers(organizers) {
                guides.rackOrganizer(organizer, mountings: &outlets)
            }
            for end in terminations {
                if let side = end.side {
                    var pose = simd_float4x4(simd_quatf(angle: end.yaw, axis: SIMD3(0, 1, 0)))
                    pose.columns.3 = SIMD4(end.point, 1)
                    // Open brush entry: the four lips frame the cable instead of covering it.
                    for edge: Float in [-1, 1] {
                        outlets.box(size: SIMD3(0.006, 0.018, 0.041), center: SIMD3(edge * 0.018, 0, 0), matrix: pose)
                        outlets.box(size: SIMD3(0.030, 0.018, 0.006), center: SIMD3(0, 0, edge * 0.018), matrix: pose)
                    }
                    let inward = -side.sign
                    outlets.box(size: SIMD3(0.039, 0.011, 0.027), center: SIMD3(inward * 0.032, -0.004, 0), matrix: pose)
                    for z: Float in [-0.007, 0.007] {
                        guides.box(size: SIMD3(0.006, 0.004, 0.006), center: SIMD3(inward * 0.043, 0.003, z), matrix: pose)
                    }
                    continue
                }
                let width = channels.filter {
                    min(simd_distance_squared(end.point, $0.start), simd_distance_squared(end.point, $0.end)) < 0.0025
                }.map(\.size.x).max() ?? 0.05
                let size = SIMD3<Float>(max(width + 0.014, 0.08), 0.055, 0.068)
                var pose = simd_float4x4(simd_quatf(angle: end.yaw, axis: SIMD3(0, 1, 0)))
                pose.columns.3 = SIMD4(end.point, 1)
                outlets.box(size: size, center: .zero, matrix: pose)
                guides.box(size: SIMD3(0.023, 0.015, 0.003), center: SIMD3(0, 0, size.z / 2 + 0.001), matrix: pose)
                brace(end.point)
            }
            return [(.guide, guides), (.capacity, warnings), (.termination, outlets)].filter { !$0.1.indices.isEmpty }
        }

        private func cableMaterial(_ style: AssemblyWireStyle) -> any RealityKit.Material {
            switch style {
            case .guide: materials.graphite
            case .termination: materials.panel
            case .wire(let medium): wireMaterial(medium)
            case .capacity: materials.activity
            case .trace: materials.trace
            case .connector: materials.connector
            case .copperPlug: materials.copperPlug
            case .copperContacts: materials.copperContacts
            case .boot: materials.graphite
            }
        }

        private static func assemblyMeshResource(_ batches: [LabSceneMesh]) async throws -> MeshResource? {
            guard !batches.isEmpty else { return nil }
            if #available(iOS 18, *) { return try await MeshResource(from: assemblyMeshDescriptors(batches)) }
            return try MeshResource.generate(from: assemblyMeshDescriptors(batches))
        }

        nonisolated private static func assemblyMeshDescriptors(_ batches: [LabSceneMesh]) -> sending [MeshDescriptor] {
            batches.enumerated().map { index, batch in
                batch.descriptor(name: "Cableado del montaje \(index)", materialIndex: UInt32(index))
            }
        }

        private func canPresentAssembly(_ assembly: LabARAssembly, editID: UUID?) -> Bool {
            guard parent.isForeground, parent.showCables, let current = parent.assembly,
                  current.id == assembly.id else { return false }
            return current.hasSameCableLayout(as: assembly) || (editID != nil && parent.assemblyEditID == editID)
        }

        private func showAssemblyCableGeometry(
            _ mesh: MeshResource?, styles: [AssemblyWireStyle], assembly: LabARAssembly, editID: UUID?,
            traceID: String?, topology: LabTopology, paths: [String: [SIMD3<Float>]], reviewCount: Int, waypointHeight: Float?
        ) throws {
            guard canPresentAssembly(assembly, editID: editID), traceID == parent.selectedLinkID, let content = scaledContent else { return }
            let palette: [any RealityKit.Material] = styles.map { cableMaterial($0) }
            let cables = mesh.map { ModelEntity(mesh: $0, materials: palette) }
            // Commit both in the same update so every patch cord stays on its connector.
            try presentAssembly(assembly, in: content)
            cablesEntity?.removeFromParent()
            if let cables {
                content.addChild(cables)
                makeTraffic(topology, paths: paths, cables: cables)
            } else {
                activeTraffic.removeAll(); trafficCircuits.removeAll(); pulsePairs.removeAll()
            }
            cablesEntity = cables
            wiredAssembly = assembly
            wiredAssemblyLinks = topology.links
            wiredTraceID = traceID
            trafficSettings = nil
            configureTraffic()
            updateWaypointHandles(for: traceID, height: waypointHeight, assembly: assembly, content: content)
            if let walkthrough = parent.walkthrough {
                if walkthrough.assemblyCableReviews != reviewCount { walkthrough.assemblyCableReviews = reviewCount }
            }
        }

        private func updateWaypointHandles(for linkID: String?, height: Float?, assembly: LabARAssembly, content: Entity) {
            let points = linkID.flatMap { assembly.waypoints?[$0] } ?? []
            if waypointHandleLinkID != linkID || waypointHandles.count != points.count || height == nil {
                waypointHandleRoot?.removeFromParent()
                waypointHandleRoot = nil
                waypointHandles.removeAll()
            }
            waypointHandleLinkID = linkID
            guard let height, !points.isEmpty else { return }
            if waypointHandleRoot == nil {
                let root = Entity()
                let mesh = MeshResource.generateSphere(radius: 0.047)
                for _ in points {
                    let handle = ModelEntity(mesh: mesh, materials: [materials.accent])
                    root.addChild(handle)
                    waypointHandles.append(handle)
                }
                content.addChild(root)
                waypointHandleRoot = root
            }
            waypointHandleRoot?.isEnabled = parent.assemblyWaypointsEditable
            for (index, point) in points.enumerated() {
                let position = SIMD3(point.x, height + 0.055, point.y)
                waypointHandles[index].position = waypointGrip?.index == index && waypointGrip?.linkID == linkID
                    ? (waypointGrip?.point ?? position) : position
            }
        }

        private func makeAssemblyMonitor(_ device: LabTopology.Device, panel: LabMonitorConfiguration.Panel,
                                         owner: LabARAssembly.Item, mount: LabARAssembly.MonitorMount?) -> Entity {
            let root = Entity()
            let size = LabARAssembly.monitorSize
            let screenSize = SIMD3<Float>(size.x, 0.35, 0.035)
            let center = SIMD3<Float>(0, size.y - screenSize.y / 2, 0)
            let enclosure = ModelEntity(mesh: .generateBox(size: screenSize, cornerRadius: 0.009), materials: [materials.graphite])
            enclosure.position = center
            root.addChild(enclosure)
            if let mount {
                let reach = size.x / 2 + 0.056
                let arm = ModelEntity(mesh: .generateBox(size: SIMD3(reach, 0.043, 0.045)), materials: [materials.metal])
                arm.position = center + SIMD3(-mount.side.sign * reach / 2, 0, 0.032)
                root.addChild(arm)
            } else {
                let stand = ModelEntity(mesh: .generateBox(size: SIMD3(0.055, 0.17, 0.04)), materials: [materials.graphite])
                stand.position.y = 0.085
                root.addChild(stand)
                root.addChild(ModelEntity(mesh: .generateBox(size: SIMD3(0.27, 0.024, 0.23)), materials: [materials.graphite]))
            }
            let face = ModelEntity(mesh: .generatePlane(width: 0.54, height: 0.32), materials: [materials.dark])
            face.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
            face.position = center - SIMD3(0, 0, 0.019)
            root.addChild(face)
            root.components.set(CollisionComponent(shapes: [.generateBox(size: screenSize).offsetBy(translation: center)]))
            dashboards.append(Dashboard(device: device, face: face, panel: panel, owner: owner))
            lastDashboardTick = nil
            return root
        }

        private func makeAssemblyAccessory(_ model: String, circuit: String = "A",
                                           pduConfiguration: LabRackPower.Configuration = .right,
                                           rackOwner: LabARAssembly.Item? = nil) throws -> Entity {
            guard let size = LabARAssembly.accessorySize(model) else {
                throw LabLayoutError.invalid("El modelo de la pieza ya no está disponible.")
            }
            let root = Entity()
            if model == "battery-bank" || model == "rack-r42612" || model == "test-desk" {
                let desk = model == "test-desk"
                let meshes = desk ? workstationMeshes(size, withDisplay: true) : rackMeshes(size)
                let surfaces: [any RealityKit.Material] = [materials.graphite, materials.panel, materials.metal,
                                                            materials.dark, materials.power, materials.screen]
                for (index, mesh) in meshes.enumerated() where !mesh.indices.isEmpty {
                    root.addChild(try mesh.model(material: surfaces[index]))
                }
                root.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: SIMD3(0, size.y / 2, 0))]))
                if model == "rack-r42612" {
                    root.addChild(try makeRackPower(size: size, configuration: pduConfiguration, devices: [], owner: rackOwner).0)
                }
                if model == "battery-bank" {
                    for (id, slot) in [("battery-9px", 2), ("battery-9px", 5), ("battery-9px", 8), ("ups-9px", 13), ("ups-9px", 17)] {
                        let unit = try makeFacilityEquipment(id, circuit: circuit)
                        unit.position = RackMount.center(id, rackDepth: size.z, slot: slot)
                        root.addChild(unit)
                    }
                }
            } else {
                let entity = if ["ups-9px", "battery-9px", "cooling-inrow"].contains(model) {
                    try makeFacilityEquipment(model, circuit: circuit)
                } else { try hardware(model) }
                entity.position.y = size.y / 2
                root.addChild(entity)
            }
            return root
        }

        private func updateARFocus() {
            let focus = parent.arFocus
            focusOrigin = focus.pivot(in: parent.layout, topology: parent.topology) ?? .zero
            let translation = -focusOrigin * parent.sceneScale
            if let scaledContent, scaledContent.position != translation { scaledContent.position = translation }
            let selectionOnly = focus != .all
            let placeID = focus.placementID(in: parent.topology)
            func present(_ entity: Entity?, featured: Bool, enabled: Bool = true) {
                guard let entity else { return }
                let visible = enabled && (featured || parent.showARContext)
                if entity.isEnabled != visible { entity.isEnabled = visible }
                if #available(iOS 18.0, *) {
                    let opacity = entity.components[OpacityComponent.self]?.opacity
                    if featured {
                        if opacity != nil { entity.components.remove(OpacityComponent.self) }
                    } else if opacity != 0.19 {
                        entity.components.set(OpacityComponent(opacity: 0.19))
                    }
                }
            }
            for (id, object) in placementModels {
                present(object, featured: !selectionOnly || id == placeID)
            }
            for (id, shell) in placementShells {
                present(shell, featured: !selectionOnly || id != placeID || focus == .placement(id))
            }
            for (id, object) in deviceModels {
                present(object, featured: !selectionOnly || devicePowerParents[id] != placeID
                        || focus == .device(id) || focus == .placement(devicePowerParents[id] ?? ""))
            }
            // Context can be hidden while cable topology and monitor activity remain live.
            present(facilityModel, featured: !selectionOnly)
            for (id, object) in facilityFixtures {
                present(object, featured: !selectionOnly || focus == .fixture(id))
            }
            present(roomEntity, featured: !selectionOnly, enabled: parent.paintRoom)
            present(cablesEntity, featured: !selectionOnly, enabled: parent.showCables)
            present(portLabelsEntity, featured: !selectionOnly, enabled: parent.showCables || parent.inspectionDestination?.port != nil)
        }

        private func updateTraceAndPortLabels() {
            guard let topology = parent.topology else { return }
            let picked = topology.links.first { $0.id == parent.selectedLinkID }
            let circuit = picked.map(topology.circuit(for:)) ?? []
            for trace in tracedCables { trace.removeFromParent() }
            tracedCables.removeAll()
            for body in linkBodies.values { body.isEnabled = true }
            if parent.isTierAR {
                tierTrace?.removeFromParent()
                tierTrace = nil
                var mesh = LabSceneMesh()
                for link in circuit {
                    if let points = pingPaths[link.id] { mesh.cable(points, radius: link.medium.cableRadius * 1.12) }
                }
                if !mesh.indices.isEmpty, let trace = try? mesh.model(material: materials.trace) {
                    cablesEntity?.addChild(trace)
                    tierTrace = trace
                }
            } else {
                for link in circuit {
                    guard let points = pingPaths[link.id], let picker = linkEntities[link.id] else { continue }
                    var mesh = LabSceneMesh()
                    mesh.cable(points, radius: link.medium.cableRadius * 1.07)
                    guard let trace = try? mesh.model(material: materials.trace) else { continue }
                    picker.addChild(trace)
                    tracedCables.append(trace)
                    linkBodies[link.id]?.isEnabled = false
                }
            }

            var endpoints: [(String, String)] = []
            if let first = circuit.first, let last = circuit.last {
                endpoints = [(first.fromDeviceID, first.fromPort), (last.toDeviceID, last.toPort)]
            }
            if let focus = parent.inspectionDestination, let port = focus.port,
               !endpoints.contains(where: { $0 == (focus.deviceID, port) }) {
                endpoints.append((focus.deviceID, port))
            }
            let labels = endpoints.compactMap { id, name in
                topology.devices.first(where: { $0.id == id }).flatMap { try? worldPort($0, name) }
            }
            showPortLabels(labels)
        }

        private func updatePingOverlay() {
            pingOverlay?.removeFromParent()
            pingOverlay = nil
            guard let cablesEntity, !parent.pingLinks.isEmpty || parent.pingBlockedLink != nil else { return }
            let overlay = Entity()
            let lift = SIMD3<Float>(0, 0.10, 0)
            var route = LabSceneMesh(), blocked = LabSceneMesh()
            for id in parent.pingLinks.sorted() {
                if let points = pingPaths[id] { route.cable(points.map { $0 + lift }, radius: 0.018) }
            }
            if let id = parent.pingBlockedLink, let points = pingPaths[id] {
                blocked.cable(points.map { $0 + lift }, radius: 0.021)
            }
            for (mesh, material) in [(route, materials.accent), (blocked, materials.blockedTrace)] where !mesh.indices.isEmpty {
                if let line = try? mesh.model(material: material) { overlay.addChild(line) }
            }
            cablesEntity.addChild(overlay)
            pingOverlay = overlay
        }

        private struct PacketLeg {
            let route: LabTrafficRoute?
            let dies: Bool
            /// Text of the floating label shown when the packet reaches the end of this leg; nil for patch panels.
            let label: String?
            let role: PacketLabelRole
        }

        private enum PacketPhase { case outbound, reply, failed }
        private enum PacketLabelRole { case source, stop, destination, failure }

        private static let trailLength = 14

        /// Animates one visible packet along the ping route, hop by hop, then its reply back to the source.
        /// A fading trail follows the packet and a floating label names each device it reaches.
        private func updatePacketJourney() {
            packetTask?.cancel()
            packetTask = nil
            packetEntity?.removeFromParent()
            packetEntity = nil; packetCore = nil; packetHalo = nil
            packetTrail.forEach { $0.removeFromParent() }
            packetTrail.removeAll(); packetTrailHistory.removeAll()
            clearPacketLabels()
            guard let journey = parent.packetJourney, let cablesEntity else { return }
            // Ride on top of the ping overlay, which is lifted by the same amount.
            let lift = SIMD3<Float>(0, 0.10, 0)
            let conceals = parent.packetConcealsFailure
            var stop = 0
            let legs = journey.hops.enumerated().map { index, hop -> PacketLeg in
                let points = pingPaths[hop.linkID].map { path in (hop.reversed ? Array(path.reversed()) : path).map { $0 + lift } }
                let last = index == journey.hops.count - 1
                let role: PacketLabelRole = hop.dies ? .failure : (last && !journey.blocked ? .destination : .stop)
                var label: String?
                if hop.dies {
                    label = conceals ? "✕ ¿Qué falló aquí?" : "✕ " + hop.deviceName
                } else if !hop.passive {
                    stop += 1
                    label = role == .destination ? "Destino · " + hop.deviceName : "\(stop) · " + hop.deviceName
                }
                return PacketLeg(route: points.flatMap { LabTrafficRoute([$0]) }, dies: hop.dies, label: label, role: role)
            }
            guard let start = legs.compactMap(\.route).first?.point(at: 0) else { return }

            let core = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [packetMaterial(.outbound)])
            let halo = ModelEntity(mesh: .generateSphere(radius: 0.11), materials: [packetMaterial(.outbound, opacity: 0.28)])
            let packet = Entity()
            packet.name = "nexus-packet"
            packet.addChild(halo)
            packet.addChild(core)
            packet.position = start
            cablesEntity.addChild(packet)
            packetEntity = packet; packetCore = core; packetHalo = halo

            if parent.reduceMotion {
                // Without motion, show the whole route labelled and the packet where it ends.
                showPacketLabel("Origen · " + journey.sourceName, role: .source, at: start, index: 0, animated: false)
                for (index, leg) in legs.enumerated() {
                    guard let route = leg.route else { continue }
                    if let label = leg.label { showPacketLabel(label, role: leg.role, at: route.point(at: leg.dies ? 0.5 : 1), index: index + 1, animated: false) }
                }
                if let last = legs.last(where: { $0.route != nil }), let route = last.route {
                    packet.position = route.point(at: last.dies ? 0.5 : 1)
                    if last.dies { paintPacket(.failed) }
                }
                notifyPacketHop(journey.hops.count)
                return
            }

            for index in 0..<Self.trailLength {
                let fraction = 1 - Float(index) / Float(Self.trailLength)
                let dot = ModelEntity(mesh: .generateSphere(radius: 0.012 + 0.036 * fraction), materials: [])
                dot.position = start
                cablesEntity.addChild(dot)
                packetTrail.append(dot)
            }
            paintPacket(.outbound)
            let blocked = journey.blocked
            let source = journey.sourceName
            packetTask = Task { @MainActor [weak self] in
                await self?.runPacket(legs, source: source, blocked: blocked)
            }
        }

        private func packetColor(_ phase: PacketPhase) -> UIColor {
            switch phase {
            case .outbound: UIColor(red: 0.18, green: 0.72, blue: 1, alpha: 1)
            case .reply: UIColor(red: 0.2, green: 0.92, blue: 0.45, alpha: 1)
            case .failed: .systemRed
            }
        }

        private func packetMaterial(_ phase: PacketPhase, opacity: Float = 1) -> UnlitMaterial {
            var material = UnlitMaterial()
            material.color = .init(tint: packetColor(phase))
            if opacity < 1 { material.blending = .transparent(opacity: .init(scale: opacity)) }
            return material
        }

        private func paintPacket(_ phase: PacketPhase) {
            packetCore?.model?.materials = [packetMaterial(phase)]
            packetHalo?.model?.materials = [packetMaterial(phase, opacity: 0.28)]
            for (index, dot) in packetTrail.enumerated() {
                let fraction = 1 - Float(index) / Float(Self.trailLength)
                dot.model?.materials = [packetMaterial(phase, opacity: 0.08 + 0.55 * fraction * fraction)]
            }
        }

        /// Moves the packet and lets the trail follow the positions it just left.
        private func placePacket(at position: SIMD3<Float>) {
            packetEntity?.position = position
            guard !packetTrail.isEmpty else { return }
            packetTrailHistory.insert(position, at: 0)
            let spacing = 2
            if packetTrailHistory.count > packetTrail.count * spacing + 1 { packetTrailHistory.removeLast() }
            for (index, dot) in packetTrail.enumerated() {
                let sample = min((index + 1) * spacing, packetTrailHistory.count - 1)
                dot.position = packetTrailHistory[sample]
            }
        }

        private func resetTrail(at position: SIMD3<Float>) {
            packetTrailHistory = [position]
            packetTrail.forEach { $0.position = position }
        }

        private func clearPacketLabels() {
            packetLabels.forEach { $0.removeFromParent() }
            packetLabels.removeAll()
        }

        /// A rounded label that floats over a device, joined to it by a thin line, and always faces the viewer.
        private func showPacketLabel(_ text: String, role: PacketLabelRole, at point: SIMD3<Float>, index: Int,
                                     animated: Bool = true) {
            guard let cablesEntity, let material = packetLabelMaterial(text, role: role) else { return }
            let height: Float = 0.15
            let aspect = Float(material.color.texture.map { $0.resource.width } ?? 4) /
                Float(material.color.texture.map { $0.resource.height } ?? 1)
            // Alternate heights so labels of neighbouring devices in a rack do not overlap.
            let rise: Float = index.isMultiple(of: 2) ? 0.34 : 0.56
            let group = Entity()
            group.name = "nexus-packet-label"
            group.position = point
            var stemMaterial = UnlitMaterial()
            stemMaterial.color = .init(tint: labelTint(role).withAlphaComponent(1))
            let stem = ModelEntity(mesh: .generateBox(width: 0.008, height: rise, depth: 0.008), materials: [stemMaterial])
            stem.position = SIMD3(0, rise / 2, 0)
            let plate = ModelEntity(mesh: .generatePlane(width: height * aspect, height: height), materials: [material])
            plate.position = SIMD3(0, rise + height / 2, 0)
            if #available(iOS 18.0, *) { plate.components.set(BillboardComponent()) }
            group.addChild(stem)
            group.addChild(plate)
            cablesEntity.addChild(group)
            packetLabels.append(group)
            if animated {
                group.scale = SIMD3(repeating: 0.2)
                var target = group.transform
                target.scale = .one
                group.move(to: target, relativeTo: group.parent, duration: 0.22, timingFunction: .easeOut)
            }
        }

        private func labelTint(_ role: PacketLabelRole) -> UIColor {
            switch role {
            case .source: UIColor(white: 0.18, alpha: 0.92)
            case .stop: UIColor(red: 0.05, green: 0.42, blue: 0.85, alpha: 0.92)
            case .destination: UIColor(red: 0.1, green: 0.62, blue: 0.3, alpha: 0.95)
            case .failure: UIColor(red: 0.82, green: 0.12, blue: 0.12, alpha: 0.95)
            }
        }

        private func packetLabelMaterial(_ text: String, role: PacketLabelRole) -> UnlitMaterial? {
            let key = "\(role)|\(text)"
            if let cached = packetLabelMaterials[key] { return cached }
            let font = UIFont.systemFont(ofSize: 56, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
            let size = CGSize(width: min(1400, textWidth + 64), height: 96)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                labelTint(role).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).fill()
                (text as NSString).draw(at: CGPoint(x: 32, y: (size.height - font.lineHeight) / 2), withAttributes: attributes)
            }
            guard let cgImage = image.cgImage,
                  let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) else { return nil }
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(scale: 1))
            packetLabelMaterials[key] = material
            return material
        }

        private func notifyPacketHop(_ value: Int) {
            guard parent.onPacketHop != nil else { return }
            Task { @MainActor [weak self] in self?.parent.onPacketHop?(value) }
        }

        /// Moves the packet along one leg. Returns false when the animation was cancelled.
        private func travel(_ route: LabTrafficRoute, from start: Float, to end: Float, speed: Float) async -> Bool {
            let duration = max(0.45, Double(route.length * abs(end - start) / speed))
            let began = ProcessInfo.processInfo.systemUptime
            while true {
                let t = Float(min(1, (ProcessInfo.processInfo.systemUptime - began) / duration))
                // Ease in and out so each hop reads as a separate step.
                let eased = t * t * (3 - 2 * t)
                placePacket(at: route.point(at: start + (end - start) * eased))
                if t >= 1 { return true }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return false }
            }
        }

        /// Briefly enlarges the packet when it reaches a device while the trail catches up.
        private func pop(times: Int = 1, duration: Double = 0.24) async -> Bool {
            for _ in 0..<times {
                let began = ProcessInfo.processInfo.systemUptime
                while true {
                    let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / duration)
                    let bump = Float(sin(t * .pi)) * 0.6
                    packetEntity?.scale = SIMD3(repeating: 1 + bump)
                    if let position = packetEntity?.position { placePacket(at: position) }
                    if t >= 1 { break }
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return false }
                }
            }
            packetEntity?.scale = .one
            return true
        }

        private func runPacket(_ legs: [PacketLeg], source: String, blocked: Bool) async {
            let speed: Float = 1.4
            while !Task.isCancelled {
                clearPacketLabels()
                paintPacket(.outbound)
                guard let first = legs.compactMap(\.route).first else { return }
                let start = first.point(at: 0)
                packetEntity?.position = start
                resetTrail(at: start)
                showPacketLabel("Origen · " + source, role: .source, at: start, index: 0)
                notifyPacketHop(0)
                guard await pop() else { return }
                for (index, leg) in legs.enumerated() {
                    if let route = leg.route {
                        guard await travel(route, from: 0, to: leg.dies ? 0.5 : 1, speed: speed) else { return }
                        if let label = leg.label {
                            showPacketLabel(label, role: leg.role, at: route.point(at: leg.dies ? 0.5 : 1), index: index + 1)
                        }
                    }
                    notifyPacketHop(index + 1)
                    if leg.dies {
                        paintPacket(.failed)
                        guard await pop(times: 3, duration: 0.32) else { return }
                        break
                    }
                    guard await pop() else { return }
                }
                if !blocked {
                    // The echo reply returns along the same route.
                    paintPacket(.reply)
                    notifyPacketHop(legs.count + 1)
                    for leg in legs.reversed() {
                        guard let route = leg.route else { continue }
                        guard await travel(route, from: 1, to: 0, speed: speed * 1.6) else { return }
                    }
                    guard await pop() else { return }
                }
                // Leave the labelled route on screen for a moment before the next packet.
                do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
            }
        }

        private func focusOrbit(on destination: LabInspectionDestination, in topology: LabTopology) {
            let observer = camera?.position ?? LabWalkPose.start(in: parent.layout).position
            guard let spot = destination.spot(in: topology, layout: parent.layout, observer: observer) else { return }
            let initial = LabWalkPose(position: observer, yaw: 0)
            let rackTarget = destination.port == nil ? LabFocusTarget.inventory(topology, in: parent.layout)
                .first(where: { $0.id == destination.deviceID }) : nil
            let framing = rackTarget.map { initial.framing($0, in: parent.layout) }
                ?? initial.inspecting(spot.point, fromSide: spot.normal, in: parent.layout)
            let distance = simd_distance(spot.point, framing.position)
            cameraTarget = framing.position + framing.rotation.act(SIMD3(0, 0, -distance))
            let offset = framing.position - cameraTarget
            cameraRadius = max(0.35, simd_length(offset))
            cameraYaw = atan2(offset.x, -offset.z)
            cameraPitch = atan2(offset.y, simd_length(SIMD2(offset.x, offset.z)))
            cameraMoved = true
            updateCamera()
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            guard parent.mode == .room || tracking else { return }
            guard parent.placementPreview == nil else { return }
            let point = recognizer.location(in: view)
            if let surface = parent.equipmentSurface {
                parent.onEquipmentTarget(equipmentTarget(surface, at: point, in: view))
                return
            }
            if parent.selectableScenePorts != nil || parent.assemblyPortSource != nil {
                if !parent.assemblyPortsEnabled { return }
                if let port = assemblyPort(at: point, in: view) {
                    parent.onAssemblyPort(port)
                    return
                }
                if case .device(let id) = target(at: point, preferPortDevice: true)?.item {
                    parent.onAssemblySelect(.device(id))
                    return
                }
                return
            }
            if let port = assemblyPort(at: point, in: view) {
                if let _ = parent.topology?.link(at: port) {
                    if parent.assemblyEditID == nil, parent.assemblyRackID == nil, let inspect = parent.onInspectPort {
                        inspect(port)
                        return
                    }
                } else if parent.assemblyPortsEnabled {
                    parent.onAssemblyPort(port)
                    return
                }
            }
            if let rack = parent.powerOutletRack {
                guard !awaitingPlacement, parent.walkthrough?.ready == true else { return }
                parent.onPowerOutlet(rack, wallOutlet(at: point, in: view))
                return
            }
            if let assembly = parent.assembly {
                if parent.assemblyPlacementRequested {
                    confirmARPreview()
                    return
                }
                if parent.assemblyPortsEnabled, let port = assemblyPort(at: point, in: view) {
                    parent.onAssemblyPort(port)
                    return
                }
                if parent.assemblyEditID == nil, parent.assemblyRackID == nil,
                   let inspect = parent.onInspectPort, let port = assemblyPort(at: point, in: view) {
                    inspect(port)
                    return
                }
                if parent.assemblyEditID == nil, parent.assemblyRackID == nil, inspectPDU(at: point, in: view) { return }
                let item = assemblyItem(at: point, in: view, assembly: assembly)
                if case .device = item, let item { parent.onAssemblySelect(item) }
                else if let rackID = parent.assemblyRackID, let target = rackTarget(at: point, rackID: rackID, in: view) {
                    parent.onAssemblyRackTarget(rackID, target)
                } else if let item {
                    parent.onAssemblySelect(item)
                }
                return
            }
            if awaitingPlacement {
                confirmARPreview()
                return
            }
            if let inspect = parent.onInspectPort, let port = assemblyPort(at: point, in: view) {
                inspect(port)
                return
            }
            if inspectPDU(at: point, in: view) { return }
            let target = target(at: point, preferPortDevice: true)
            if let peerSession = parent.peerSession {
                var targetID: String? = nil
                switch target?.item {
                case .device(let id), .hardware(let id), .placement(let id), .link(let id):
                    targetID = id
                case nil: break
                }
                if let targetID, peerSession.isLockedByPeer(targetID) {
                    let holder = peerSession.lockHolder(for: targetID) ?? "el otro usuario"
                    peerSession.lastActionAlert = "⚠️ Elemento en uso por \(holder)."
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                    return
                }
            }
            parent.selection = nil
            if selectedHardwareHighlight !== highlightedDevice { selectedHardwareHighlight?.isEnabled = false }
            if let highlight = target?.highlight {
                selectedHardwareHighlight = highlight
                highlight.isEnabled = true
            }
            switch target?.item {
            case .link(let id): parent.onSelectLink(id)
            case .device(let id): parent.onSelectDevice(id)
            case .hardware(let id): parent.onSelectHardware(id)
            case .placement(let id): parent.selection = parent.layout.placements.first { $0.id == id }
            case nil:
                if parent.isTierMiniature, let id = miniatureCable(at: point, in: view) { parent.onSelectLink(id) }
            }
            updateState()
        }

        private func wallOutlet(at point: CGPoint, in view: ARView) -> LabRackPower.Outlet? {
            guard let frame = view.session.currentFrame, case .normal = frame.camera.trackingState,
                  let content = scaledContent else { return nil }
            guard let hit = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .vertical).first,
                  let plane = hit.anchor as? ARPlaneAnchor,
                  plane.classification != .door, plane.classification != .window else { return nil }
            let h = hit.worldTransform.columns.3, n = plane.transform.columns.1, c = frame.camera.transform.columns.3
            let world = SIMD3(h.x, h.y, h.z)
            let towardsCamera = SIMD3(c.x - h.x, c.y - h.y, c.z - h.z)
            let normal = SIMD3(n.x, 0, n.z)
            let direction = content.convert(direction: simd_dot(normal, towardsCamera) >= 0 ? normal : -normal, from: nil)
            guard simd_length_squared(direction) > 0.1 else { return nil }
            return .init(position: content.convert(position: world, from: nil), normal: simd_normalize(direction))
        }

        private func miniatureCable(at point: CGPoint, in view: ARView) -> String? {
            guard parent.showCables, let cablesEntity, cablesEntity.isEnabledInHierarchy else { return nil }
            let model = cablesEntity.transformMatrix(relativeTo: nil)
            let camera = view.cameraTransform
            let forward = camera.rotation.act(SIMD3<Float>(0, 0, -1))
            let touch = SIMD2(Float(point.x), Float(point.y))
            var closest: String?
            var limit: Float = 8 * 8
            for id in pingPaths.keys.sorted() {
                guard let path = pingPaths[id] else { continue }
                var previous: SIMD2<Float>?
                for (index, point) in path.enumerated()
                    where index.isMultiple(of: 3) || index == path.count - 1 {
                    let p = model * SIMD4(point, 1)
                    let world = SIMD3(p.x, p.y, p.z)
                    guard simd_dot(world - camera.translation, forward) > 0,
                          let projected = view.project(world) else { previous = nil; continue }
                    let end = SIMD2(Float(projected.x), Float(projected.y))
                    if let start = previous {
                        let segment = end - start
                        let progress = simd_clamp(simd_dot(touch - start, segment) / max(simd_length_squared(segment), 0.001), 0, 1)
                        let distance = simd_distance_squared(touch, start + segment * progress)
                        if distance < limit { limit = distance; closest = id }
                    }
                    previous = end
                }
            }
            return closest
        }

        private func rackTarget(at point: CGPoint, rackID: String, in view: ARView) -> RackMount.Target? {
            guard let ray = view.ray(through: point), let model = placementModels[rackID], model.isEnabledInHierarchy,
                  let rack = parent.layout.placements.first(where: { $0.id == rackID }) else { return nil }
            return RackMount.target(origin: model.convert(position: ray.origin, from: nil),
                                    direction: model.convert(direction: ray.direction, from: nil), size: rack.size)
        }

        private func assemblyPort(at point: CGPoint, in view: ARView) -> LabTopology.Port? {
            var object = view.entity(at: point)
            while let entity = object {
                if let port = portHits[ObjectIdentifier(entity)] {
                    return .init(deviceID: port.deviceID, name: port.name)
                }
                object = entity.parent
            }
            return nil
        }

        private func inspectPDU(at point: CGPoint, in view: ARView) -> Bool {
            guard let inspect = parent.onInspectPDU, let panel = view.entity(at: point),
                  let hit = pduHits[ObjectIdentifier(panel)], let ray = view.ray(through: point) else { return false }
            let origin = panel.convert(position: ray.origin, from: nil)
            let direction = panel.convert(direction: ray.direction, from: nil)
            var outlet: Int?
            if abs(direction.z) > 0.0001 {
                let y = origin.y - direction.y * origin.z / direction.z
                outlet = hit.heights.indices.min { abs(hit.heights[$0] - y) < abs(hit.heights[$1] - y) }
                    .flatMap { abs(hit.heights[$0] - y) < 0.016 ? $0 : nil }
            }
            inspect(hit.rack, hit.circuit, outlet)
            return true
        }

        private func equipmentTarget(_ surface: LabEquipmentSurface, at point: CGPoint, in view: ARView) -> LabEquipmentTarget? {
            if surface == .floor {
                if parent.assembly != nil {
                    guard let content = scaledContent,
                          let hit = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first(where: {
                              ($0.anchor as? ARPlaneAnchor)?.classification == .floor
                          }) else { return nil }
                    let position = hit.worldTransform.columns.3
                    return .floor(content.convert(position: SIMD3(position.x, position.y, position.z), from: nil))
                }
                return waypointHit(point, height: parent.layout.floorHeight, in: view).map(LabEquipmentTarget.floor)
            }
            guard let ray = view.ray(through: point) else { return nil }
            var nearest: (id: String, point: SIMD2<Float>, distance: Float)?
            for desk in parent.layout.placements where desk.kind == .workstation {
                guard let model = placementModels[desk.id], model.isEnabledInHierarchy,
                      let hit = LabARAssembly.waypointPlaneHit(origin: model.convert(position: ray.origin, from: nil),
                          direction: model.convert(direction: ray.direction, from: nil), height: 0.75),
                      abs(hit.x) <= desk.size.x / 2, abs(hit.z) <= desk.size.z / 2 else { continue }
                let distance = simd_distance_squared(ray.origin, model.convert(position: hit, to: nil))
                if distance < (nearest?.distance ?? .infinity) { nearest = (desk.id, SIMD2(hit.x, hit.z), distance) }
            }
            guard let nearest else { return nil }
            return .desk(nearest.id, nearest.point)
        }

        private func waypointIndex(at point: CGPoint, in view: ARView) -> Int? {
            guard parent.assemblyWaypointsEditable, waypointHandleRoot?.isEnabledInHierarchy == true,
                  waypointHandleLinkID == parent.selectedLinkID, parent.isForeground else { return nil }
            let distances = waypointHandles.enumerated().compactMap { index, handle -> (Int, CGFloat)? in
                guard let projected = view.project(handle.position(relativeTo: nil)) else { return nil }
                let distance = hypot(projected.x - point.x, projected.y - point.y)
                return distance <= 27 ? (index, distance) : nil
            }
            return distances.min { $0.1 < $1.1 }?.0
        }

        private func waypointHit(_ point: CGPoint, height: Float, in view: ARView) -> SIMD3<Float>? {
            guard let content = scaledContent, let ray = view.ray(through: point) else { return nil }
            let origin = content.convert(position: ray.origin, from: nil)
            let direction = content.convert(direction: ray.direction, from: nil)
            return LabARAssembly.waypointPlaneHit(origin: origin, direction: direction, height: height)
        }

        @objc private func dragWaypoint(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began:
                let delta = gesture.translation(in: view)
                let start = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
                guard let index = waypointIndex(at: start, in: view), let id = waypointHandleLinkID else { return }
                let position = waypointHandles[index].position
                guard let hit = waypointHit(start, height: position.y, in: view) else { return }
                waypointGrip = WaypointGrip(index: index, linkID: id, height: position.y, offset: position - hit, point: position)
                _ = parent.onAssemblyWaypoint(.began(index))
                moveWaypoint(to: point, in: view)
            case .changed: moveWaypoint(to: point, in: view)
            case .ended:
                guard let grip = waypointGrip else { return }
                moveWaypoint(to: point, in: view)
                waypointGrip = nil
                settleWaypoint(grip, at: parent.onAssemblyWaypoint(.finished))
            case .cancelled, .failed:
                guard let grip = waypointGrip else { return }
                waypointGrip = nil
                settleWaypoint(grip, at: parent.onAssemblyWaypoint(.cancelled))
            default: break
            }
        }

        private func moveWaypoint(to point: CGPoint, in view: ARView) {
            guard var grip = waypointGrip, grip.linkID == waypointHandleLinkID,
                  waypointHandles.indices.contains(grip.index),
                  let hit = waypointHit(point, height: grip.height, in: view) else { return }
            grip.point = hit + grip.offset
            waypointGrip = grip
            waypointHandles[grip.index].position = grip.point
            _ = parent.onAssemblyWaypoint(.moved(grip.point))
        }

        private func settleWaypoint(_ grip: WaypointGrip, at point: SIMD2<Float>?) {
            guard let point, waypointHandles.indices.contains(grip.index) else { return }
            waypointHandles[grip.index].position = SIMD3(point.x, grip.height, point.y)
        }

        private func updateARPreview(_ frame: ARFrame, in view: ARView) {
            let isAssembly = parent.assembly != nil
            let requesting = isAssembly ? parent.assemblyPlacementRequested : awaitingPlacement
            guard requesting, !(awaitingPlacement && parent.restoresWorldPlacement),
                  let footprint = parent.arFootprint, footprint.points.count >= 3, !view.bounds.isEmpty else {
                clearARPreview()
                return
            }
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let camera = frame.camera.transform.columns.3
            let measured = view.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal).first {
                guard let surface = $0.anchor as? ARPlaneAnchor else { return false }
                guard $0.worldTransform.columns.3.y < camera.y else { return false }
                if footprint.rack != nil || footprint.requiresFloor { return surface.classification == .floor }
                switch surface.classification {
                case .ceiling, .wall, .window, .door: return false
                case .table, .seat: return !parent.arPlacementOnFloor
                default: return true
                }
            }
            let estimate = parent.arPlacementOnFloor || measured != nil ? nil :
                view.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first {
                    $0.worldTransform.columns.3.y < camera.y
                }
            guard let result = measured ?? estimate else { clearARPreview(); return }

            var transform = result.worldTransform
            if isAssembly || parent.worldPlacementName != nil {
                let point = transform.columns.3
                let yaw = atan2(point.x - camera.x, point.z - camera.z)
                transform = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
                transform.columns.3 = point
            }
            if previewFootprint != footprint || previewAnchor == nil {
                if let previewAnchor { view.scene.removeAnchor(previewAnchor) }
                let anchor = AnchorEntity(world: .zero)
                let mesh = previewOutline(footprint.points)
                guard !mesh.indices.isEmpty, let outline = try? mesh.model(material: materials.accent) else {
                    previewAnchor = nil
                    clearARPreview()
                    return
                }
                anchor.addChild(outline)
                if let rack = footprint.rack {
                    let access = previewOutline(LabPlacementFootprint(size: rack.accessSize).points, dashed: true)
                    if let outline = try? access.model(material: rackAccessUnknown) { anchor.addChild(outline) }
                }
                view.scene.addAnchor(anchor)
                previewAnchor = anchor
                previewFootprint = footprint
                previewBlocked = false
                previewRackFit = nil
            }
            var outlineTransform = transform
            if let yaw = footprint.yaw, let rootAnchor, !awaitingPlacement {
                outlineTransform = rootAnchor.transform.matrix * simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
                outlineTransform.columns.3 = transform.columns.3
            } else if let yaw = footprint.yaw, footprint.rack != nil, !isAssembly {
                outlineTransform = transform * simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
            }
            previewAnchor?.transform = Transform(matrix: outlineTransform)
            previewAnchor?.isEnabled = true
            var blocked = false
            if isAssembly, !awaitingPlacement, let rootAnchor {
                let hit = transform.columns.3, forward = transform.columns.2
                let position = rootAnchor.convert(position: SIMD3(hit.x, hit.y, hit.z), from: nil)
                let direction = rootAnchor.convert(direction: SIMD3(forward.x, forward.y, forward.z), from: nil)
                blocked = !parent.onAssemblyCanPlace(position, atan2(direction.x, direction.z))
            }
            let fit = footprint.rack.flatMap { rack -> LabRackClearance.Fit? in
                if blocked { return .occupied }
                guard let floor = result.anchor as? ARPlaneAnchor else { return .needsFloor }
                return rackFit(rack, on: floor, at: outlineTransform, anchors: frame.anchors)
            }
            blocked = fit.map { !$0.canPlace } ?? blocked
            if let walkthrough = parent.walkthrough {
                if walkthrough.rackFit != fit { walkthrough.rackFit = fit }
                if blocked, fit == nil, walkthrough.placementHint != LabARAssembly.collisionHint {
                    walkthrough.placementHint = LabARAssembly.collisionHint
                } else if (!blocked || fit != nil), walkthrough.placementHint == LabARAssembly.collisionHint {
                    walkthrough.placementHint = nil
                }
                if walkthrough.placementAvailable == blocked { walkthrough.placementAvailable = !blocked }
            }
            if previewBlocked != blocked || previewRackFit != fit {
                let bodyMaterial = fit == .needsFloor ? rackAccessUnknown : blocked ? materials.blockedTrace : materials.accent
                let accessMaterial = fit == .clear ? materials.accent : fit == .accessLimited || fit == .blocked || fit == .occupied
                    ? materials.blockedTrace : rackAccessUnknown
                for (child, material) in zip(previewAnchor?.children.map { $0 } ?? [], [bodyMaterial, accessMaterial]) {
                    (child as? ModelEntity)?.model?.materials = [material]
                }
            }
            previewBlocked = blocked
            previewRackFit = fit
            previewTransform = blocked ? nil : transform
        }

        private func clearARPreview() {
            previewTransform = nil
            previewAnchor?.isEnabled = false
            if parent.walkthrough?.rackFit != nil { parent.walkthrough?.rackFit = nil }
            if previewBlocked {
                previewBlocked = false
                if parent.walkthrough?.placementHint == LabARAssembly.collisionHint { parent.walkthrough?.placementHint = nil }
                if let outline = previewAnchor?.children.first as? ModelEntity { outline.model?.materials = [materials.accent] }
            }
            previewRackFit = nil
            if parent.walkthrough?.placementAvailable == true { parent.walkthrough?.placementAvailable = false }
        }

        private func confirmARPreview() {
            guard tracking, parent.isForeground, !(awaitingPlacement && parent.restoresWorldPlacement),
                  let view, let root = rootAnchor, parent.arFootprint == previewFootprint,
                  let frame = view.session.currentFrame, case .normal = frame.camera.trackingState else { return }
            let isAssembly = parent.assembly != nil
            guard isAssembly ? parent.assemblyPlacementRequested : awaitingPlacement else { return }
            if parent.arFootprint?.rack != nil { updateARPreview(frame, in: view) }
            guard let transform = previewTransform else { return }
            if awaitingPlacement {
                if let name = parent.worldPlacementName {
                    let anchor = ARAnchor(name: name, transform: transform)
                    view.session.add(anchor: anchor)
                    applyWorldPlacement(anchor)
                } else {
                    root.transform = Transform(matrix: transform)
                    confirmPlacement()
                }
                root.isEnabled = true
                transition(.ready)
            }
            guard isAssembly else { return }
            let hit = transform.columns.3
            let forward = transform.columns.2
            let position = root.convert(position: SIMD3(hit.x, hit.y, hit.z), from: nil)
            let direction = root.convert(direction: SIMD3(forward.x, forward.y, forward.z), from: nil)
            parent.walkthrough?.placementHint = nil
            parent.onAssemblyPosition(position, atan2(direction.x, direction.z))
        }

        private let rackAccessUnknown = UnlitMaterial(color: .systemOrange)

        private func previewOutline(_ points: [SIMD2<Float>], dashed: Bool = false) -> LabSceneMesh {
            var mesh = LabSceneMesh()
            for (start, end) in zip(points, points.dropFirst() + points.prefix(1)) {
                let length = simd_distance(start, end)
                guard length > 0.001 else { continue }
                let count = dashed ? max(1, Int(length / 0.13)) : 1
                for index in 0..<count {
                    let a = simd_mix(start, end, SIMD2(repeating: Float(index) / Float(count)))
                    let b = simd_mix(start, end, SIMD2(repeating: (Float(index) + (dashed ? 0.56 : 1)) / Float(count)))
                    mesh.tube(from: SIMD3(a.x, 0.018, a.y), to: SIMD3(b.x, 0.018, b.y), radius: dashed ? 0.004 : 0.006)
                }
            }
            return mesh
        }

        private func rackFit(_ rack: LabRackClearance, on floor: ARPlaneAnchor, at pose: simd_float4x4,
                             anchors: [ARAnchor]) -> LabRackClearance.Fit {
            let inverse = simd_inverse(pose)
            func boundary(of plane: ARPlaneAnchor) -> [SIMD3<Float>] {
                let local = inverse * plane.transform
                return plane.geometry.boundaryVertices.map { point in
                    let vertex = local * SIMD4(point, 1)
                    return SIMD3(vertex.x, vertex.y, vertex.z)
                }
            }
            let floorOutline = boundary(of: floor).map { SIMD2($0.x, $0.z) }
            let obstacles = anchors.compactMap { anchor -> [SIMD3<Float>]? in
                guard let plane = anchor as? ARPlaneAnchor, plane.identifier != floor.identifier else { return nil }
                return boundary(of: plane)
            }
            return rack.fit(floor: floorOutline, obstacles: obstacles)
        }

        private func assemblyItem(at point: CGPoint, in view: ARView, assembly: LabARAssembly) -> LabARAssembly.Item? {
            var hit = view.entity(at: point)
            while let object = hit {
                let name = object.name
                if name.hasPrefix("device:") {
                    let item = LabARAssembly.Item.device(String(name.dropFirst("device:".count)))
                    return item
                } else if name.hasPrefix("placement:") {
                    let item = LabARAssembly.Item.support(String(name.dropFirst("placement:".count)))
                    if assembly.piece(item) != nil { return item }
                } else if name.hasPrefix("assembly:") {
                    return assemblyAccessories.first { $0.value === object }?.key
                }
                hit = object.parent
            }
            return nil
        }

        private func target(at point: CGPoint, preferPortDevice: Bool = false) -> (item: LabSceneTarget, highlight: Entity?, deviceID: String?)? {
            var entity = view?.entity(at: point)
            while let current = entity {
                if let port = portHits[ObjectIdentifier(current)] {
                    if !preferPortDevice, parent.showCables, let link = parent.topology?.links.first(where: {
                        ($0.fromDeviceID == port.deviceID && $0.fromPort == port.name)
                            || ($0.toDeviceID == port.deviceID && $0.toPort == port.name)
                    }) { return (.link(link.id), nil, port.deviceID) }
                    return (.device(port.deviceID), nil, port.deviceID)
                }
                if current.name.hasPrefix("cable:") {
                    let id = String(current.name.dropFirst("cable:".count))
                    guard parent.visibleCableIDs?.contains(id) ?? true else { return nil }
                    return (.link(id), nil, nil)
                }
                if current.name.hasPrefix("device:") {
                    let id = String(current.name.dropFirst("device:".count))
                    return (.device(id), current.findEntity(named: "hardware-selection"), id)
                }
                if current.name.hasPrefix("hardware:") {
                    return (.hardware(String(current.name.dropFirst("hardware:".count))), current.findEntity(named: "hardware-selection"), nil)
                }
                if current.name.hasPrefix("placement:") {
                    return (.placement(String(current.name.dropFirst("placement:".count))), nil, nil)
                }
                entity = current.parent
            }
            return nil
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let view, parent.mode == .room else { return }
            let count = recognizer.numberOfTouches
            guard recognizer.state == .began || recognizer.state == .changed else {
                orbitTouchCount = 0
                return
            }
            let delta = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            defer { orbitTouchCount = count }
            guard recognizer.state == .began || orbitTouchCount == count else { return }
            let movement = SIMD2(Float(delta.x), Float(delta.y))
            if count == 2 {
                shiftOrbit(by: -movement, radius: cameraRadius, height: view.bounds.height)
                cameraMoved = true
                updateCamera()
            } else if count == 1 || count == 3 {
                rotateOrbit(by: LabOrbitGesture.rotation(for: movement, fingers: count))
            }
        }

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view, parent.mode == .room, orbitTouchCount < 3, recognizer.numberOfTouches == 2,
                  recognizer.state == .began || recognizer.state == .changed else { return }
            let scale = Float(recognizer.scale)
            guard scale.isFinite, scale > 0 else { return }
            let prior = cameraRadius
            cameraRadius = min(100, max(0.35, prior / scale))
            let center = recognizer.location(in: view)
            shiftOrbit(by: SIMD2(Float(center.x - view.bounds.midX), Float(center.y - view.bounds.midY)),
                       radius: prior - cameraRadius, height: view.bounds.height)
            cameraMoved = true
            recognizer.scale = 1
            updateCamera()
        }

        @objc private func twist(_ recognizer: UIRotationGestureRecognizer) {
            guard parent.mode == .room, orbitTouchCount < 3, recognizer.numberOfTouches == 2,
                  recognizer.state == .began || recognizer.state == .changed else { return }
            let angle = Float(recognizer.rotation)
            recognizer.rotation = 0
            if angle.isFinite { rotateOrbit(by: SIMD2(-angle, 0)) }
        }

        @objc private func resetWithFourFingers(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended, let view { resetOrbit(to: view.bounds.size) }
        }

        private func rotateOrbit(by delta: SIMD2<Float>) {
            cameraYaw = (cameraYaw + delta.x).truncatingRemainder(dividingBy: 2 * .pi)
            cameraPitch = min(1.52, max(0.02, cameraPitch + delta.y))
            cameraMoved = true
            updateCamera()
        }

        private func shiftOrbit(by delta: SIMD2<Float>, radius: Float, height: CGFloat) {
            let offset = LabOrbitGesture.screenOffset(delta, radius: radius, field: orbitFieldOfView, viewportHeight: Float(height))
            let candidate = cameraTarget + orbitRotation.act(offset)
            let extent = cameraBounds.map { simd_distance($0, defaultCameraTarget) }.max() ?? 5
            let limit = max(2, extent * 1.5)
            let displacement = candidate - defaultCameraTarget
            let distance = simd_length(displacement)
            if distance.isFinite { cameraTarget = defaultCameraTarget + displacement * min(1, limit / max(0.001, distance)) }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer !== waypointPan && otherGestureRecognizer !== waypointPan &&
                !(gestureRecognizer is UITapGestureRecognizer) && !(otherGestureRecognizer is UITapGestureRecognizer)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let drag = waypointPan, let view else { return true }
            let point = gestureRecognizer.location(in: view)
            if gestureRecognizer === drag {
                let delta = drag.translation(in: view)
                let start = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
                return waypointIndex(at: start, in: view) != nil
            }
            return waypointIndex(at: point, in: view) == nil
        }

        private var initialOrbit: (Float, Float) {
            (.pi / 4, 0.75)
        }

        private var orbitRotation: simd_quatf {
            let backward = SIMD3(sin(cameraYaw) * cos(cameraPitch), sin(cameraPitch), -cos(cameraYaw) * cos(cameraPitch))
            let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), backward))
            let up = simd_cross(backward, right)
            return simd_quatf(simd_float3x3(columns: (right, up, backward)))
        }

        private func updateCamera() {
            let rotation = orbitRotation
            camera?.position = cameraTarget + rotation.act(SIMD3(0, 0, cameraRadius))
            camera?.orientation = rotation
            if notifiedOrbitHeading != cameraYaw, parent.onOrbitHeading != nil {
                let heading = cameraYaw
                notifiedOrbitHeading = heading
                Task { @MainActor [weak self] in
                    guard let self, self.cameraYaw == heading else { return }
                    self.parent.onOrbitHeading?(heading)
                }
            }
            repaintStaticTraffic()
        }

        func updateWalkCamera() {
            guard let pose = parent.virtualPose, let camera else { return }
            let lockChanged = lastWalkLock != parent.lockedDeviceID
            let viewport = view?.bounds.size ?? .zero
            if viewport.width > 0, viewport.height > 0 {
                let aspect = Float(viewport.width / viewport.height)
                let minVerticalField = 2 * atan(1.52 / (3 * aspect)) * 180 / .pi
                let field = parent.lockedDeviceID != nil && parent.inspectionDestination?.port == nil
                    ? max(60, min(94, minVerticalField)) : 60
                if camera.camera.fieldOfViewInDegrees != field { camera.camera.fieldOfViewInDegrees = field }
            }
            guard lastWalkPose != pose || lockChanged else { return }
            let rotate = lockChanged && parent.lockedDeviceID != nil && !parent.reduceMotion && parent.stereoEye == 0
                && (lastWalkPose.map { LabWalkPose.canTravel(from: $0.position, to: pose.position, in: parent.layout) } ?? false)
            lastWalkPose = pose
            lastWalkLock = parent.lockedDeviceID
            let transform = Transform(rotation: pose.rotation,
                                      translation: pose.position + pose.rotation.act(SIMD3(parent.stereoEye * 0.032, 0, 0)))
            cameraTurn?.stop()
            if rotate {
                cameraTurn = camera.move(to: transform, relativeTo: camera.parent, duration: 0.24, timingFunction: .easeInOut)
            } else {
                cameraTurn = nil
                camera.transform = transform
            }
            repaintStaticTraffic()
        }

        func applyZoom() {
            guard parent.mode == .room else { return }
            if lastOrbitReset != parent.orbitReset {
                lastOrbitReset = parent.orbitReset
                lastZoomStep = parent.zoomStep
                if let view { resetOrbit(to: view.bounds.size) }
                return
            }
            guard lastZoomStep != parent.zoomStep else { return }
            cameraRadius = min(100, max(0.35, cameraRadius * pow(0.75, Float(parent.zoomStep - lastZoomStep))))
            lastZoomStep = parent.zoomStep
            cameraMoved = true
            updateCamera()
        }

        private func resetOrbit(to size: CGSize) {
            cameraTarget = defaultCameraTarget
            (cameraYaw, cameraPitch) = initialOrbit
            cameraMoved = false
            fitCamera(to: size)
        }

        func layoutCamera(to size: CGSize) {
            if parent.virtualPose != nil { updateWalkCamera() }
            else { fitCamera(to: size) }
        }

        func fitCamera(to size: CGSize) {
            guard parent.mode == .room, parent.virtualPose == nil, camera != nil, !cameraBounds.isEmpty,
                  !cameraMoved, size.width >= 1, size.height >= 1 else { return }
            cameraRadius = LabGeometry.orbitDistance(for: cameraBounds, target: cameraTarget, rotation: orbitRotation,
                                                     aspect: Float(size.width / size.height), verticalField: orbitFieldOfView)
            updateCamera()
        }

        func report(_ message: String?) {
            Task { @MainActor [weak self] in
                guard let self, view != nil else { return }
                let text = renderError ?? message
                if let text, parent.mode == .ar { suspend(.failed(text)) }
                else { parent.trackingMessage = text }
            }
        }

        private func transition(_ phase: ARWalkthrough.Phase) {
            guard let walkthrough = parent.walkthrough, walkthrough.phase != phase else { return }
            walkthrough.phase = phase
            if phase != .ready {
                walkthrough.pose = nil
                walkthrough.target = nil
                walkthrough.focusOrigin = nil
                walkthrough.deviceInSight = nil
                walkthrough.searchMarker = nil
            }
        }

        func hideTrackedContent() {
            tracking = false
            clearARPreview()
            if rootAnchor?.isEnabled == true { rootAnchor?.isEnabled = false }
            configureTraffic()
        }

        private func suspend(_ phase: ARWalkthrough.Phase) {
            hideTrackedContent()
            transition(phase)
        }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // The delegate queue is explicitly set to the main queue in makeUIView.
            MainActor.assumeIsolated { updateTracking(frame) }
        }

        private func applyWorldPlacement(_ anchor: ARAnchor) {
            placedAnchorID = anchor.identifier
            rootAnchor?.transform = Transform(matrix: anchor.transform)
            confirmPlacement()
        }

        private func confirmPlacement() {
            awaitingPlacement = false
            clearARPreview()
            parent.walkthrough?.placementHint = nil
            if parent.isTierAR && parent.assembly == nil && !tierCablesLoaded && parent.topology != nil {
                parent.walkthrough?.tierCableStatus = .loading
            }
            parent.walkthrough?.placementConfirmed = true
        }

        private func updateTracking(_ frame: ARFrame) {
            guard parent.isForeground, let view, rootAnchor != nil, renderError == nil else { return }
            if let phase = unavailablePhase(frame.camera.trackingState) { suspend(phase); return }
            if awaitingPlacement || parent.assemblyPlacementRequested || previewAnchor?.isEnabled == true,
               frame.timestamp - lastPlacementFrameTime >= 1.0 / 30 {
                lastPlacementFrameTime = frame.timestamp
                updateARPreview(frame, in: view)
            }
            if parent.inspectionDestination != nil, !awaitingPlacement, tracking,
               frame.timestamp - lastSearchFrameTime >= 1.0 / 30 {
                lastSearchFrameTime = frame.timestamp
                updateSearchMarker(frame, in: view)
            }
            guard frame.timestamp - lastFrameTime >= 0.15 else { return }
            lastFrameTime = frame.timestamp
            tracking = true
            if let name = parent.worldPlacementName, parent.restoresWorldPlacement || placedAnchorID != nil {
                guard let anchor = frame.anchors.first(where: { $0.name == name }) else {
                    suspend(.aligning)
                    return
                }
                if awaitingPlacement || anchor.identifier != placedAnchorID { applyWorldPlacement(anchor) }
                else { rootAnchor?.transform = Transform(matrix: anchor.transform) }
            }
            if awaitingPlacement {
                transition(parent.restoresWorldPlacement ? .aligning : .placing)
                return
            }
            if stagedTierRoom != nil {
                Task { @MainActor [weak self] in
                    guard let self, parent.isForeground else { return }
                    rebuildIfNeeded()
                }
                return
            }
            if rootAnchor?.isEnabled == false { rootAnchor?.isEnabled = true }
            if parent.assembly != nil {
                if let walkthrough = parent.walkthrough, let rootAnchor {
                    let camera = simd_inverse(rootAnchor.transform.matrix) * frame.camera.transform
                    let forward = -SIMD3(camera.columns.2.x, 0, camera.columns.2.z)
                    if simd_length_squared(forward) > 0.01 { walkthrough.focusDirection = forward }
                }
                transition(.ready)
                configureTraffic()
                updateDashboards()
                return
            }
            loadTierCables()
            configureTraffic()
            repaintStaticTraffic()
            if let walkthrough = parent.walkthrough {
                transition(.ready)
                let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                let hit = target(at: center)
                if walkthrough.target != hit?.item { walkthrough.target = hit?.item }
                if walkthrough.deviceInSight != hit?.deviceID { walkthrough.deviceInSight = hit?.deviceID }
                let t = rootAnchor.map { simd_inverse($0.transform.matrix) * frame.camera.transform } ?? frame.camera.transform
                let camera = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                let forward = -SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
                let modelCamera = camera / parent.sceneScale + focusOrigin
                if walkthrough.focusOrigin != modelCamera { walkthrough.focusOrigin = modelCamera }
                if walkthrough.focusDirection != forward { walkthrough.focusDirection = forward }
                if !parent.arPlacementRequired || placedAnchorID != nil {
                    let pose = ARWalkthrough.Pose(position: SIMD2(modelCamera.x, modelCamera.z),
                                                  direction: SIMD2(-t.columns.2.x, -t.columns.2.z))
                    if walkthrough.pose != pose { walkthrough.pose = pose }
                    #if DEBUG
                    if parent.layout.facility != nil, let rootAnchor {
                        sampleDeviceWalk(cameraPosition: SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z),
                                         anchorPosition: rootAnchor.position(relativeTo: nil), time: frame.timestamp)
                    }
                    #endif
                }
            }
        }

        private func updateSearchMarker(_ frame: ARFrame, in view: ARView) {
            guard let walkthrough = parent.walkthrough else { return }
            guard let destination = parent.inspectionDestination, let model = deviceModels[destination.deviceID],
                  model.isEnabledInHierarchy, let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
                  !view.bounds.isEmpty else {
                if walkthrough.searchMarker != nil { walkthrough.searchMarker = nil }
                return
            }
            let port = destination.port.flatMap { name in
                parent.topology?.devices.first(where: { $0.id == destination.deviceID })
                    .flatMap { try? LabScenePort.local($0, name) }
            }
            let point = model.convert(position: port?.point ?? .zero, to: nil)
            let camera = frame.camera.transform
            var local = simd_inverse(camera) * SIMD4(point.x, point.y, point.z, 1)
            let behind = local.z >= 0
            local.z = -max(abs(local.z), 0.01)
            let projectedWorld = camera * local
            let projectedPoint = SIMD3(projectedWorld.x, projectedWorld.y, projectedWorld.z)
            let size = view.bounds.size
            let screen: CGPoint
            #if compiler(>=6.4)
            // The iOS 27 SDK (Xcode 27) adds projection by rotation angle.
            if #available(iOS 27, *) {
                let angle: CGFloat = switch orientation {
                case .landscapeRight: 0
                case .landscapeLeft: 180
                case .portraitUpsideDown: 270
                default: 90
                }
                screen = frame.camera.projectPoint(projectedPoint, viewRotationAngle: angle, viewportSize: size)
            } else {
                screen = frame.camera.projectPoint(projectedPoint, orientation: orientation, viewportSize: size)
            }
            #else
            // Xcode 26 builds, such as the cloud build, use the orientation API.
            screen = frame.camera.projectPoint(projectedPoint, orientation: orientation, viewportSize: size)
            #endif
            guard screen.x.isFinite, screen.y.isFinite else { return }
            let dx = Float(2 * screen.x / size.width - 1)
            let dy = Float(2 * screen.y / size.height - 1)
            let offset = behind ? SIMD2<Float>(dx < -0.01 ? -2 : 2, 0) : SIMD2(dx, dy)
            let marker = ARWalkthrough.SearchMarker(offset: offset, behind: behind)
            if walkthrough.searchMarker != marker { walkthrough.searchMarker = marker }
        }

        #if DEBUG
        private var initialWalk: (camera: SIMD3<Float>, anchor: SIMD3<Float>)?
        private var walkSampleTime = -Double.infinity
        private var cameraTravel: Float = 0
        private var anchorTravel: Float = 0

        private func sampleDeviceWalk(cameraPosition: SIMD3<Float>, anchorPosition: SIMD3<Float>, time: TimeInterval) {
            guard time - walkSampleTime >= 2 else { return }
            walkSampleTime = time
            if initialWalk == nil { initialWalk = (cameraPosition, anchorPosition) }
            guard let initialWalk else { return }
            cameraTravel = max(cameraTravel, simd_distance(cameraPosition, initialWalk.camera))
            anchorTravel = max(anchorTravel, simd_distance(anchorPosition, initialWalk.anchor))
            let values: [String: Double] = [
                "sampledAt": Date().timeIntervalSince1970,
                "cameraTravelMeters": Double(cameraTravel),
                "anchorTravelMeters": Double(anchorTravel)
            ]
            let url = URL.cachesDirectory.appendingPathComponent("NexusWalkthrough.json")
            if let data = try? JSONEncoder().encode(values) { try? data.write(to: url, options: .atomic) }
        }
        #endif

        private func unavailablePhase(_ state: ARCamera.TrackingState) -> ARWalkthrough.Phase? {
            switch state {
            case .normal: return nil
            case .notAvailable: return .limited("La cámara aún no puede ubicar el iPhone.")
            case .limited(.initializing): return .starting
            case .limited(.relocalizing): return .aligning
            case .limited(.excessiveMotion): return .limited("Baja la velocidad y mantén el iPhone estable.")
            case .limited(.insufficientFeatures): return .limited("Apunta a una pared iluminada con detalles.")
            case .limited: return .limited("Mueve el iPhone despacio para recuperar la posición.")
            }
        }

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            MainActor.assumeIsolated {
                guard view != nil, rootAnchor != nil, renderError == nil,
                      let phase = unavailablePhase(camera.trackingState) else { return }
                suspend(phase)
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            MainActor.assumeIsolated { suspend(.interrupted) }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            MainActor.assumeIsolated { suspend(parent.arPlacementRequired ? .starting : .aligning) }
        }

        nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }

        nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
            let message = "AR: " + error.localizedDescription
            MainActor.assumeIsolated { suspend(.failed(message)) }
        }

        private weak var attachedPeerSession: NexusPeerSession?
        private var participantEntities: [UUID: Entity] = [:]

        func setupPeerSession(_ session: NexusPeerSession?) {
            guard let session else {
                attachedPeerSession = nil
                return
            }
            guard session !== attachedPeerSession else { return }
            attachedPeerSession = session

            session.onMessageReceived = { [weak self] message in
                guard let self else { return }
                switch message {
                case .movePlacement(let id, let x, let y, let z, let yaw):
                    self.applyPeerPlacementMove(id: id, x: x, y: y, z: z, yaw: yaw)
                case .alignMarker(let matrix):
                    self.applyMarkerAlignment(matrix)
                default: break
                }
            }

            session.onCollaborationDataReceived = { [weak self] data in
                guard let self, let arSession = self.parent.arSession else { return }
                arSession.update(with: data)
            }
        }

        func applyPeerPlacementMove(id: String, x: Float, y: Float, z: Float, yaw: Float) {
            guard let model = placementModels[id] else { return }
            var targetTransform = model.transform
            targetTransform.translation = SIMD3<Float>(x, y, z)
            targetTransform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            model.move(to: targetTransform, relativeTo: model.parent, duration: 0.05, timingFunction: .easeInOut)
        }

        func applyMarkerAlignment(_ matrix: [Float]) {
            guard matrix.count == 16, let root = rootAnchor else { return }
            let col0 = SIMD4<Float>(matrix[0], matrix[1], matrix[2], matrix[3])
            let col1 = SIMD4<Float>(matrix[4], matrix[5], matrix[6], matrix[7])
            let col2 = SIMD4<Float>(matrix[8], matrix[9], matrix[10], matrix[11])
            let col3 = SIMD4<Float>(matrix[12], matrix[13], matrix[14], matrix[15])
            let simdMatrix = simd_float4x4(columns: (col0, col1, col2, col3))
            root.transform = Transform(matrix: simdMatrix)
            parent.walkthrough?.placementConfirmed = true
        }

        func syncMarkerTransformToPeer() {
            guard let root = rootAnchor, let session = attachedPeerSession else { return }
            let cols = root.transform.matrix.columns
            let floatArray: [Float] = [
                cols.0.x, cols.0.y, cols.0.z, cols.0.w,
                cols.1.x, cols.1.y, cols.1.z, cols.1.w,
                cols.2.x, cols.2.y, cols.2.z, cols.2.w,
                cols.3.x, cols.3.y, cols.3.z, cols.3.w
            ]
            session.sendReliable(.alignMarker(transform: floatArray))
        }

        private func updateParticipantAnchor(_ anchor: ARParticipantAnchor) {
            guard let root = rootAnchor else { return }
            let sphere: Entity
            if let existing = participantEntities[anchor.identifier] {
                sphere = existing
            } else {
                let meshEntity = ModelEntity(
                    mesh: .generateSphere(radius: 0.05),
                    materials: [SimpleMaterial(color: UIColor.systemCyan.withAlphaComponent(0.85), isMetallic: false)]
                )
                let pointer = ModelEntity(
                    mesh: .generateBox(size: [0.02, 0.02, 0.10]),
                    materials: [SimpleMaterial(color: UIColor.systemBlue, isMetallic: false)]
                )
                pointer.position = [0, 0, -0.06]
                meshEntity.addChild(pointer)
                root.addChild(meshEntity)
                participantEntities[anchor.identifier] = meshEntity
                sphere = meshEntity
            }
            sphere.transform = Transform(matrix: anchor.transform)
        }

        nonisolated func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
            MainActor.assumeIsolated {
                self.attachedPeerSession?.sendARCollaborationData(data)
            }
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            MainActor.assumeIsolated {
                for anchor in anchors {
                    if let participant = anchor as? ARParticipantAnchor {
                        self.updateParticipantAnchor(participant)
                    }
                }
            }
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            MainActor.assumeIsolated {
                for anchor in anchors {
                    if let participant = anchor as? ARParticipantAnchor {
                        self.updateParticipantAnchor(participant)
                    }
                }
            }
        }
    }
}

extension LabTopology.Medium {
    var sceneColor: UIColor {
        switch self {
        case .copper: UIColor(red: 0.12, green: 0.42, blue: 0.93, alpha: 1)
        case .fiber: UIColor(red: 1, green: 0.53, blue: 0.07, alpha: 1)
        case .serial: UIColor(red: 0.50, green: 0.29, blue: 0.75, alpha: 1)
        case .console: UIColor(red: 0.12, green: 0.73, blue: 0.74, alpha: 1)
        case .powerA: UIColor(red: 0.78, green: 0.21, blue: 0.22, alpha: 1)
        case .powerB: UIColor(red: 0.57, green: 0.35, blue: 0.90, alpha: 1)
        }
    }
}

enum LabSignalColor {
    static let outgoing = UIColor(red: 0.2, green: 0.95, blue: 0.58, alpha: 1)
    static let incoming = UIColor(red: 1, green: 0.48, blue: 0.13, alpha: 1)
    static let trace = UIColor(red: 1, green: 0.79, blue: 0.28, alpha: 1)
}

private struct LabSceneMaterials {
    let white: PhysicallyBasedMaterial
    let facilityFloor = SimpleMaterial(color: UIColor(red: 0.52, green: 0.59, blue: 0.62, alpha: 1), roughness: 0.8, isMetallic: false)
    let facilityWall = SimpleMaterial(color: UIColor(red: 0.34, green: 0.42, blue: 0.48, alpha: 1), roughness: 0.82, isMetallic: false)
    let coldAisle = SimpleMaterial(color: UIColor(red: 0.35, green: 0.63, blue: 0.72, alpha: 1), roughness: 0.84, isMetallic: false)
    let hotAisle = SimpleMaterial(color: UIColor(red: 0.72, green: 0.49, blue: 0.37, alpha: 1), roughness: 0.84, isMetallic: false)
    let graphite = SimpleMaterial(color: UIColor(red: 0.14, green: 0.16, blue: 0.18, alpha: 1), roughness: 0.57, isMetallic: false)
    let panel = SimpleMaterial(color: UIColor(red: 0.29, green: 0.34, blue: 0.37, alpha: 1), roughness: 0.49, isMetallic: false)
    let metal = SimpleMaterial(color: UIColor(red: 0.63, green: 0.67, blue: 0.69, alpha: 1), roughness: 0.36, isMetallic: true)
    let connector = SimpleMaterial(color: UIColor(red: 0.52, green: 0.61, blue: 0.63, alpha: 1), roughness: 0.36, isMetallic: false)
    let copperPlug = SimpleMaterial(color: UIColor(red: 0.82, green: 0.89, blue: 0.92, alpha: 0.9), roughness: 0.21, isMetallic: false)
    let copperContacts = SimpleMaterial(color: UIColor(red: 0.80, green: 0.57, blue: 0.25, alpha: 1), roughness: 0.28, isMetallic: true)
    let dark = SimpleMaterial(color: UIColor(white: 0.025, alpha: 1), roughness: 0.8, isMetallic: false)
    let power: UnlitMaterial
    let activity: UnlitMaterial
    let screen: UnlitMaterial
    let accent: UnlitMaterial
    let trace: UnlitMaterial
    let blockedTrace: UnlitMaterial
    let powerA: UnlitMaterial
    let powerB: UnlitMaterial
    let off = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1), roughness: 0.8, isMetallic: false)
    let copperWire = SimpleMaterial(color: LabTopology.Medium.copper.sceneColor, roughness: 0.55, isMetallic: false)
    let fiberWire = SimpleMaterial(color: LabTopology.Medium.fiber.sceneColor, roughness: 0.55, isMetallic: false)
    let serialWire = SimpleMaterial(color: LabTopology.Medium.serial.sceneColor, roughness: 0.55, isMetallic: false)
    let consoleWire = SimpleMaterial(color: LabTopology.Medium.console.sceneColor, roughness: 0.55, isMetallic: false)

    init() {
        var white = PhysicallyBasedMaterial()
        white.baseColor = .init(tint: .white)
        white.roughness = 0.92
        white.metallic = 0.0
        self.white = white
        var power = UnlitMaterial(); power.color = .init(tint: LabSignalColor.outgoing); self.power = power
        var activity = UnlitMaterial(); activity.color = .init(tint: LabSignalColor.incoming); self.activity = activity
        var screen = UnlitMaterial(); screen.color = .init(tint: UIColor(red: 0.03, green: 0.25, blue: 0.44, alpha: 1)); self.screen = screen
        var accent = UnlitMaterial(); accent.color = .init(tint: UIColor(red: 0.1, green: 0.58, blue: 1, alpha: 1)); self.accent = accent
        var trace = UnlitMaterial(); trace.color = .init(tint: LabSignalColor.trace); self.trace = trace
        var blocked = UnlitMaterial(); blocked.color = .init(tint: .systemRed); blockedTrace = blocked
        var powerA = UnlitMaterial(); powerA.color = .init(tint: LabTopology.Medium.powerA.sceneColor); self.powerA = powerA
        var powerB = UnlitMaterial(); powerB.color = .init(tint: LabTopology.Medium.powerB.sceneColor); self.powerB = powerB
    }
}

private final class LabRenderView: ARView {
    var didLayout: ((CGSize) -> Void)?
    var didAttach: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { didAttach?() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?(bounds.size)
    }
}

private nonisolated struct LabSceneMesh: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    mutating func append(positions newPositions: [SIMD3<Float>], normals newNormals: [SIMD3<Float>], indices newIndices: [UInt32]) {
        let offset = UInt32(positions.count)
        positions += newPositions; normals += newNormals; indices += newIndices.map { $0 + offset }
    }

    mutating func box(size: SIMD3<Float>, center: SIMD3<Float>, matrix: simd_float4x4 = matrix_identity_float4x4) {
        let half = size / 2
        let corners: [SIMD3<Float>] = [SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
                                      SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)]
        let faces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [0, 1, 5, 4], [3, 7, 6, 2]]
        let faceNormals: [SIMD3<Float>] = [SIMD3(0, 0, -1), SIMD3(0, 0, 1), SIMD3(-1, 0, 0), SIMD3(1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, 1, 0)]
        for (index, face) in faces.enumerated() {
            let points = face.map { matrix * SIMD4(corners[$0] * half + center, 1) }.map { SIMD3($0.x, $0.y, $0.z) }
            let normal4 = matrix * SIMD4(faceNormals[index], 0)
            let normal = simd_normalize(SIMD3(normal4.x, normal4.y, normal4.z))
            append(positions: points, normals: Array(repeating: normal, count: 4), indices: [0, 1, 2, 0, 2, 3])
        }
    }

    mutating func cableGuide(from start: SIMD3<Float>, to end: SIMD3<Float>, size: SIMD2<Float>) {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.001 else { return }
        let axis = delta / length
        let (sideAxis, upAxis) = LabCablePacking.frame(along: axis)
        let transform = simd_float4x4(columns: (SIMD4(sideAxis, 0), SIMD4(upAxis, 0),
                                               SIMD4(axis, 0), SIMD4((start + end) / 2, 1)))
        for side: Float in [-1, 1] {
            box(size: SIMD3(0.004, size.y, length),
                center: SIMD3(side * (size.x / 2 + 0.002), 0, 0), matrix: transform)
        }
        box(size: SIMD3(size.x + 0.008, 0.004, length),
            center: SIMD3(0, -size.y / 2 - 0.002, 0), matrix: transform)
    }

    mutating func cableElbow(_ elbow: LabCablePacking.Elbow) {
        guard elbow.points.count >= 2 else { return }
        let initialSide = LabCablePacking.frame(along: elbow.incoming).side
        let endingSide = LabCablePacking.frame(along: elbow.outgoing).side
        let carried = simd_quatf(from: elbow.incoming, to: elbow.outgoing).act(initialSide)
        let roll = atan2(simd_dot(simd_cross(carried, endingSide), elbow.outgoing), simd_dot(carried, endingSide))
        var previous: [SIMD3<Float>] = []
        for index in elbow.points.indices {
            let point = elbow.points[index]
            let fraction = Float(index) / Float(elbow.points.count - 1)
            let tangent: SIMD3<Float>
            if index == 0 { tangent = elbow.incoming }
            else if index == elbow.points.count - 1 { tangent = elbow.outgoing }
            else { tangent = simd_normalize(elbow.points[index + 1] - elbow.points[index - 1]) }
            let side = simd_quatf(angle: roll * fraction, axis: tangent)
                .act(simd_quatf(from: elbow.incoming, to: tangent).act(initialSide))
            let up = simd_cross(tangent, side)
            let size = elbow.startSize + (elbow.endSize - elbow.startSize) * fraction
            let width = size.x / 2, height = size.y / 2
            let wall: Float = 0.004
            // Match the open U section of the straight trays through the whole bend.
            let section: [SIMD2<Float>] = [
                [-width - wall, -height - wall], [width + wall, -height - wall],
                [width + wall, height], [width, height], [width, -height], [-width, -height],
                [-width, height], [-width - wall, height]
            ]
            let ring = section.map { point + side * $0.x + up * $0.y }
            if !previous.isEmpty {
                for corner in ring.indices {
                    let next = (corner + 1) % ring.count
                    let face = [previous[corner], previous[next], ring[next], ring[corner]]
                    let normal = simd_normalize(simd_cross(face[1] - face[0], face[3] - face[0]))
                    append(positions: face, normals: Array(repeating: normal, count: 4), indices: [0, 1, 2, 0, 2, 3])
                }
            }
            previous = ring
        }
    }

    mutating func rackOrganizer(_ organizer: LabCablePacking.Organizer, mountings: inout LabSceneMesh) {
        let rack = organizer.rack
        let face = organizer.face
        let railDepth = face.railDepth(in: rack.size)
        let depth = organizer.depth
        var frame = simd_float4x4(simd_quatf(angle: rack.yaw, axis: SIMD3(0, 1, 0)))
        frame.columns.3 = SIMD4(rack.position, 1)

        switch organizer.mount {
        case .horizontal(let rows):
            let y = rows.lowerBound - 0.014
            let halfSpan = rack.size.x / 2 - 0.011
            let sectionDepth: Float = face == .front ? 0.038 : 0.034
            let bracketDepth = abs(depth - railDepth)
            box(size: SIMD3(2 * halfSpan, 0.004, sectionDepth), center: SIMD3(0, y, depth), matrix: frame)
            for side: Float in [-1, 1] {
                let x = side * organizer.railX
                mountings.box(size: SIMD3(0.022, 0.030, 0.004),
                              center: SIMD3(x, y + 0.008, railDepth + face.sign * 0.013), matrix: frame)
                mountings.box(size: SIMD3(0.015, 0.004, bracketDepth + 0.016),
                              center: SIMD3(x, y, (railDepth + depth) / 2), matrix: frame)
                for screwY in [y + 0.001, y + 0.018] {
                    mountings.box(size: SIMD3(0.007, 0.007, 0.003),
                                  center: SIMD3(x, screwY, railDepth + face.sign * 0.016), matrix: frame)
                }
            }
            let count = max(2, Int(ceil(2 * halfSpan / 0.16)))
            let height: Float = 0.012
            for index in 0..<count {
                let x = (Float(index) + 0.5) * 2 * halfSpan / Float(count) - halfSpan
                let fingerWidth: Float = face == .front ? 0.009 : 0.007
                let outerEdge = depth + face.sign * (sectionDepth / 2 - 0.002)
                box(size: SIMD3(fingerWidth, height, 0.004), center: SIMD3(x, y + height / 2, outerEdge), matrix: frame)
                box(size: SIMD3(fingerWidth, 0.004, 0.011),
                    center: SIMD3(x, y + height, outerEdge - face.sign * 0.004), matrix: frame)
                if face == .rear {
                    box(size: SIMD3(fingerWidth, height, 0.003),
                        center: SIMD3(x, y + height / 2, depth - face.sign * sectionDepth / 2), matrix: frame)
                }
            }
        case .vertical(let x, let heights):
            let halfWidth = rack.size.x / 2
            let side: Float = x < 0 ? -1 : 1
            let lower = max(0.028, heights.lowerBound - 0.012)
            let upper = min(rack.size.y - 0.035, heights.upperBound + 0.018)
            let length = upper - lower
            guard length > 0.020 else { return }
            let backing = x + side * 0.019
            box(size: SIMD3(0.004, length, 0.028), center: SIMD3(backing, (lower + upper) / 2, depth), matrix: frame)
            let count = max(1, Int(ceil(length / 0.17)))
            for index in 0..<count {
                let y = lower + (Float(index) + 0.5) * length / Float(count)
                for edge: Float in [-1, 1] {
                    let z = depth + edge * 0.018
                    box(size: SIMD3(0.030, 0.007, 0.004), center: SIMD3(x + side * 0.003, y, z), matrix: frame)
                    box(size: SIMD3(0.004, 0.007, 0.009),
                        center: SIMD3(x - side * 0.012, y, z - edge * 0.003), matrix: frame)
                }
            }
            // Inboard drops bolt onto the horizontal organizers at each end.
            if abs(x) < halfWidth - 0.060 {
                for y in [lower, upper] {
                    mountings.box(size: SIMD3(0.022, 0.012, 0.006), center: SIMD3(backing, y, depth), matrix: frame)
                }
                return
            }
            let mounts = max(2, Int(ceil(length / 0.38)))
            for index in 0..<mounts {
                let y = lower + (Float(index) + 0.5) * length / Float(mounts)
                let depthSpan = abs(depth - railDepth)
                mountings.box(size: SIMD3(0.017, 0.017, depthSpan + 0.016),
                              center: SIMD3(backing, y, (railDepth + depth) / 2), matrix: frame)
                mountings.box(size: SIMD3(0.008, 0.024, 0.023),
                              center: SIMD3(side * (halfWidth - 0.011), y, railDepth), matrix: frame)
                mountings.box(size: SIMD3(0.003, 0.007, 0.007),
                              center: SIMD3(side * (halfWidth - 0.016), y, railDepth), matrix: frame)
            }
        case .depthRun(let ports, let rows, let span):
            let spanLength = span.upperBound - span.lowerBound
            let shortBridge = organizer.portDepth == nil && spanLength < 0.13
            let connectorGap = min(0.028, spanLength / 3)
            let start = span.lowerBound + (organizer.portDepth == span.lowerBound ? connectorGap : 0)
            let end = span.upperBound - (organizer.portDepth == span.upperBound ? connectorGap : 0)
            let length = end - start
            let x = (ports.lowerBound + ports.upperBound) / 2
            let width = ports.upperBound - ports.lowerBound + 0.032
            let y = rows.lowerBound - 0.016
            let height: Float = 0.014
            box(size: SIMD3(width, 0.004, length), center: SIMD3(x, y, (start + end) / 2), matrix: frame)
            let clips = max(1, Int(ceil(length / 0.17)))
            for index in 0..<clips {
                let z = start + (Float(index) + 0.5) * length / Float(clips)
                for side: Float in [-1, 1] {
                    let edge = x + side * (width / 2 - 0.002)
                    box(size: SIMD3(0.004, height, 0.009), center: SIMD3(edge, y + height / 2, z), matrix: frame)
                    box(size: SIMD3(0.008, 0.004, 0.009), center: SIMD3(edge - side * 0.002, y + height, z), matrix: frame)
                }
            }
            let side: Float = x < 0 ? -1 : 1
            let anchorX = side * (shortBridge ? organizer.railX : rack.size.x / 2 - 0.012)
            let count = max(1, Int(ceil(length / 0.30)))
            for index in 0..<count {
                let z = start + (Float(index) + 0.5) * length / Float(count)
                mountings.box(size: SIMD3(abs(anchorX - x) + 0.012, 0.007, 0.016),
                              center: SIMD3((anchorX + x) / 2, y - 0.005, z), matrix: frame)
                if !shortBridge {
                    mountings.box(size: SIMD3(0.006, 0.026, 0.024), center: SIMD3(anchorX, y, z), matrix: frame)
                }
            }
            if shortBridge {
                let middle = (start + end) / 2
                mountings.box(size: SIMD3(0.012, 0.025, abs(middle - railDepth) + 0.014),
                              center: SIMD3(anchorX, y, (middle + railDepth) / 2), matrix: frame)
            }
        }
    }

    mutating func cable(_ route: [SIMD3<Float>], radius: Float, sides: Int = 8) {
        var points: [SIMD3<Float>] = []
        for point in route where points.last.map({ simd_distance_squared($0, point) > 0.00000001 }) ?? true {
            points.append(point)
        }
        guard points.count >= 2 else { return }
        let segments = zip(points, points.dropFirst()).map { simd_normalize($1 - $0) }
        var radial = LabCablePacking.frame(along: segments[0]).side
        for index in points.indices {
            let incoming = segments[max(0, index - 1)]
            let outgoing = segments[min(index, segments.count - 1)]
            let tangent = simd_normalize(incoming + outgoing)
            let projected = radial - tangent * simd_dot(radial, tangent)
            radial = simd_length_squared(projected) < 0.00001
                ? LabCablePacking.frame(along: tangent).side : simd_normalize(projected)
            let vertical = simd_cross(tangent, radial)
            let base = UInt32(positions.count)
            for side in 0..<sides {
                let angle = 2 * Float.pi * Float(side) / Float(sides)
                let normal = radial * cos(angle) + vertical * sin(angle)
                positions.append(points[index] + radius * normal)
                normals.append(normal)
                if index > 0 {
                    let a = base + UInt32(side), b = base + UInt32((side + 1) % sides)
                    let previous = UInt32(sides)
                    indices += [a - previous, b - previous, a, a, b - previous, b]
                }
            }
        }
    }

    mutating func tube(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float) {
        let axis = simd_normalize(b - a)
        let reference = abs(axis.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let u = simd_normalize(simd_cross(axis, reference)), v = simd_cross(axis, u)
        // ponytail: eight-sided batched tubes are enough for 1:1 patch cords; no entity per segment.
        for side in 0..<8 {
            let angleA = Float(side) * .pi / 4, angleB = Float(side + 1) * .pi / 4
            let normalA = u * cos(angleA) + v * sin(angleA), normalB = u * cos(angleB) + v * sin(angleB)
            let base = positions.count
            append(positions: [a + normalA * radius, a + normalB * radius, b + normalB * radius, b + normalA * radius],
                   normals: [normalA, normalB, normalB, normalA], indices: [0, 1, 2, 0, 2, 3])
            assert(simd_dot(simd_cross(positions[base + 1] - positions[base], positions[base + 2] - positions[base]), normalA + normalB) > 0,
                   "Cable triangle must face outward.")
        }
    }

    func descriptor(name: String = "Nexus — geometría original", materialIndex: UInt32 = 0) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .allFaces(materialIndex)
        return descriptor
    }

    @MainActor func model(material: any RealityKit.Material) throws -> ModelEntity {
        ModelEntity(mesh: try MeshResource.generate(from: [descriptor()]), materials: [material])
    }
}
