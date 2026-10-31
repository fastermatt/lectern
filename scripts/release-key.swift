// Release signing for Thruline's in-app updater.
//
//   swift scripts/release-key.swift generate          # once: create the key in your login Keychain, print the public key
//   swift scripts/release-key.swift sign <zip>        # writes <zip>.sig (Ed25519 over the ZIP's SHA-256)
//   swift scripts/release-key.swift verify <zip>      # checks <zip>.sig against the public key built into the app
//
// The private key never leaves the maintainer's Keychain (service "Throughline release signing").
// BACK IT UP somewhere safe. If it is lost, existing installs can no longer update in-app and
// people must reinstall manually once; a new public key can then ship in that release.
import CryptoKit
import Foundation

let service = "Throughline release signing", account = "throughline"

func run(_ arguments: [String]) -> (Int32, String) {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    process.standardOutput = pipe; process.standardError = Pipe()
    try? process.run(); process.waitUntilExit()
    return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}

func storedKey() -> Curve25519.Signing.PrivateKey? {
    let (status, output) = run(["find-generic-password", "-s", service, "-a", account, "-w"])
    guard status == 0, let data = Data(base64Encoded: output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

func digest(_ path: String) throws -> Data {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return Data(hasher.finalize())
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "generate":
    if let existing = storedKey() {
        print("A release key already exists. Public key:\n\(existing.publicKey.rawRepresentation.base64EncodedString())"); exit(0)
    }
    let key = Curve25519.Signing.PrivateKey()
    let (status, _) = run(["add-generic-password", "-s", service, "-a", account, "-w", key.rawRepresentation.base64EncodedString(),
                           "-j", "Ed25519 private key that signs Thruline releases for the in-app updater. Back this up."])
    guard status == 0 else { print("Could not store the key in the Keychain."); exit(1) }
    print("Created. Public key (put in AppUpdater.releasePublicKey):\n\(key.publicKey.rawRepresentation.base64EncodedString())")
case "sign":
    guard let path = args.dropFirst().first, let key = storedKey() else { print("usage: sign <zip>  (and run generate first)"); exit(1) }
    let signature = try key.signature(for: digest(path))
    try (signature.base64EncodedString() + "\n").write(toFile: path + ".sig", atomically: true, encoding: .utf8)
    print("Wrote \(path).sig")
case "verify":
    guard let path = args.dropFirst().first else { print("usage: verify <zip>"); exit(1) }
    let source = try String(contentsOfFile: "Sources/StudyTable/AppUpdater.swift", encoding: .utf8)
    guard let line = source.split(separator: "\n").first(where: { $0.contains("static let releasePublicKey") }),
          let encoded = line.split(separator: "\"").dropFirst().first, let raw = Data(base64Encoded: String(encoded)),
          let signature = Data(base64Encoded: try String(contentsOfFile: path + ".sig", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else {
        print("Could not read the public key or signature."); exit(1)
    }
    let ok = try Curve25519.Signing.PublicKey(rawRepresentation: raw).isValidSignature(signature, for: digest(path))
    print(ok ? "Signature valid." : "SIGNATURE INVALID."); exit(ok ? 0 : 1)
default:
    print("usage: swift scripts/release-key.swift generate | sign <zip> | verify <zip>"); exit(1)
}
