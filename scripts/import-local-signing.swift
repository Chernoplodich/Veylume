// Imports only a newly generated personal signing identity. No trust settings,
// existing keys, default keychain or search-list changes. Password stays on stdin.
import Foundation
import Security

func check(_ status: OSStatus) throws {
    if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
}
var stage = "input"
do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let payload = try JSONSerialization.jsonObject(with: input) as! [String: String]
    let data = try Data(contentsOf: URL(fileURLWithPath: payload["pkcs12"]!))
    var keychain: SecKeychain?
    stage = "keychain"
    if let path = payload["keychain"] { try check(SecKeychainOpen(path, &keychain)) }
    else { try check(SecKeychainCopyDefault(&keychain)) }
    guard let keychain else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecNoSuchKeychain)) }
    var length: UInt32 = 4096
    var path = [CChar](repeating: 0, count: Int(length))
    try check(SecKeychainGetPath(keychain, &length, &path))
    var status: SecKeychainStatus = 0
    try check(SecKeychainGetStatus(keychain, &status))
    guard status & UInt32(kSecUnlockStateStatus) != 0 else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))
    }
    var previous = DarwinBoolean(false)
    try check(SecKeychainGetUserInteractionAllowed(&previous))
    try check(SecKeychainSetUserInteractionAllowed(false))
    defer { _ = SecKeychainSetUserInteractionAllowed(previous.boolValue) }
    var tool: SecTrustedApplication?
    stage = "access"
    try check(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &tool))
    var access: SecAccess?
    try check(SecAccessCreate("Veylume personal signing key" as CFString, [tool!] as CFArray, &access))
    var items: CFArray?
    stage = "import"
    try check(SecPKCS12Import(data as CFData, [kSecImportExportPassphrase: payload["passphrase"]!,
        kSecImportExportKeychain: keychain, kSecImportExportAccess: access!] as CFDictionary, &items))
    let output = try JSONSerialization.data(withJSONObject: ["keychain": String(cString: path)])
    FileHandle.standardOutput.write(output)
} catch let error as NSError {
    // Never print input, imported contents, keys or passphrases.
    fputs("Personal signing import failed at \(stage) (\(error.code)). Unlock your signing keychain in Keychain Access, then retry.\n", stderr)
    exit(1)
}
