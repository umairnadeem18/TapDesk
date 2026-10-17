/**
 * Real release binaries, with the checksums published alongside them.
 *
 * Two rules that are easy to break by accident:
 *
 * 1. The URL pins the tag (eleases/download/v1.0.0-beta.1/...) rather than
 *    using eleases/latest. latest EXCLUDES prereleases, so a beta link
 *    built on it 404s - which is exactly what happened the first time.
 *    Pinning the tag also means the published SHA-256 always belongs to the
 *    file being downloaded.
 *
 * 2. The repo used to be 	apdesk/tapdesk, which does not exist. A visitor
 *    following that link got a 404 with no way to tell why.
 *
 * The APK is split per CPU architecture. arm64-v8a covers essentially every
 * phone made since 2017; armeabi-v7a is the fallback for older or cheaper
 * devices. One universal APK would be 187 MB, so it is not offered.
 */
export const RELEASES = {
  android: {
    version: "v1.0.0-beta.1",
    size: "24.1 MB",
    minAndroid: "Android 8.0 (API 26)",
    // SHA-256 of TapDesk-v1.0.0-beta.1-arm64-v8a.apk
    sha256:
      "632c7f9e911dabdcec3f370ac22db964fe460ca162a3067cabbba0f2cb9f3a4b",
    url: "https://github.com/umairnadeem18/TapDesk/releases/download/v1.0.0-beta.1/TapDesk-v1.0.0-beta.1-arm64-v8a.apk",
    variants: [
      {
        id: "arm64-v8a",
        label: "Most phones (2017 and newer)",
        size: "24.1 MB",
        sha256:
          "632c7f9e911dabdcec3f370ac22db964fe460ca162a3067cabbba0f2cb9f3a4b",
        url: "https://github.com/umairnadeem18/TapDesk/releases/download/v1.0.0-beta.1/TapDesk-v1.0.0-beta.1-arm64-v8a.apk",
      },
      {
        id: "armeabi-v7a",
        label: "Older or budget phones",
        size: "20.0 MB",
        sha256:
          "47cf7c1e8fb1dec7e4fee29ae0ee7343b986d0367dafac50dfc041439b3a9756",
        url: "https://github.com/umairnadeem18/TapDesk/releases/download/v1.0.0-beta.1/TapDesk-v1.0.0-beta.1-armeabi-v7a.apk",
      },
    ],
  },
  windows: {
    version: "not built yet",
    size: "-",
    minWindows: "Windows 10 / 11 (64-bit)",
    // The companion is Phase 5. There is no installer to point at, and
    // publishing an invented checksum or URL would be worse than saying so.
    sha256: "",
    url: "",
  },
};

export const HOW_IT_WORKS = [
  {
    step: "01",
    title: "Install TapDesk on your computer",
    body: "Run the TapDesk desktop companion on Windows. It lives quietly in the system tray, shows a QR code, and never talks to the internet.",
    minutes: "~1 minute",
  },
  {
    step: "02",
    title: "Scan the QR with your phone",
    body: "Open the TapDesk Android app and point the camera at the QR code on screen. Your computer asks for permission — tap Allow.",
    minutes: "~10 seconds",
  },
  {
    step: "03",
    title: "Present from anywhere in the room",
    body: "Use Slides, Mouse and Keyboard tabs to drive your deck, point at the board and type — all over your own Wi-Fi.",
    minutes: "Then just talk",
  },
];

export const PROBLEMS = [
  {
    title: "You are stuck behind the desk",
    body: "The clicker is on the podium, the keyboard is under papers, and reaching either one breaks your flow mid-sentence.",
  },
  {
    title: "No room for a second mouse",
    body: "Lab desks and lecture halls are crowded. Borrowing a wireless receiver from a colleague is a gamble every single class.",
  },
  {
    title: "Guest Wi-Fi blocks device-to-device traffic",
    body: "Most school networks isolate clients, so phone-to-PC control simply will not work on a shared campus network.",
  },
  {
    title: "Cloud remotes leak your keystrokes",
    body: "Consumer remote tools route your input through somebody else's server. For a classroom PC, that is not an acceptable trade.",
  },
];

