import AppKit

// Nib-less AppKit lifecycle. The delegate builds the menu and windows.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
