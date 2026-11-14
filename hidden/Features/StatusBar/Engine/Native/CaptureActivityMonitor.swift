//
//  CaptureActivityMonitor.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import CoreAudio
import CoreMediaIO
import Darwin
import Foundation

// Whether any app is recording from a microphone or using a camera. macOS 27
// runs every native visibility restriction in assessment mode, which also hides
// the menu-bar capsule naming the app that records (#437), so
// NativeVisibilityEngine holds no restriction while this is active.
protocol CaptureActivityMonitoring: AnyObject {
    var isActive: Bool { get }

    // Called on the main queue whenever isActive may have changed.
    var onChange: (() -> Void)? { get set }
}

// Reads the same public state the recording indicators reflect, for every
// process, without the microphone or camera permission:
// - microphone: each audio process object's "is running input" (macOS 14.2+).
//   Device-level "running somewhere" would also fire for a headset that is
//   only playing audio.
// - camera: each camera device's "running somewhere".
// Screen recording has no public equivalent, so it is not covered.
final class CaptureActivityMonitor: CaptureActivityMonitoring {
    var onChange: (() -> Void)?

    private var processes: [AudioObjectID] = []
    private var cameras: [CMIOObjectID] = []
    // The process and camera lists change rarely; an object's running state
    // changes whenever an app starts or stops capturing. They get separate
    // blocks so a state change only reports, and never re-registers.
    private var listListener: AudioObjectPropertyListenerBlock!
    private var cameraListListener: CMIOObjectPropertyListenerBlock!
    private var runningListener: AudioObjectPropertyListenerBlock!
    private var cameraRunningListener: CMIOObjectPropertyListenerBlock!

    init() {
        // One block per kind for every registration, so each can be removed again.
        listListener = { [weak self] _, _ in self?.devicesDidChange() }
        cameraListListener = { [weak self] _, _ in self?.devicesDidChange() }
        runningListener = { [weak self] _, _ in self?.onChange?() }
        cameraRunningListener = { [weak self] _, _ in self?.onChange?() }
        if #available(macOS 14.2, *) {
            var processList = Self.audioAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processList, .main, listListener)
        }
        var cameraList = Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraList, .main, cameraListListener)
        track()
    }

    deinit {
        untrack()
        if #available(macOS 14.2, *) {
            var processList = Self.audioAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processList, .main, listListener)
        }
        var cameraList = Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraList, .main, cameraListListener)
    }

    var isActive: Bool {
        if #available(macOS 14.2, *) {
            if processes.contains(where: {
                Self.audioFlag(kAudioProcessPropertyIsRunningInput, of: $0) && !Self.isAlwaysOnSpeechListener($0)
            }) {
                return true
            }
        }
        return cameras.contains { Self.cameraIsRunning($0) }
    }

    private func devicesDidChange() {
        track()
        onChange?()
    }

    // Registers only on objects that are new since the last call and drops the
    // ones that are gone. Re-registering on every object each time piled up
    // listeners until the main thread did nothing else (2.0.0 and earlier).
    private func track() {
        if #available(macOS 14.2, *) {
            let change = Self.diff(old: processes, new: Self.audioObjects(kAudioHardwarePropertyProcessObjectList))
            var running = Self.audioAddress(kAudioProcessPropertyIsRunningInput)
            for process in change.removed {
                AudioObjectRemovePropertyListenerBlock(process, &running, .main, runningListener)
            }
            for process in change.added {
                AudioObjectAddPropertyListenerBlock(process, &running, .main, runningListener)
            }
            processes = change.current
        }
        let change = Self.diff(old: cameras, new: Self.cameraObjects())
        var running = Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for camera in change.removed {
            CMIOObjectRemovePropertyListenerBlock(camera, &running, .main, cameraRunningListener)
        }
        for camera in change.added {
            CMIOObjectAddPropertyListenerBlock(camera, &running, .main, cameraRunningListener)
        }
        cameras = change.current
    }

    // Removing from an object that has already gone away fails harmlessly.
    private func untrack() {
        if #available(macOS 14.2, *) {
            var running = Self.audioAddress(kAudioProcessPropertyIsRunningInput)
            for process in processes {
                AudioObjectRemovePropertyListenerBlock(process, &running, .main, runningListener)
            }
        }
        var running = Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for camera in cameras {
            CMIOObjectRemovePropertyListenerBlock(camera, &running, .main, cameraRunningListener)
        }
        processes = []
        cameras = []
    }

    struct ObjectChange<ID: Hashable> {
        var added: [ID]
        var removed: [ID]
        var current: [ID]
    }

    // Duplicates in the new list are registered once.
    static func diff<ID: Hashable>(old: [ID], new: [ID]) -> ObjectChange<ID> {
        var seen = Set<ID>()
        let current = new.filter { seen.insert($0).inserted }
        let before = Set(old)
        return ObjectChange(added: current.filter { !before.contains($0) },
                            removed: old.filter { !seen.contains($0) },
                            current: current)
    }

    // MARK: - CoreAudio

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: selector,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = audioAddress(selector)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func audioFlag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var address = audioAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    // CoreSpeech keeps an input stream open for speech recognition even when no
    // recording indicator is shown. Treating it as active capture would disable
    // hiding permanently on systems where the listener is enabled.
    private static func isAlwaysOnSpeechListener(_ object: AudioObjectID) -> Bool {
        var address = audioAddress(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr else { return false }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
        return isAlwaysOnSpeechListener(path: String(cString: path))
    }

    static func isAlwaysOnSpeechListener(path: String) -> Bool {
        return path == "/System/Library/PrivateFrameworks/CoreSpeech.framework/corespeechd"
    }

    // MARK: - CoreMediaIO

    private static func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        return CMIOObjectPropertyAddress(mSelector: selector,
                                         mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                         mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameraObjects() -> [CMIOObjectID] {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func cameraIsRunning(_ camera: CMIOObjectID) -> Bool {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
            && value != 0
    }
}
