import Foundation

enum AppConfig {
    static let supabaseURL = URL(string: "https://rlsexpvcqmntcnihegob.supabase.co")!
    static let supabaseKey = "sb_publishable_TmGgXugasrR5XCAoX-PLiA_FPrkD4vo"

    // From Google Cloud Console → Credentials.
    // iOS client ID is what the GoogleSignIn SDK uses on-device.
    // Web client ID is what Supabase requires as the audience for verifying the ID token.
    static let googleIOSClientID = "515834663717-2ifd5ncgmtq6g8blnncag5nvilksfode.apps.googleusercontent.com"
    static let googleWebClientID = "515834663717-u501cjo8c51e1dq0p1hv82ag5be86bl7.apps.googleusercontent.com"
}