export const SERVICES = [
  {
    icon: "MousePointer2",
    title: "Wireless mouse",
    tagline: "An analog stick, real clicks.",
    description:
      "Push the stick to move the cursor — direction follows your thumb, distance sets the speed. Tap to click, hold to drag, double-tap to double-click, and swipe the scroll strip to scroll documents without touching the desk.",
    bullets: [
      "Analog stick with tunable speed and acceleration curve",
      "Left / right click, press-and-hold drag, double click",
      "Vertical scroll strip for long documents",
      "Left-handed layout swap and haptic feedback",
    ],
    pain: "Problem: your cursor is bolted to the desk.",
  },
  {
    icon: "Presentation",
    title: "Slide control",
    tagline: "A clicker that never gets lost.",
    description:
      "Two oversized buttons — Previous and Next — sized for a thumb and readable at arm's length. Works with PowerPoint, Google Slides in a browser, LibreOffice Impress and anything that answers arrow keys or Page Up / Page Down.",
    bullets: [
      "Previous / Next with haptic feedback on every press",
      "Start, end and blank-screen shortcuts",
      "Optional volume-key control so your phone can stay pocketed",
      "Slide timer for pacing a lecture",
    ],
    pain: "Problem: you fish the clicker out of your pocket every time you turn around.",
  },
  {
    icon: "Keyboard",
    title: "Full keyboard",
    tagline: "Type without leaving the floor.",
    description:
      "A complete on-screen QWERTY layout plus arrows, F-keys and sticky modifiers, and a Unicode text field that accepts voice typing and any keyboard layout your phone supports — including Urdu.",
    bullets: [
      "Full QWERTY, arrows, F1–F12, Tab, Esc, Enter, Space",
      "Sticky Shift / Ctrl / Alt / Win for shortcuts",
      "Text injection: type with your phone's native keyboard or by voice",
      "Shortcut row: Copy, Paste, Undo, Alt+Tab, Win+D, Ctrl+S",
    ],
    pain: "Problem: the one word you need to type is on a keyboard across the room.",
  },
  {
    icon: "QrCode",
    title: "QR pairing",
    tagline: "Under ten seconds, no typing IPs.",
    description:
      "The desktop app shows a QR code carrying its name, local IP, port and a single-use pairing token. Scan it and you are connected. No accounts, no email, no typing an IP address on a phone keyboard.",
    bullets: [
      "Scan-to-pair in under 10 seconds",
      "Manual fallback: IP address plus a 6-digit PIN",
      "Remembered computers reconnect automatically next launch",
      "Auto-refresh when the computer changes network or IP",
    ],
    pain: "Problem: pairing tools make you type a 192.168.x.x address.",
  },
  {
    icon: "ShieldCheck",
    title: "Secure by design",
    tagline: "Only the paired phone can drive your PC.",
    description:
      "The QR carries a certificate fingerprint that the phone pins, so nobody can sit in the middle. Pairing tokens are random, single-use and expire in two minutes. The computer always shows who is connected and can revoke them instantly.",
    bullets: [
      "Pinned TLS with a one-time pairing token",
      "Explicit Allow / Deny prompt on the computer",
      "Visible connected-device indicator and instant disconnect hotkey",
      "Optional Safe Mode blocking risky shortcuts like Win+R",
    ],
    pain: "Problem: a remote-control tool that pipes your keystrokes through the cloud.",
  },
  {
    icon: "Wifi",
    title: "Offline-first networking",
    tagline: "Your LAN only. No servers involved.",
    description:
      "TapDesk connects directly between your phone and your computer over your own Wi-Fi. Nothing is uploaded, nothing is logged, and there is no TapDesk server to attack or to go down.",
    bullets: [
      "Direct phone-to-PC link, no cloud round trip",
      "Works on school Wi-Fi that allows client traffic",
      "Hotspot fallback when the network isolates devices",
      "No analytics and no personal data in the apps",
    ],
    pain: "Problem: campus Wi-Fi isolates clients, so nothing connects.",
  },
];

export const FAQ = [
  {
    q: "Do my phone and computer have to be on the same Wi-Fi?",
    a: "Yes. TapDesk connects directly over your local network — no internet connection is required at all. If your school Wi-Fi uses client isolation (which blocks device-to-device traffic), connect your computer to your phone's hotspot instead and TapDesk will find it there.",
  },
  {
    q: "Is it safe to let a phone control my computer?",
    a: "The computer cannot be controlled until a QR scan has been paired and you have tapped Allow. Connections are TLS-encrypted and pinned to the certificate fingerprint shown in the QR, pairing tokens are single-use and expire after two minutes, and the desktop app always shows when a phone is connected with a one-click Disconnect and a global hotkey.",
  },
  {
    q: "Do I need an account, subscription or internet connection?",
    a: "No. There is no account, no subscription and no cloud service. Everything runs locally on your own network. That also means nothing you click or type ever leaves your devices.",
  },
  {
    q: "How do I install an APK on Android?",
    a: "Download the APK, then allow your browser to install apps from that source: Settings → Apps → Special access → Install unknown apps → pick your browser → Allow. Then open the downloaded file and tap Install. A Google Play release is in the works for people who prefer the store.",
  },
  {
    q: "Will Windows SmartScreen warn me about the installer?",
    a: "Possibly, if the build is not yet code-signed. TapDesk is unsigned in the early beta, so SmartScreen will show an 'unrecognised app' warning. Click 'More info' then 'Run anyway'. We publish a SHA-256 checksum on the download page so you can verify the file you received.",
  },
  {
    q: "Which platforms are supported?",
    a: "v1 targets Android 8.0 or newer on the phone and Windows 10/11 on the computer. macOS, Linux and iOS companions are on the roadmap, and the desktop companion will be open source.",
  },
];

export const STATS = [
  { value: "< 10s", label: "Median pairing time" },
  { value: "< 50ms", label: "Input latency on Wi-Fi" },
  { value: "0", label: "Bytes sent to any server" },
  { value: "3", label: "Tabs: Slides, Mouse, Keys" },
];