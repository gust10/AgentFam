// SceneViewWrapper.swift
// NSViewRepresentable bridging an SCNView (SceneKit) into SwiftUI.
//
// Three-layer transparency setup (all three are required):
//   1. NSWindow.backgroundColor = .clear + isOpaque = false  (OverlayWindow.swift)
//   2. scnView.backgroundColor = .clear                      (this file)
//   3. scene.background.contents = NSColor.clear             (this file)
// Omitting any one of these leaves an opaque black or grey region.
//
// GLB loading chain:
//   Bundle → URL → SCNScene(url:options:) — on macOS 12+ SceneKit routes
//   GLB/glTF 2.0 through ModelIO internally; no explicit MDLAsset bridge needed.
//
// When agent.glb is absent (e.g. during initial development) a blue placeholder
// sphere is inserted so the SceneKit view is never visually empty.
//
// To add animation playback later:
//   1. Set scnView.rendersContinuously = true
//   2. Iterate avatarScene.rootNode's animation keys and call play() on each
//      SCNAnimationPlayer if using player-based animations.

import SwiftUI
import SceneKit

// MARK: - SceneViewWrapper

struct SceneViewWrapper: NSViewRepresentable {

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero, options: nil)
        configureView(scnView)

        let scene = makeScene()
        scnView.scene      = scene
        scnView.pointOfView = addCamera(to: scene)
        addLighting(to: scene)
        loadAvatar(into: scene)

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        // No dynamic updates for the static avatar view — extend here when
        // avatar swap or animation state control is needed.
    }

    // MARK: - SCNView configuration

    private func configureView(_ scnView: SCNView) {
        // Layer 2 of 3 for transparency (see file header).
        // Note: SCNView.isOpaque is read-only; set the layer's opacity via
        // backgroundColor = .clear which already implies transparency.
        scnView.backgroundColor       = .clear

        // Disable built-in camera controls (the user cannot orbit the avatar).
        // Set to true temporarily if you want to inspect the loaded model.
        scnView.allowsCameraControl   = false

        // Only redraw when the scene changes — saves GPU power when idle.
        // Set to true if agent.glb contains looping skeletal animations.
        scnView.rendersContinuously   = false

        // We add our own lights below; disabling auto-lighting gives
        // predictable results when the GLB file has no embedded lights.
        scnView.autoenablesDefaultLighting = false

        // Anti-aliasing for smooth avatar edges.
        scnView.antialiasingMode      = .multisampling4X
    }

    // MARK: - Scene construction

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Layer 3 of 3 for transparency.
        // Sets the "skybox" (scene background) to fully transparent so the
        // desktop / underlying windows show through behind the avatar.
        scene.background.contents = NSColor.clear

        return scene
    }

    // MARK: - Camera

    @discardableResult
    private func addCamera(to scene: SCNScene) -> SCNNode {
        let camera        = SCNCamera()
        camera.fieldOfView = 35          // narrow FOV = less distortion
        camera.zNear      = 0.1
        camera.zFar       = 100

        let cameraNode    = SCNNode()
        cameraNode.name   = "MainCamera"
        cameraNode.camera = camera
        // Position: slightly above centre, pulled back 4 units on the Z axis.
        // Adjust Z to frame the avatar (move closer / farther).
        cameraNode.position = SCNVector3(x: 0, y: 1.5, z: 4)
        scene.rootNode.addChildNode(cameraNode)
        return cameraNode
    }

    // MARK: - Lighting

    private func addLighting(to scene: SCNScene) {
        // Ambient fill light — removes pitch-black shadow areas.
        let ambientNode        = SCNNode()
        let ambient            = SCNLight()
        ambient.type           = .ambient
        ambient.color          = NSColor.white
        ambient.intensity      = 500
        ambientNode.light      = ambient
        ambientNode.name       = "AmbientLight"
        scene.rootNode.addChildNode(ambientNode)

        // Directional key light — gives the avatar shape and definition.
        let directionalNode    = SCNNode()
        let directional        = SCNLight()
        directional.type       = .directional
        directional.color      = NSColor.white
        directional.intensity  = 800
        directional.castsShadow = false   // shadows on a transparent overlay look odd
        directionalNode.light  = directional
        // Rotate 45° down and 45° to the right for a classic "three-point" setup.
        // SCNVector3 components are CGFloat on macOS (SCNFloat = CGFloat on 64-bit).
        directionalNode.eulerAngles = SCNVector3(
            x: -CGFloat.pi / 4,
            y:  CGFloat.pi / 4,
            z:  0
        )
        directionalNode.name  = "DirectionalLight"
        scene.rootNode.addChildNode(directionalNode)
    }

    // MARK: - GLB / Avatar loading

    private func loadAvatar(into scene: SCNScene) {
        // Locate agent.glb in the app bundle.
        // Add agent.glb to the Xcode project under "Copy Bundle Resources".
        guard let url = Bundle.main.url(forResource: "agent", withExtension: "glb") else {
            print("[VividTeam] agent.glb not found in bundle — showing placeholder geometry.")
            insertPlaceholderGeometry(into: scene)
            return
        }


        // Load via SceneKit's native URL-based loader.
        // On macOS 12+, SCNScene(url:options:) routes GLB/glTF 2.0 through the
        // internal ModelIO pipeline automatically — no cross-framework bridge needed.
        // (SCNScene(mdlAsset:) requires the SceneKit+ModelIO category header which
        // is not always auto-linked in SwiftPM builds.)
        guard let avatarScene = try? SCNScene(url: url, options: nil) else {
            print("[VividTeam] SCNScene failed to load agent.glb — showing placeholder.")
            insertPlaceholderGeometry(into: scene)
            return
        }

        // Graft the avatar's top-level nodes into our scene.
        // We move nodes rather than nesting scenes to keep the scene graph flat
        // and avoid SCNScene ownership conflicts.
        for child in avatarScene.rootNode.childNodes {
            child.removeFromParentNode()
            scene.rootNode.addChildNode(child)
        }

        print("[VividTeam] agent.glb loaded successfully.")
    }

    // MARK: - Placeholder geometry

    /// Called when agent.glb is absent. Scene is left empty so the transparent
    /// SCNView shows through to the overlay background — no blue sphere.
    private func insertPlaceholderGeometry(into scene: SCNScene) {
        // No geometry added intentionally.
        // The ActiveAgentView SwiftUI layer provides the visual placeholder
        // until a real agent.glb is bundled with the app.
    }
}
