import Foundation
import os

/// Everything the spike does is logged here so it can be followed from the terminal:
///   xcrun simctl spawn <udid> log stream --predicate 'subsystem == "dev.lectern.spike"' --style compact
nonisolated let spikeLog = Logger(subsystem: "dev.lectern.spike", category: "externaldisplay")
