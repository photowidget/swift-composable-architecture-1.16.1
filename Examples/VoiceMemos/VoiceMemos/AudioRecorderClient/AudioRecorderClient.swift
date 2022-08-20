import Dependencies
import Foundation

extension DependencyValues {
  var audioRecorder: AudioRecorderClient {
    get { self[AudioRecorderClientKey.self] }
    set { self[AudioRecorderClientKey.self] = newValue }
  }

  private enum AudioRecorderClientKey: LiveDependencyKey {
    static let liveValue = AudioRecorderClient.live
    static let testValue = AudioRecorderClient.unimplemented
  }
}

struct AudioRecorderClient {
  var currentTime: @Sendable () async -> TimeInterval?
  var requestRecordPermission: @Sendable () async -> Bool
  var startRecording: @Sendable (URL) async throws -> Bool
  var stopRecording: @Sendable () async -> Void
}
