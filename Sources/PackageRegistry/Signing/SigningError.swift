enum SigningError: Error {
    case invalid(String)
    case signatureInvalid(String)
    case certificateNotTrusted(SigningEntity)
    case certificateInvalid(String)
}
