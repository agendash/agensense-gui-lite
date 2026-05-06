import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let preferredSize = NSSize(width: 1320, height: 900)
    let screenFrame = NSScreen.main?.visibleFrame ?? self.frame
    let windowFrame = NSRect(
      x: screenFrame.midX - preferredSize.width / 2,
      y: screenFrame.midY - preferredSize.height / 2,
      width: preferredSize.width,
      height: preferredSize.height
    )
    self.minSize = NSSize(width: 1080, height: 720)
    self.title = "AgenSense GUI Lite"
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
