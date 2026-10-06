import CoreAudio
import AppKit
import Darwin
import QuickTileCore

struct VolumeControl {
    var outputDeviceID: UInt32? { try? device() }
    var outputDeviceName: String? {
        guard let device = try? device() else { return nil }
        var property = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
    private var restoreKey: String? {
        guard let device = try? device() else { return nil }
        var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, let value else { return nil }
        return "volumeRestore." + (value.takeRetainedValue() as String)
    }
    var restoreLevel: Double? {
        // Preserve adjustments made directly on the Mac while its output is muted.
        if isMuted() == true, let underlying = read(includeMute: false), underlying > 0 { return underlying }
        guard let key = restoreKey, let value = UserDefaults.standard.object(forKey: key) as? Double, value > 0, value <= 1 else { return nil }
        return value
    }
    private func device() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { throw QuickTileError.unsupported("No audio output device is available.") }
        return device
    }
    private func address(_ selector: AudioObjectPropertySelector, _ channel: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
    }
    private func writable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ channel: UInt32 = 0) -> Bool {
        var property = address(selector, channel), settable = DarwinBoolean(false)
        return AudioObjectHasProperty(device, &property) && AudioObjectIsPropertySettable(device, &property, &settable) == noErr && settable.boolValue
    }
    private func volumeChannels(_ device: AudioDeviceID) -> [UInt32] {
        if writable(device, kAudioDevicePropertyVolumeScalar) { return [0] }
        // Conventional stereo devices expose individual channels; other devices are reported unsupported.
        return [UInt32(1), 2].filter { writable(device, kAudioDevicePropertyVolumeScalar, $0) }
    }
    var supportsVolume: Bool { guard let device = try? device() else { return false }; return !volumeChannels(device).isEmpty }
    var supportsMute: Bool { guard let device = try? device() else { return false }; return writable(device, kAudioDevicePropertyMute) }
    func read(includeMute: Bool = true) -> Double? {
        if includeMute && isMuted() == true { return 0 }
        guard let device = try? device(), let channel = volumeChannels(device).first else { return nil }
        var property = address(kAudioDevicePropertyVolumeScalar, channel), value: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, value.isFinite else { return nil }
        return Double(min(1, max(0, value)))
    }
    func isMuted() -> Bool? {
        guard let device = try? device() else { return nil }
        var property = address(kAudioDevicePropertyMute), value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
    func setMuted(_ muted: Bool) throws {
        let device = try device()
        guard writable(device, kAudioDevicePropertyMute) else {
            throw QuickTileError.unsupported("This output requires its hardware mute control.")
        }
        if muted, isMuted() != true, let key = restoreKey, let level = read(includeMute: false), level > 0 { UserDefaults.standard.set(level, forKey: key) }
        var property = address(kAudioDevicePropertyMute), value: UInt32 = muted ? 1 : 0
        guard AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr,
              isMuted() == muted else { throw QuickTileError.failed("The output device could not change mute state.") }
    }
    func setDialLevel(_ level: Double) throws {
        guard level.isFinite, (0...1).contains(level) else { throw QuickTileError.invalid("Invalid volume level.") }
        if level == 0 {
            // A zero scalar can still be audible on some outputs. Use hardware mute
            // and preserve the underlying level for restoration.
            try setMuted(true)
        } else {
            try execute(.set(level))
            if isMuted() == true { try setMuted(false) }
        }
    }
    func execute(_ command: VolumeCommand) throws {
        let device = try device()
        if case .mute = command {
            guard let muted = isMuted() else { throw QuickTileError.unsupported("This output device does not support software mute. Use its hardware controls.") }
            if muted {
                // Preserve direct changes made on the Mac while muted.
                let current = read(includeMute: false)
                if current == 0, let previous = restoreLevel, supportsVolume { try execute(.set(previous)) }
            }
            try setMuted(!muted)
            return
        }
        let channels = volumeChannels(device)
        guard !channels.isEmpty else { throw QuickTileError.unsupported("This output device does not support software volume. HDMI and some digital outputs require hardware controls.") }
        for channel in channels {
            var property = address(kAudioDevicePropertyVolumeScalar, channel), value: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { throw QuickTileError.failed("Could not read output volume.") }
            switch command { case .up: value += 0.0625; case .down: value -= 0.0625; case .set(let level): value = Float(level); case .mute: break }
            value = min(1, max(0, value))
            guard AudioObjectSetPropertyData(device, &property, 0, nil, size, &value) == noErr else { throw QuickTileError.failed("The output device rejected the volume change.") }
            var observed: Float32 = 0
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &observed) == noErr, abs(observed - value) < 0.025 else { throw QuickTileError.failed("The output device did not confirm the volume change.") }
        }
    }
}

/// DisplayServices controls the actual backlight on supported Apple displays.
/// Load dynamically so missing APIs or unsupported monitors disable the dial.
@MainActor final class BrightnessControl {
    static let shared = BrightnessControl()
    private typealias Read = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Write = @convention(c) (UInt32, Float) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let read: Read?
    private let write: Write?
    private init() {
        library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
        read = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Read.self) }
        write = library.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Write.self) }
    }
    private func level(_ id: UInt32) -> Double? {
        var value: Float = 0
        guard let read, write != nil, CGDisplayIsActive(id) != 0, read(id, &value) == 0,
              value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }
    func snapshot(displayID: UInt32? = nil) -> ControlState {
        let screens = NSScreen.screens.sorted { a, b in
            let aid = (a.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let bid = (b.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(aid) > CGDisplayIsBuiltin(bid)
        }
        let displays = screens.compactMap { screen -> DisplayControlState? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return .init(id: id, name: screen.localizedName, brightness: level(id), builtIn: CGDisplayIsBuiltin(id) != 0)
        }
        let selected = displays.first { $0.id == displayID && $0.brightness != nil } ?? displays.first { $0.brightness != nil }
        let audio = VolumeControl()
        return ControlState(volume: audio.read(), brightness: selected?.brightness, displayID: selected?.id, displayName: selected?.name,
                            muted: audio.isMuted(), outputDeviceID: audio.outputDeviceID, outputDeviceName: audio.outputDeviceName,
                            restoreLevel: audio.restoreLevel, displays: displays)
    }
    func set(_ value: Double, displayID: UInt32) throws {
        guard value.isFinite, (0...1).contains(value), level(displayID) != nil, let write else {
            throw QuickTileError.unsupported("This display does not support brightness control.")
        }
        guard write(displayID, Float(value)) == 0, let observed = level(displayID), abs(observed - value) < 0.04 else { throw QuickTileError.failed("The display did not confirm the brightness change.") }
    }
}
